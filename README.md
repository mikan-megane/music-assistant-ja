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
ghcr.io/<owner>/music-assistant-ja:<MA server version>
ghcr.io/<owner>/music-assistant-ja:<git-sha>
```

Built by GitHub Actions (daily cron + push to `main` + manual trigger) on the
native arm64 runner, `linux/arm64` only.

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

## Raspberry Pi deployment

`raspberrypi4` pulls the image automatically every day 04:00 JST with the
nickfedor/watchtower container (Discord notifications), just like the other
containers in the `~/homeassistant` stack. The Dockerfile's `:latest` tag is
rebuilt daily by this workflow whenever upstream releases something new.

Previously the image was built locally on the Pi via cron
(`scripts/pi-local-build.sh`) — that script is kept for emergencies
(self-contained: resolves the latest stable release, builds arm64 natively
and swaps the service) but is not wired to a cron anymore, and the current
compose file references the registry image directly.

## Tracking upstream

The workflow runs **daily** (04:00 UTC) and builds against the **latest stable
release** of [music-assistant/server](https://github.com/music-assistant/server)
(resolved via the GitHub API, e.g. `2.10.9` — never `beta`). Publishing:

```
ghcr.io/<owner>/music-assistant-ja:latest   # daily stable-tracking build
ghcr.io/<owner>/music-assistant-ja:<ver>    # the MA server version it was built against
ghcr.io/<owner>/music-assistant-ja:<sha>
```

`FRONTEND_CLONE_BUST` is set to the tracked release, so the frontend is
re-cloned from upstream `main` on every release bump (a moving ref would
otherwise be forever cached). No new release = cache hit = ~seconds build.

Use the manual trigger (`workflow_dispatch`) with `upstream_tag` to target a
specific release (`latest image tag` can be overridden via `image_tag`).
