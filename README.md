# KojoStream

KojoStream is a Roku M3U/IPTV player with playlist management, channel browsing, optional XMLTV guide data, and an optional FFmpeg transcode proxy for streams that Roku's native player rejects.

## Roku Sideload Build

From Windows PowerShell:

```powershell
.\build-roku-zip.ps1
```

Upload the generated `KojoStream-sideload.zip` through the Roku developer web installer.

## Transcode Proxy

Some IPTV streams play in VLC/mobile apps but fail on Roku because the HLS segments are not Roku-friendly. The proxy runs FFmpeg on another machine and exposes a Roku-compatible HLS stream.

### Windows

Install FFmpeg, then run:

```powershell
.\start-transcode-proxy.ps1
```

or double-click:

```text
start-transcode-proxy.bat
```

### Docker / Portainer

Use:

```text
docker-compose.transcode.yml
```

More details are in `docs/transcode-proxy-docker.md`.

For NVIDIA GPU encoding, use:

```text
docker-compose.transcode.nvidia.yml
```

The NVIDIA stack expects the Docker host to have working NVIDIA drivers and the NVIDIA Container Toolkit.

## Roku Setting

In the Roku app, set:

```text
Settings > Transcode Server
```

to the machine running the proxy, for example:

```text
http://192.168.0.10:8977
```
