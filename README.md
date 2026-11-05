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

Cron (daily 05:10 JST, after the 04:00 watchtower round — see the
"Tracking upstream" section for what the script does):

```
10 5 * * *  /bin/bash /home/mikan/src/music-assistant-ja/scripts/pi-local-build.sh
```

Output is appended to `~/src/music-assistant-ja/pi-local-build.log`.

The service carries `com.centurylinklabs.watchtower.enable=false` so the nickfedor/watchtower container (which still auto-updates Home Assistant etc.) never replaces the locally built image with a registry one.

Rollback: ghcr.io/mikan-megane/music-assistant-ja:beta is still pulled and available locally as a fallback — comment out `build:` and switch `image:` back to `ghcr.io/mikan-megane/music-assistant-ja:beta` in `docker-compose.yml`.

## Tracking upstream (daily, latest stable release)

The cron runs **daily** (05:10 JST) and the script resolves the latest stable
release of [music-assistant/server](https://github.com/music-assistant/server)
via the GitHub API, passing it to the Dockerfile as `MA_SERVER_TAG` (pinned
version tag, e.g. `2.10.9` — never `beta`).

- No new release → the build is a full cache hit (~20 s) and the running container is untouched
- New release (or repo change) → rebuild + one brief restart of the service
- If the GitHub API is unreachable, the run is skipped rather than built against stale input

Pre-swap safety net (on every deploy): `music-assistant-server2` (the `/data`
volume) is tarred to `music-assistant-server2.auto-backups/` and the image the
container was running on is re-tagged as `music-assistant-ja:prev` (last 2
backups kept). Rollback from a bad release:

```bash
# point the service back at the previous image + restore the data snapshot
cp ~/homeassistant/music-assistant-server2.auto-backups/data-<date>.tar.gz /tmp
tar -C /tmp -xzf /tmp/data-<date>.tar.gz   # then manually restore into ~/homeassistant/music-assistant-server2
MA_JA_IMAGE=music-assistant-ja:prev docker compose ... # or edit docker-compose.yml's image:
```

**Note:** the Pi first ran a beta-built image (e.g. `2.11.0b8`). Switching to a
stable release is a *downgrade* — MA's SQLite schema may refuse it. The
automatic data snapshots above are the safety net; check the container logs
after the first stable deploy.

To override the tracked version manually:

```bash
MA_JA_SERVER_TAG=2.10.9 bash ~/src/music-assistant-ja/scripts/pi-local-build.sh
```

GH Actions can still publish a reference image to GHCR via the manual trigger
(`workflow_dispatch`).
