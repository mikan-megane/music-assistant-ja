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
containers in the `~/homeassistant` stack.

## Tracking upstream

The workflow runs **daily** (06:00 UTC, after the ~04:04 UTC upstream nightly
release) and builds against the newest upstream **nightly snapshot**
(`MA_SERVER_TAG=2.11.0.dev2026110604` style, resolved via the GitHub API).
The frontend is re-cloned from upstream `main` on every snapshot bump
(`FRONTEND_CLONE_BUST`), so the moving ref is never served stale from the
cache.

Why the nightly snapshots instead of the `beta` tag: `beta` and the nightlies
are cut from the same upstream `dev` branch, but the paused `beta` tag
(`2.11.0b8`, API schema 101) is now older than what frontend `main` requires
(≥ 102) — rebuilding the frontend from `main` and pairing it with `beta`
shows the **"update your server"** wall in the web UI. The daily snapshots
(schema 103 as of 2026-11-06) pair naturally with `frontend/main`.

Publishing:

```
ghcr.io/<owner>/music-assistant-ja:latest
ghcr.io/<owner>/music-assistant-ja:<git-sha>
```

A pre-snapshot of the pre-nightly data is kept at
`raspberrypi4:~/homeassistant/music-assistant-server2.auto-backups/data-predowngrade-2.11.0b8.tar.gz`.
MA migrations are forward-only — if you ever build against an *older* upstream
tag, take a snapshot first:

```bash
docker run --rm -v ~/homeassistant/music-assistant-server2:/data:ro alpine \
  tar czf - -C / data > ~/ma-data-backup.tar.gz
```

Use the manual trigger (`workflow_dispatch`) to pin a specific upstream tag
(`upstream_tag`) and/or override the published tag (`image_tag`).
