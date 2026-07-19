# syntax=docker/dockerfile:1

# The upstream MA server tag is parameterised so the Actions workflow can target
# beta / latest / a specific release without editing this file.
ARG MA_SERVER_TAG=beta
ARG FRONTEND_REF=main

# ---- Stage 1: build the MA frontend from source with ja.json injected --------
FROM node:22-bookworm AS frontend

ARG FRONTEND_REF

RUN corepack enable
WORKDIR /app

# Shallow-clone upstream frontend at the requested ref (default: main).
# main tracks the current beta branch, which matches MA server beta channel.
RUN git clone --depth 1 --branch "${FRONTEND_REF}" https://github.com/music-assistant/frontend.git .

# Drop our Japanese file next to the other locale JSONs so vite-i18n picks
# it up automatically (no source code changes needed upstream).
# NOTE: ja.json MUST be saved as UTF-8 *without* BOM. A leading BOM (EF BB BF)
# makes JSON.parse() throw inside @intlify/unplugin-vue-i18n, which then
# silently skips the file and "ja" never ends up in availableLocales — i.e.
# Japanese won't show up in Settings → Language.
COPY ja.json src/translations/ja.json

# Add a "Japanese" label to en.json so the language dropdown shows a readable
# name in every UI locale (en is the configured fallbackLocale for all).
RUN node <<'EOF'
const fs = require('fs');
const p = 'src/translations/en.json';
const j = JSON.parse(fs.readFileSync(p, 'utf8'));
j.settings.language.options.ja = 'Japanese';
fs.writeFileSync(p, JSON.stringify(j, null, 2) + '\n');
EOF

# Frozen install uses upstream's lockfile as-is.
RUN pnpm install --frozen-lockfile

# Produces ./music_assistant_frontend/ (a Python package dir) wired up by
# upstream's setup.cfg + vite.config.ts.
RUN pnpm exec vite build

# ---- Stage 2: replace the frontend bundled inside the MA server image -------
FROM ghcr.io/music-assistant/server:${MA_SERVER_TAG}

COPY --from=frontend /app/music_assistant_frontend/ /tmp/fe/
RUN FE_DIR="$(python3 -c 'from music_assistant_frontend import where; print(where())')" \
 && rm -rf "${FE_DIR:?}"/* \
 && cp -a /tmp/fe/. "${FE_DIR}/" \
 && chmod -R a+rX "${FE_DIR}" \
 && rm -rf /tmp/fe
