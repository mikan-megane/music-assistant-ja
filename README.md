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

Multi-arch: `linux/arm64` + `linux/amd64`.

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

## Tracking upstream

The workflow runs weekly (Mon 04:00 UTC) and rebuilds against the upstream `beta` channel. To target a specific MA server release, use the manual trigger with the `upstream_tag` input (`latest`, `2.9.9`, etc.).
