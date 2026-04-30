# KojoStream Transcode Proxy on Docker/Portainer

The Roku app cannot transcode on the Roku device itself. This container runs the KojoStream FFmpeg proxy on another machine and exposes Roku-friendly HLS on port `8977`.

## Portainer Stack

Use `docker-compose.transcode.yml` as the stack file:

```yaml
services:
  kojostream-transcode:
    image: kojostream-transcode:latest
    build:
      context: .
      dockerfile: Dockerfile.transcode
    container_name: kojostream-transcode
    restart: unless-stopped
    ports:
      - "8977:8977"
    environment:
      KOJO_VIDEO_ENCODER: libx264
      KOJO_X264_PRESET: fast
      KOJO_X264_CRF: "19"
      KOJO_VIDEO_MAXRATE: 10M
      KOJO_VIDEO_BUFSIZE: 20M
      KOJO_AUDIO_BITRATE: 160k
      KOJO_SINGLE_ACTIVE_STREAM: "true"
      KOJO_STARTUP_RETRIES: "3"
    volumes:
      - kojostream-transcode-cache:/cache

volumes:
  kojostream-transcode-cache:
```

If your Portainer stack is created from a Git repository, point it at this repo and set the compose path to:

```text
docker-compose.transcode.yml
```

Portainer needs access to the Docker build context. The easiest path is a Git-backed stack pointed at this repository. If you use Portainer's web editor without a Git repository, prebuild the image on the Docker host first, then deploy a stack that references `kojostream-transcode:latest`.

## Quality Settings

The default Docker stack uses higher-quality CPU encoding:

```yaml
environment:
  KOJO_VIDEO_ENCODER: libx264
  KOJO_X264_PRESET: fast
  KOJO_X264_CRF: "19"
  KOJO_VIDEO_MAXRATE: 10M
  KOJO_VIDEO_BUFSIZE: 20M
  KOJO_AUDIO_BITRATE: 160k
  KOJO_SINGLE_ACTIVE_STREAM: "true"
  KOJO_STARTUP_RETRIES: "3"
```

Lower CRF means higher quality and larger bitrate. Good CPU values are usually `18` to `21`. Slower presets such as `medium` can look slightly better at the same bitrate, but use more CPU.

`KOJO_SINGLE_ACTIVE_STREAM` is on by default. When Roku starts a different transcoded channel, the proxy stops older FFmpeg sessions first. This helps providers that reject multiple simultaneous streams from the same account/token.

`KOJO_STARTUP_RETRIES` controls how many times the proxy restarts FFmpeg if it exits before producing an HLS playlist. Early FFmpeg exits are logged with the exit code and recent FFmpeg output.

## NVIDIA NVENC

If the Docker host has an NVIDIA GPU such as a Quadro P4000 and the NVIDIA Container Toolkit is installed, use:

```text
docker-compose.transcode.nvidia.yml
```

That stack uses:

```yaml
environment:
  NVIDIA_VISIBLE_DEVICES: all
  NVIDIA_DRIVER_CAPABILITIES: compute,video,utility
  KOJO_VIDEO_ENCODER: h264_nvenc
  KOJO_NVENC_PRESET: p7
  KOJO_NVENC_TUNE: hq
  KOJO_NVENC_CQ: "16"
  KOJO_VIDEO_BITRATE: 14M
  KOJO_VIDEO_MAXRATE: 20M
  KOJO_VIDEO_BUFSIZE: 40M
  KOJO_AUDIO_BITRATE: 192k
  KOJO_SINGLE_ACTIVE_STREAM: "true"
  KOJO_STARTUP_RETRIES: "3"
```

NVENC is much easier on the CPU and is a good fit for live TV. It is not mathematically lossless, but the NVIDIA stack is tuned to spend bitrate for quality: `cq=16`, `14M` target, and `20M` max. If the stream still looks too compressed, try `KOJO_NVENC_CQ=14` and `KOJO_VIDEO_MAXRATE=25M`. If bandwidth matters more than quality, try `cq=18-20` and `maxrate=10M-14M`.

To confirm the container can see NVENC:

```sh
docker exec kojostream-transcode ffmpeg -hide_banner -encoders | grep nvenc
```

If no NVENC encoders appear, check the host's NVIDIA driver and NVIDIA Container Toolkit installation.

## Manual Docker Build

From the project directory on the Docker host:

```sh
docker build -f Dockerfile.transcode -t kojostream-transcode:latest .
docker run -d --name kojostream-transcode --restart unless-stopped -p 8977:8977 -v kojostream-transcode-cache:/cache kojostream-transcode:latest
```

For a prebuilt-image Portainer stack, use:

```yaml
services:
  kojostream-transcode:
    image: kojostream-transcode:latest
    container_name: kojostream-transcode
    restart: unless-stopped
    ports:
      - "8977:8977"
    environment:
      KOJO_VIDEO_ENCODER: libx264
      KOJO_X264_PRESET: fast
      KOJO_X264_CRF: "19"
      KOJO_VIDEO_MAXRATE: 10M
      KOJO_VIDEO_BUFSIZE: 20M
      KOJO_AUDIO_BITRATE: 160k
      KOJO_SINGLE_ACTIVE_STREAM: "true"
      KOJO_STARTUP_RETRIES: "3"
    volumes:
      - kojostream-transcode-cache:/cache

volumes:
  kojostream-transcode-cache:
```

## Roku Setting

In the Roku app, set:

```text
Settings > Transcode Server
```

to the Docker host LAN URL:

```text
http://YOUR_PORTAINER_HOST_IP:8977
```

For example:

```text
http://192.168.0.10:8977
```

## Health Check

From another machine on the LAN:

```sh
curl http://YOUR_PORTAINER_HOST_IP:8977/health
```

Expected response:

```text
ok
```
