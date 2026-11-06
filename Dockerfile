# syntax=docker/dockerfile:1

# The upstream MA server tag is parameterised so the Actions workflow can target
# a specific release without editing this file. The workflow passes the newest
# upstream nightly snapshot (X.Y.Z.devN, same dev branch as beta but fresher):
# the frontend below is built from upstream `main`, whose minimum server API
# schema tracks those snapshots — an old beta (e.g. 2.11.0b8, schema 101) is
# rejected by today's frontend (requires >= 102) with the "update your server"
# wall. Only pair a beta/stable tag with a matching-era frontend checkout.
# MA migrations are forward-only, so never build against an older tag than
# what is currently deployed.
ARG MA_SERVER_TAG=beta
ARG FRONTEND_REF=main

# ---- Stage 1: build the MA frontend from source with ja.json injected --------
FROM node:22-bookworm AS frontend

ARG FRONTEND_REF

# Cache-bust: pi-local-build.sh passes the upstream MA release it targets, so
# the frontend checkout below is re-cloned whenever the tracked MA release
# changes (a moving ref like `main` would otherwise be cached forever between
# releases and silently keep serving the old commit).
ARG FRONTEND_CLONE_BUST=

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

# Verify the file is valid JSON without BOM (BOM silently breaks the i18n plugin).
RUN node <<'CHECKEOF'
const fs = require('fs');
const buf = fs.readFileSync('src/translations/ja.json');
if (buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF) {
  console.error('ERROR: ja.json has BOM! Remove it before building.');
  process.exit(1);
}
try {
  const data = JSON.parse(buf.toString('utf8'));
  console.log(`ja.json: valid, ${Object.keys(data).length} top-level keys, ${buf.length} bytes`);
} catch(e) {
  console.error('ERROR: ja.json is invalid JSON:', e.message);
  process.exit(1);
}
CHECKEOF

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

# ---- Stage 2: replace the frontend + inject server ja translations ----------
FROM ghcr.io/music-assistant/server:${MA_SERVER_TAG}

COPY --from=frontend /app/music_assistant_frontend/ /tmp/fe/
RUN FE_DIR="$(python3 -c 'from music_assistant_frontend import where; print(where())')" \
 && rm -rf "${FE_DIR:?}"/* \
 && cp -a /tmp/fe/. "${FE_DIR}/" \
 && chmod -R a+rX "${FE_DIR}" \
 && rm -rf /tmp/fe

# Copy the server-side Japanese translation file into the MA server translations
# directory so that config entries, error messages, media genres, provider
# descriptions etc. are also shown in Japanese on the backend side.
COPY server_ja.json /tmp/ja.json
RUN python3 <<'PYEOF'
import music_assistant, os, shutil
translations_dir = os.path.join(music_assistant.__path__[0], "translations")
shutil.copy("/tmp/ja.json", os.path.join(translations_dir, "ja.json"))
os.chmod(os.path.join(translations_dir, "ja.json"), 0o644)
os.remove("/tmp/ja.json")
PYEOF
