#!/usr/bin/env python3
import argparse
import hashlib
import json
import mimetypes
import os
import shutil
import subprocess
import tempfile
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse


class TranscodeSession:
    def __init__(self, session_id, source_url, headers, root_dir, ffmpeg_path, settings):
        self.session_id = session_id
        self.source_url = source_url
        self.headers = headers
        self.root_dir = root_dir
        self.ffmpeg_path = ffmpeg_path
        self.settings = settings
        self.work_dir = root_dir / session_id
        self.playlist_path = self.work_dir / "stream.m3u8"
        self.log_path = self.work_dir / "ffmpeg.log"
        self.process = None
        self.lock = threading.Lock()
        self.last_access = time.time()
        self.closed = False
        self.start_attempts = 0

    def ensure_running(self):
        with self.lock:
            if self.closed:
                return False

            self.last_access = time.time()
            if self.process is not None and self.process.poll() is None:
                return True

            self.work_dir.mkdir(parents=True, exist_ok=True)
            for old_file in self.work_dir.glob("*"):
                if old_file.name != "ffmpeg.log":
                    old_file.unlink(missing_ok=True)

            cmd = self._build_ffmpeg_command()
            self.start_attempts += 1
            print(f"Starting FFmpeg session {self.session_id} attempt={self.start_attempts}", flush=True)
            log_file = self.log_path.open("ab")
            log_file.write(("\n\n--- starting ffmpeg " + time.ctime() + " ---\n").encode("utf-8"))
            log_file.write((" ".join(cmd) + "\n").encode("utf-8"))
            log_file.flush()

            self.process = subprocess.Popen(
                cmd,
                stdout=log_file,
                stderr=log_file,
                cwd=str(self.work_dir),
            )
            return True

    def stop(self, final=False):
        with self.lock:
            if final:
                self.closed = True
            if self.process is not None and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            self.process = None

    def is_closed(self):
        with self.lock:
            return self.closed

    def wait_for_playlist(self, timeout_seconds=90):
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            if self.is_closed():
                return False
            if self.playlist_path.exists():
                text = self.playlist_path.read_text("utf-8", errors="ignore")
                if ".ts" in text:
                    return True
            if self.process is not None:
                exit_code = self.process.poll()
            else:
                exit_code = None
            if exit_code is not None:
                self.report_process_exit(exit_code)
                if self.start_attempts >= parse_int(self.settings["startup_retries"], 3):
                    return False
                time.sleep(2)
                if not self.ensure_running():
                    return False
            time.sleep(0.25)
        return False

    def read_log_tail(self, max_chars=2500):
        if not self.log_path.exists():
            return ""
        text = self.log_path.read_text("utf-8", errors="ignore")
        return text[-max_chars:]

    def report_process_exit(self, exit_code):
        print(
            f"FFmpeg session {self.session_id} exited before playlist was ready. exit_code={exit_code}",
            flush=True,
        )
        log_tail = self.read_log_tail()
        if log_tail:
            print(f"Recent FFmpeg output for session {self.session_id}:", flush=True)
            print(log_tail, flush=True)

    def _build_ffmpeg_command(self):
        cmd = [
            self.ffmpeg_path,
            "-hide_banner",
            "-loglevel",
            "warning",
            "-fflags",
            "+genpts",
            "-probesize",
            "5000000",
            "-analyzeduration",
            "5000000",
            "-allowed_extensions",
            "ALL",
        ]

        if self.headers.get("User-Agent"):
            cmd.extend(["-user_agent", self.headers["User-Agent"]])

        header_lines = []
        for key in ["Referer", "Origin", "Cookie"]:
            if self.headers.get(key):
                header_lines.append(f"{key}: {self.headers[key]}")
        if header_lines:
            cmd.extend(["-headers", "\r\n".join(header_lines) + "\r\n"])

        cmd.extend(["-i", self.source_url, "-map", "0:v:0", "-map", "0:a:0?"])
        cmd.extend(self._build_video_args())
        cmd.extend(
            [
                "-c:a",
                "aac",
                "-b:a",
                self.settings["audio_bitrate"],
                "-ac",
                "2",
                "-ar",
                "48000",
                "-f",
                "hls",
                "-hls_time",
                self.settings["hls_time"],
                "-hls_list_size",
                self.settings["hls_list_size"],
                "-hls_delete_threshold",
                self.settings["hls_delete_threshold"],
                "-hls_flags",
                "delete_segments+independent_segments+program_date_time",
                "-hls_segment_filename",
                "seg_%06d.ts",
                "stream.m3u8",
            ]
        )
        return cmd

    def _build_video_args(self):
        encoder = self.settings["video_encoder"].lower()
        keyframe_seconds = self.settings["keyframe_seconds"]
        force_keyframes = "expr:gte(t,n_forced*" + keyframe_seconds + ")"

        if encoder in ("h264_nvenc", "nvenc"):
            return [
                "-c:v",
                "h264_nvenc",
                "-preset",
                self.settings["nvenc_preset"],
                "-tune",
                self.settings["nvenc_tune"],
                "-rc",
                "vbr",
                "-cq",
                self.settings["nvenc_cq"],
                "-b:v",
                self.settings["video_bitrate"],
                "-maxrate",
                self.settings["video_maxrate"],
                "-bufsize",
                self.settings["video_bufsize"],
                "-profile:v",
                "high",
                "-level:v",
                self.settings["h264_level"],
                "-pix_fmt",
                "yuv420p",
                "-g",
                self.settings["gop_size"],
                "-forced-idr",
                "1",
                "-force_key_frames",
                force_keyframes,
            ]

        args = [
            "-c:v",
            "libx264",
            "-preset",
            self.settings["x264_preset"],
            "-crf",
            self.settings["x264_crf"],
            "-profile:v",
            "high",
            "-level:v",
            self.settings["h264_level"],
            "-pix_fmt",
            "yuv420p",
            "-maxrate",
            self.settings["video_maxrate"],
            "-bufsize",
            self.settings["video_bufsize"],
            "-x264-params",
            "keyint=" + self.settings["gop_size"] + ":min-keyint=" + self.settings["gop_size"] + ":scenecut=0:repeat-headers=1",
            "-force_key_frames",
            force_keyframes,
        ]

        if self.settings["x264_tune"]:
            args.extend(["-tune", self.settings["x264_tune"]])

        return args


class SessionManager:
    def __init__(self, ffmpeg_path, root_dir, settings):
        self.ffmpeg_path = ffmpeg_path
        self.root_dir = root_dir
        self.settings = settings
        self.single_active_stream = settings["single_active_stream"]
        self.sessions = {}
        self.lock = threading.Lock()
        root_dir.mkdir(parents=True, exist_ok=True)
        self.cleanup_thread = threading.Thread(target=self.cleanup_loop, daemon=True)
        self.cleanup_thread.start()

    def get_session(self, source_url, headers):
        fingerprint = json.dumps(
            {"url": source_url, "headers": headers},
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        session_id = hashlib.sha1(fingerprint).hexdigest()[:16]
        with self.lock:
            session = self.sessions.get(session_id)
            if session is None:
                session = TranscodeSession(
                    session_id,
                    source_url,
                    headers,
                    self.root_dir,
                    self.ffmpeg_path,
                    self.settings,
                )
                self.sessions[session_id] = session
            return session

    def activate_session(self, active_session):
        if not self.single_active_stream:
            return

        sessions_to_stop = []
        with self.lock:
            for session_id, session in list(self.sessions.items()):
                if session is active_session:
                    continue
                sessions_to_stop.append((session_id, session))
                del self.sessions[session_id]

        for session_id, session in sessions_to_stop:
            print(
                f"Stopping previous transcode session {session_id} before starting {active_session.session_id}",
                flush=True,
            )
            session.stop(final=True)
            shutil.rmtree(session.work_dir, ignore_errors=True)

    def cleanup_loop(self):
        while True:
            time.sleep(300)
            self.cleanup_inactive_sessions(max_idle_seconds=1800)

    def cleanup_inactive_sessions(self, max_idle_seconds):
        cutoff = time.time() - max_idle_seconds
        stale_sessions = []
        with self.lock:
            for session_id, session in list(self.sessions.items()):
                if session.last_access < cutoff:
                    stale_sessions.append((session_id, session))
                    del self.sessions[session_id]

        for session_id, session in stale_sessions:
            print(f"Cleaning up inactive transcode session {session_id}", flush=True)
            session.stop(final=True)
            shutil.rmtree(session.work_dir, ignore_errors=True)


class ProxyHandler(BaseHTTPRequestHandler):
    manager = None

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_text("ok\n", "text/plain")
            return

        if parsed.path == "/hls":
            self.handle_hls(parsed)
            return

        if parsed.path.startswith("/session/"):
            self.handle_session_file(parsed)
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def handle_hls(self, parsed):
        query = parse_qs(parsed.query)
        source_values = query.get("url", [])
        if not source_values:
            self.send_error(HTTPStatus.BAD_REQUEST, "Missing url query parameter")
            return

        source_url = source_values[0]
        headers = {
            "User-Agent": first_query_value(query, "ua"),
            "Referer": first_query_value(query, "ref"),
            "Origin": first_query_value(query, "origin"),
            "Cookie": first_query_value(query, "cookie"),
        }
        headers = {key: value for key, value in headers.items() if value}

        session = self.manager.get_session(source_url, headers)
        source_host = urlparse(source_url).netloc
        print(
            f"HLS request session={session.session_id} source_host={source_host} path={urlparse(source_url).path}",
            flush=True,
        )
        self.manager.activate_session(session)
        if not session.ensure_running():
            self.send_error(HTTPStatus.CONFLICT, "Transcode session was replaced by a newer channel request.")
            return
        if not session.wait_for_playlist():
            if session.is_closed():
                print(f"HLS request session={session.session_id} closed before playlist was ready", flush=True)
                self.send_error(HTTPStatus.CONFLICT, "Transcode session was replaced by a newer channel request.")
                return
            log_tail = session.read_log_tail()
            if log_tail:
                print("FFmpeg did not produce an HLS playlist. Recent log output:", flush=True)
                print(log_tail, flush=True)
            self.send_error(
                HTTPStatus.BAD_GATEWAY,
                "FFmpeg did not produce an HLS playlist in time. Check the proxy window for recent FFmpeg output.",
            )
            return

        playlist = session.playlist_path.read_text("utf-8", errors="ignore")
        playlist = self.rewrite_playlist(playlist, session.session_id)
        print(f"HLS playlist ready session={session.session_id}", flush=True)
        self.send_text(playlist, "application/vnd.apple.mpegurl")

    def handle_session_file(self, parsed):
        parts = parsed.path.split("/")
        if len(parts) != 4:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return

        session_id = parts[2]
        filename = Path(unquote(parts[3])).name
        session = self.manager.sessions.get(session_id)
        if session is None:
            self.send_error(HTTPStatus.NOT_FOUND, "Unknown session")
            return

        session.last_access = time.time()
        file_path = session.work_dir / filename
        if not file_path.exists() or not file_path.is_file():
            self.send_error(HTTPStatus.NOT_FOUND, "Segment not found")
            return

        content_type = mimetypes.guess_type(file_path.name)[0]
        if file_path.suffix == ".ts":
            content_type = "video/mp2t"
        elif file_path.suffix == ".m3u8":
            content_type = "application/vnd.apple.mpegurl"

        data = file_path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def rewrite_playlist(self, playlist, session_id):
        base_url = f"http://{self.headers.get('Host')}"
        rewritten = []
        for line in playlist.splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#"):
                rewritten.append(f"{base_url}/session/{session_id}/{quote(stripped)}")
            else:
                rewritten.append(line)
        return "\n".join(rewritten) + "\n"

    def send_text(self, text, content_type):
        data = text.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)


def first_query_value(query, key):
    values = query.get(key, [])
    if not values:
        return ""
    return values[0]


def build_transcode_settings(args):
    return {
        "video_encoder": args.video_encoder,
        "x264_preset": args.x264_preset,
        "x264_crf": args.x264_crf,
        "x264_tune": args.x264_tune,
        "nvenc_preset": args.nvenc_preset,
        "nvenc_tune": args.nvenc_tune,
        "nvenc_cq": args.nvenc_cq,
        "video_bitrate": args.video_bitrate,
        "video_maxrate": args.video_maxrate,
        "video_bufsize": args.video_bufsize,
        "h264_level": args.h264_level,
        "audio_bitrate": args.audio_bitrate,
        "hls_time": args.hls_time,
        "hls_list_size": args.hls_list_size,
        "hls_delete_threshold": args.hls_delete_threshold,
        "keyframe_seconds": args.keyframe_seconds,
        "gop_size": args.gop_size,
        "single_active_stream": parse_bool(args.single_active_stream),
        "startup_retries": args.startup_retries,
    }


def parse_bool(value):
    if value is None:
        return False
    return value.strip().lower() in ("1", "true", "yes", "y", "on")


def parse_int(value, default_value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default_value


def main():
    parser = argparse.ArgumentParser(description="KojoStream FFmpeg HLS transcode proxy")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8977)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument(
        "--work-dir",
        default=str(Path(tempfile.gettempdir()) / "kojostream-transcode-proxy"),
    )
    parser.add_argument("--video-encoder", default=os.getenv("KOJO_VIDEO_ENCODER", "libx264"))
    parser.add_argument("--x264-preset", default=os.getenv("KOJO_X264_PRESET", "fast"))
    parser.add_argument("--x264-crf", default=os.getenv("KOJO_X264_CRF", "19"))
    parser.add_argument("--x264-tune", default=os.getenv("KOJO_X264_TUNE", ""))
    parser.add_argument("--nvenc-preset", default=os.getenv("KOJO_NVENC_PRESET", "p5"))
    parser.add_argument("--nvenc-tune", default=os.getenv("KOJO_NVENC_TUNE", "hq"))
    parser.add_argument("--nvenc-cq", default=os.getenv("KOJO_NVENC_CQ", "19"))
    parser.add_argument("--video-bitrate", default=os.getenv("KOJO_VIDEO_BITRATE", "8M"))
    parser.add_argument("--video-maxrate", default=os.getenv("KOJO_VIDEO_MAXRATE", "10M"))
    parser.add_argument("--video-bufsize", default=os.getenv("KOJO_VIDEO_BUFSIZE", "20M"))
    parser.add_argument("--h264-level", default=os.getenv("KOJO_H264_LEVEL", "4.2"))
    parser.add_argument("--audio-bitrate", default=os.getenv("KOJO_AUDIO_BITRATE", "160k"))
    parser.add_argument("--hls-time", default=os.getenv("KOJO_HLS_TIME", "2"))
    parser.add_argument("--hls-list-size", default=os.getenv("KOJO_HLS_LIST_SIZE", "8"))
    parser.add_argument("--hls-delete-threshold", default=os.getenv("KOJO_HLS_DELETE_THRESHOLD", "4"))
    parser.add_argument("--keyframe-seconds", default=os.getenv("KOJO_KEYFRAME_SECONDS", "2"))
    parser.add_argument("--gop-size", default=os.getenv("KOJO_GOP_SIZE", "60"))
    parser.add_argument(
        "--single-active-stream",
        default=os.getenv("KOJO_SINGLE_ACTIVE_STREAM", "true"),
        help="Stop other active FFmpeg sessions when a new channel starts. Helps IPTV providers with one-stream limits.",
    )
    parser.add_argument(
        "--startup-retries",
        default=os.getenv("KOJO_STARTUP_RETRIES", "3"),
        help="How many times to restart FFmpeg if it exits before producing an HLS playlist.",
    )
    args = parser.parse_args()

    if shutil.which(args.ffmpeg) is None and not Path(args.ffmpeg).exists():
        raise SystemExit("ffmpeg was not found. Install FFmpeg and make sure ffmpeg is on PATH.")

    settings = build_transcode_settings(args)
    manager = SessionManager(args.ffmpeg, Path(args.work_dir), settings)
    ProxyHandler.manager = manager

    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    print(f"KojoStream transcode proxy listening on http://{args.host}:{args.port}", flush=True)
    print("Set the Roku app Transcode Server setting to this PC's LAN URL, for example http://192.168.1.25:8977", flush=True)
    print("Transcode settings: " + json.dumps(settings, sort_keys=True), flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
