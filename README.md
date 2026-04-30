# KojoStream

KojoStream is a Roku M3U/IPTV player. It loads M3U playlists, displays channels in a vertical TV-style list, supports optional XMLTV guide data, and can fall back to an FFmpeg transcode proxy for streams Roku's native player rejects.

The Roku app does not include content. You provide your own M3U/XMLTV URLs.

## Features

- Add, edit, select, and delete saved playlists on the Roku.
- Store playlist name, M3U URL, and optional XMLTV URL in the Roku registry.
- Parse M3U channel metadata including title, logo, category, `tvg-id`, and common header hints.
- Browse all loaded channels in a vertical up/down list with channel artwork preview.
- Search channels from the side menu.
- Show XMLTV `Now` and `Next` data when the XMLTV feed matches by `tvg-id` or channel title.
- Play channels in picture-in-picture first, then expand to fullscreen.
- Channel up/down while fullscreen.
- Retry playback through direct HLS, local HLS wrapper, and optional transcode proxy.
- Log stream diagnostics for failing channels, including manifest status, MPEG-TS stream types, H.264 details, and AAC details.

## Roku Build And Sideload

From Windows PowerShell:

```powershell
.\build-roku-zip.ps1
```

This creates:

```text
KojoStream-sideload.zip
```

Upload that zip through the Roku developer web installer.

Generated zips are ignored by Git, so rebuilding locally will not dirty the repository.

## App Navigation

### Main Channel List

- `Up/Down`: move through channels.
- `OK`: start the selected channel in the top-right preview.
- `OK` again on the same playing channel: expand fullscreen.
- `Back` while preview is playing: expand fullscreen.
- `Left`: open the side menu.

### Fullscreen Playback

- `Back`: return to the channel list with preview playback.
- `Up`: previous channel.
- `Down`: next channel.
- `Play/Pause`: pause playback.
- `Fast Forward/Rewind`: seek by 10 seconds when the stream supports it.

### Side Menu

- `Home`: return focus to the channel list.
- `Search`: search loaded channels.
- `Playlists`: manage playlist entries.
- `Refresh`: reload the current playlist.
- `Settings`: edit app settings.

### Playlist Manager

- `OK`: select the focused playlist, or add one if the list is empty.
- `*` / Options: add a playlist.
- `Play`: edit the focused playlist.
- `Rewind`: delete the focused playlist.

Adding a playlist asks for:

1. Playlist name.
2. M3U playlist URL.
3. Optional XMLTV URL.

### Settings

- `Up/Down`: move between settings.
- `OK` on `Channel View Mode`: toggles the saved view preference.
- `OK` on `Transcode Server`: enter, update, or turn off the proxy URL.
- `Back`: return to the main app.

The current channel browser is rendered as a vertical guide-style list.

## XMLTV Guide Data

When adding or editing a playlist, you can enter an XMLTV URL. KojoStream downloads the guide feed in the background and maps guide entries to channels by:

- `tvg-id`
- channel title

Matched guide data appears as `Now` and `Next` text while browsing.

## Playback Flow

KojoStream tries to keep native Roku playback first:

1. `hls-direct`: play the original HLS URL directly.
2. `hls-wrapper`: wrap a media playlist in a small local master playlist.
3. `hls-transcode`: use the configured FFmpeg proxy, only when `Settings > Transcode Server` is set.

The transcode fallback is useful for streams that play in VLC/mobile IPTV apps but fail on Roku with errors such as:

```text
Video errorCode: -5 errorMsg: malformed data
```

Common causes include HLS segments that do not start with SPS/PPS/IDR keyframe data, unsupported AAC profiles, unusual segment extensions, or stream layouts Roku's native player is stricter about.

## Transcode Proxy

Roku channels cannot run FFmpeg or transcode video on the Roku device. The proxy must run on another machine on your network, such as:

- Windows PC
- Linux server
- NAS
- Mini PC
- Docker/Portainer host

The Roku app sends the original stream URL to the proxy. The proxy uses FFmpeg to output Roku-friendly HLS, then Roku plays that local network stream.

### Windows Proxy

Install FFmpeg, then run:

```powershell
.\start-transcode-proxy.ps1
```

or double-click:

```text
start-transcode-proxy.bat
```

The launcher prints one or more LAN URLs. Enter the correct one on Roku:

```text
Settings > Transcode Server
```

Example:

```text
http://192.168.0.10:8977
```

### Docker / Portainer

For CPU encoding, use:

```text
docker-compose.transcode.yml
```

For NVIDIA GPU encoding, use:

```text
docker-compose.transcode.nvidia.yml
```

The NVIDIA stack expects working NVIDIA drivers and NVIDIA Container Toolkit on the Docker host.

More detail is in:

```text
docs/transcode-proxy-docker.md
```

## Transcode Quality

The default Docker CPU profile favors higher quality over the earlier low-latency defaults:

```text
KOJO_VIDEO_ENCODER=libx264
KOJO_X264_PRESET=fast
KOJO_X264_CRF=19
KOJO_VIDEO_MAXRATE=10M
KOJO_VIDEO_BUFSIZE=20M
KOJO_AUDIO_BITRATE=160k
KOJO_SINGLE_ACTIVE_STREAM=true
```

Lower `KOJO_X264_CRF` means higher quality and more bitrate. Good live-TV values are usually `18` to `21`.

The NVIDIA profile uses NVENC:

```text
KOJO_VIDEO_ENCODER=h264_nvenc
KOJO_NVENC_PRESET=p7
KOJO_NVENC_TUNE=hq
KOJO_NVENC_CQ=16
KOJO_VIDEO_BITRATE=14M
KOJO_VIDEO_MAXRATE=20M
KOJO_VIDEO_BUFSIZE=40M
KOJO_AUDIO_BITRATE=192k
KOJO_SINGLE_ACTIVE_STREAM=true
```

NVENC is not mathematically lossless, and CPU x264 can still be more efficient at the same bitrate. The advantage of a GPU such as a Quadro P4000 is that it can encode live streams with very little CPU load, letting you use generous bitrate and quality settings for minimal visible loss. The NVIDIA profile intentionally uses more bandwidth to preserve detail; if it still looks too compressed, try `KOJO_NVENC_CQ=14` and `KOJO_VIDEO_MAXRATE=25M`.

`KOJO_SINGLE_ACTIVE_STREAM=true` stops older FFmpeg sessions when a new channel starts. This is intentionally on by default because many IPTV providers limit an account/token to one active stream, and leaving the previous channel transcoding in the background can make the next channel fail.

## Troubleshooting

### Roku Logs

Use the Roku developer console or BrightScript telnet console to read app logs. For telnet:

```sh
telnet ROKU_IP_ADDRESS 8085
```

Useful log lines include:

- `Playback attempt format ...`
- `Video errorCode ...`
- `Stream probe report:`
- `ts_probe=...`
- `h264_sps=...`
- `aac_probe=...`

### Proxy Logs

The proxy prints HTTP requests and FFmpeg startup details. If a channel takes a while to load, FFmpeg may be waiting for clean H.264 headers/keyframes before it can produce Roku-friendly HLS.

In Docker:

```sh
docker logs -f kojostream-transcode
```

When switching channels, healthy proxy logs should include lines like:

```text
HLS request session=... source_host=...
Stopping previous transcode session ... before starting ...
```

To check NVENC availability:

```sh
docker exec kojostream-transcode ffmpeg -hide_banner -encoders | grep nvenc
```

### Common Issues

- `FFmpeg was not found on PATH`: install FFmpeg, then restart PowerShell.
- Roku cannot reach proxy: use the Docker/PC LAN IP, not `localhost` or `0.0.0.0`.
- Proxy starts but Roku still fails: check firewall rules for port `8977`.
- NVENC not found: verify NVIDIA drivers and NVIDIA Container Toolkit on the Docker host.
- Slow first playback: expected for damaged/non-Roku-friendly streams while FFmpeg waits for usable keyframes.

## Repository Layout

```text
components/                         Roku SceneGraph components
components/tasks/M3uLoader.*         M3U download and parser task
components/tasks/XmltvLoader.*       XMLTV download and guide parser task
components/tasks/StreamProbeTask.*   Stream diagnostics task
source/main.brs                      Roku app entrypoint
images/                              Roku app artwork
tools/kojostream_transcode_proxy.py  FFmpeg HLS proxy
Dockerfile.transcode                 Docker image for the proxy
docker-compose.transcode.yml         CPU transcode stack
docker-compose.transcode.nvidia.yml  NVIDIA/NVENC transcode stack
docs/transcode-proxy-docker.md       Detailed Docker/Portainer guide
build-roku-zip.ps1                   Roku sideload zip builder
```

## Git Hygiene

The repo ignores generated and local-only files:

- `KojoStream-sideload.zip`
- `KojoStream.zip`
- captured test streams such as `seg.ts`
- local playlist dumps such as `tmp_playlist.m3u`
- `.claude/`
- Python cache files

This keeps private test data and generated artifacts out of GitHub.
