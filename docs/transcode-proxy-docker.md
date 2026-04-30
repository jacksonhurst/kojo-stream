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
