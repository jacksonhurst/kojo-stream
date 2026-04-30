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
    def __init__(self, session_id, source_url, headers, root_dir, ffmpeg_path):
        self.session_id = session_id
        self.source_url = source_url
        self.headers = headers
        self.root_dir = root_dir
        self.ffmpeg_path = ffmpeg_path
        self.work_dir = root_dir / session_id
        self.playlist_path = self.work_dir / "stream.m3u8"
        self.log_path = self.work_dir / "ffmpeg.log"
        self.process = None
        self.lock = threading.Lock()
        self.last_access = time.time()

    def ensure_running(self):
        with self.lock:
            self.last_access = time.time()
            if self.process is not None and self.process.poll() is None:
                return

            self.work_dir.mkdir(parents=True, exist_ok=True)
            for old_file in self.work_dir.glob("*"):
                if old_file.name != "ffmpeg.log":
                    old_file.unlink(missing_ok=True)

            cmd = self._build_ffmpeg_command()
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

    def stop(self):
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            self.process = None

    def wait_for_playlist(self, timeout_seconds=90):
        deadline = time.time() + timeout_seconds
        while time.time() < deadline:
            if self.playlist_path.exists():
                text = self.playlist_path.read_text("utf-8", errors="ignore")
                if ".ts" in text:
                    return True
            if self.process is not None and self.process.poll() is not None:
                time.sleep(2)
                self.ensure_running()
            time.sleep(0.25)
        return False

    def read_log_tail(self, max_chars=2500):
        if not self.log_path.exists():
            return ""
        text = self.log_path.read_text("utf-8", errors="ignore")
        return text[-max_chars:]

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

        cmd.extend(
            [
                "-i",
                self.source_url,
                "-map",
                "0:v:0",
                "-map",
                "0:a:0?",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-tune",
                "zerolatency",
                "-profile:v",
                "high",
                "-level:v",
                "4.1",
                "-pix_fmt",
                "yuv420p",
                "-x264-params",
                "keyint=60:min-keyint=60:scenecut=0:repeat-headers=1",
                "-force_key_frames",
                "expr:gte(t,n_forced*2)",
                "-c:a",
                "aac",
                "-b:a",
                "128k",
                "-ac",
                "2",
                "-ar",
                "48000",
                "-f",
                "hls",
                "-hls_time",
                "2",
                "-hls_list_size",
                "8",
                "-hls_delete_threshold",
                "4",
                "-hls_flags",
                "delete_segments+independent_segments+program_date_time",
                "-hls_segment_filename",
                "seg_%06d.ts",
                "stream.m3u8",
            ]
        )
        return cmd


class SessionManager:
    def __init__(self, ffmpeg_path, root_dir):
        self.ffmpeg_path = ffmpeg_path
        self.root_dir = root_dir
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
                )
                self.sessions[session_id] = session
            return session

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
            print(f"Cleaning up inactive transcode session {session_id}")
            session.stop()
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
        session.ensure_running()
        if not session.wait_for_playlist():
            log_tail = session.read_log_tail()
            if log_tail:
                print("FFmpeg did not produce an HLS playlist. Recent log output:")
                print(log_tail)
            self.send_error(
                HTTPStatus.BAD_GATEWAY,
                "FFmpeg did not produce an HLS playlist in time. Check the proxy window for recent FFmpeg output.",
            )
            return

        playlist = session.playlist_path.read_text("utf-8", errors="ignore")
        playlist = self.rewrite_playlist(playlist, session.session_id)
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
        print(f"{self.address_string()} - {fmt % args}")


def first_query_value(query, key):
    values = query.get(key, [])
    if not values:
        return ""
    return values[0]


def main():
    parser = argparse.ArgumentParser(description="KojoStream FFmpeg HLS transcode proxy")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8977)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "ffmpeg")
    parser.add_argument(
        "--work-dir",
        default=str(Path(tempfile.gettempdir()) / "kojostream-transcode-proxy"),
    )
    args = parser.parse_args()

    if shutil.which(args.ffmpeg) is None and not Path(args.ffmpeg).exists():
        raise SystemExit("ffmpeg was not found. Install FFmpeg and make sure ffmpeg is on PATH.")

    manager = SessionManager(args.ffmpeg, Path(args.work_dir))
    ProxyHandler.manager = manager

    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    print(f"KojoStream transcode proxy listening on http://{args.host}:{args.port}")
    print("Set the Roku app Transcode Server setting to this PC's LAN URL, for example http://192.168.1.25:8977")
    server.serve_forever()


if __name__ == "__main__":
    main()
