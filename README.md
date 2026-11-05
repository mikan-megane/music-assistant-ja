# music-assistant-ja

Music Assistant server Docker image with the Japanese (`ja`) translation injected into the bundled frontend.

## What this does

The upstream [music-assistant/frontend](https://github.com/music-assistant/frontend) repo ships ~30 locales; Japanese (`ja`) is not yet among them. This image:

1. Clones upstream `music-assistant/frontend`
2. Drops [`ja.json`](./ja.json) into `src/translations/`
3. Runs `pnpm install` + `vite build` (so the locale is compiled exactly like the others)
4. Copies the built `music_assistant_frontend/` package over the one bundled inside `ghcr.io/music-assistant/server`

## Image

Published to GHCR by GitHub Actions:

```
ghcr.io/<owner>/music-assistant-ja:latest
ghcr.io/<owner>/music-assistant-ja:beta
ghcr.io/<owner>/music-assistant-ja:<git-sha>
```

Multi-arch: `linux/arm64` + `linux/amd64`. Only built on push to `main` or a manual trigger — the weekly cron was removed in favour of local builds on the Raspberry Pi (below).

## Usage

```yaml
# docker-compose.yml
services:
  music-assistant-server:
    image: ghcr.io/<owner>/music-assistant-ja:latest
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./music-assistant-server2:/data/
    cap_add:
      - SYS_ADMIN
      - DAC_READ_SEARCH
    security_opt:
      - apparmor:unconfined
    environment:
      - LOG_LEVEL=info
```

The UI auto-detects Japanese from `navigator.language`. To switch manually, open **Settings → Language**.

## Updating `ja.json`

Edit `ja.json` and push to `main` — the workflow rebuilds automatically.

## Local builds on the Raspberry Pi

The Pi that runs the image (`raspberrypi4`) builds it itself — no GH Actions runner involved, arm64 native, no QEMU.

1. Repo clone on the Pi: `~/src/music-assistant-ja` (the compose file's `build:` context points here)
2. `bash scripts/pi-local-build.sh` does: `git pull` → `docker compose -f ~/homeassistant/docker-compose.yml build --pull music-assistant-server` → `up -d` (that service only)
3. Built, tagged and started as `music-assistant-ja:local`. If the build fails, the running container is left untouched

Cron (Mon 05:10 JST, after the 04:00 watchtower round):

```
10 5 * * 1  /bin/bash /home/mikan/src/music-assistant-ja/scripts/pi-local-build.sh
```

Output is appended to `~/src/music-assistant-ja/pi-local-build.log`.

The service carries `com.centurylinklabs.watchtower.enable=false` so the nickfedor/watchtower container (which still auto-updates Home Assistant etc.) never replaces the locally built image with a registry one.

Rollback: ghcr.io/mikan-megane/music-assistant-ja:beta is still pulled and available locally as a fallback — comment out `build:` and switch `image:` back to `ghcr.io/mikan-megane/music-assistant-ja:beta` in `docker-compose.yml`.

## Tracking upstream

Local builds are against the upstream `beta` channel (Dockerfile `MA_SERVER_TAG` default). The `--pull` in `build` re-resolves `ghcr.io/music-assistant/server:beta` each run, so upstream beta updates are picked up automatically on the next weekly build. To target a specific MA server release, change `MA_SERVER_TAG` in `docker-compose.yml` (or pass `--build-arg` via a manual build). GH Actions can still publish a reference image to GHCR via the manual trigger (`workflow_dispatch`).
