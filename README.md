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

The workflow runs **daily** (04:00 UTC) and builds against the upstream
**`beta`** channel (`MA_SERVER_TAG=beta`). The frontend is re-cloned from
upstream `main` on every build (`FRONTEND_CLONE_BUST=$(date -u +%F)`) so a
moving ref is never served stale from the cache.

Why beta and not the latest stable release: the deployed instance ran a beta
(`2.11.0b8`) whose SQLite schema was migrated forward, and MA migrations are
**forward-only** — stable `2.10.9` refuses that database
(`no such column: favorite`). Revisit stable tracking only when the upstream
stable channel reaches ≥ 2.11. If you ever try, take a snapshot first:

```bash
docker run --rm -v ~/homeassistant/music-assistant-server2:/data:ro alpine \
  tar czf - -C / data > ~/ma-data-backup.tar.gz
```

A pre-downgrade snapshot of the 2.11.0b8 data is kept at
`raspberrypi4:~/homeassistant/music-assistant-server2.auto-backups/data-predowngrade-2.11.0b8.tar.gz`.

Use the manual trigger (`workflow_dispatch`) to override the published tag
(`image_tag` input).
