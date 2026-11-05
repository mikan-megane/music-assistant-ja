#!/usr/bin/env bash
# pi-local-build.sh — build & deploy the music-assistant-ja image on the Pi itself.
#
# Runs on the Raspberry Pi that serves music-assistant-server via the compose
# stack in $MA_JA_COMPOSE_DIR. Daily cron entry (see README):
#
#   10 5 * * *  /bin/bash /home/mikan/src/music-assistant-ja/scripts/pi-local-build.sh
#
# Flow:
#   1. resolve the latest stable upstream MA release (GitHub API) and export it
#      as MA_JA_SERVER_TAG — the compose build args substitute it
#   2. git pull
#   3. docker compose build --pull music-assistant-server
#   4. restart the service ONLY when the built image actually changed;
#      on unchanged days the build is a pure cache hit (~20 s, no restart)
#
# Safety: before swapping, the running /data dir is snapshotted (2 versions
# retained) and the currently running image is re-tagged as :prev, so a bad
# release can be rolled back without touching ghcr.io.
# If the build fails, `set -e` aborts before any swap — container untouched.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="${MA_JA_COMPOSE_DIR:-/home/mikan/homeassistant}"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
SERVICE="${MA_JA_SERVICE:-music-assistant-server}"
IMAGE="${MA_JA_IMAGE:-music-assistant-ja:local}"
PREV_IMAGE="${MA_JA_PREV_IMAGE:-music-assistant-ja:prev}"
DATA_DIR="${MA_JA_DATA_DIR:-$COMPOSE_DIR/music-assistant-server2}"
BACKUP_DIR="${MA_JA_BACKUP_DIR:-$DATA_DIR.auto-backups}"
LOG_FILE="${MA_JA_LOG_FILE:-$REPO_DIR/pi-local-build.log}"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

# Serialise overlapping runs (cron + manual) with a non-blocking flock.
exec 9>"$REPO_DIR/.pi-local-build.lock"
if ! flock -n 9; then
  log "another run holds the lock; exiting"
  exit 0
fi

# Log everything to a file; build failures are captured too.
exec >>"$LOG_FILE" 2>&1

log "=== start (repo: $REPO_DIR)"
log "git HEAD: $(git -C "$REPO_DIR" log -1 --format='%h %s' 2>/dev/null || echo 'n/a')"

# Image ID of the container that is currently running (may be empty).
CONTAINER_ID="$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE" 2>/dev/null || true)"
OLD_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_ID" 2>/dev/null || true)"

# ---- 1. latest stable upstream MA release -> MA_JA_SERVER_TAG --------------
if [ -n "${MA_JA_SERVER_TAG:-}" ]; then
  log "MA_JA_SERVER_TAG explicitly set: $MA_JA_SERVER_TAG (skipping GitHub API)"
else
  REL="$(curl -fsSL --connect-timeout 10 --max-time 30 \
    'https://api.github.com/repos/music-assistant/server/releases/latest' 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)" || true
  if [ -z "$REL" ]; then
    log "WARNING: could not determine the latest upstream MA release (network/API?); skipping this run"
    exit 0
  fi
  export MA_JA_SERVER_TAG="$REL"
fi
log "targeting upstream MA server: $MA_JA_SERVER_TAG"

# ---- 2. update this repo ---------------------------------------------------
if git -C "$REPO_DIR" symbolic-ref -q HEAD >/dev/null; then
  log "git pull --ff-only"
  git -C "$REPO_DIR" pull --ff-only --quiet
else
  log "detached HEAD; skipping git pull"
fi

# ---- 3. build ---------------------------------------------------------------
log "docker compose build --pull ($SERVICE)"
docker compose -f "$COMPOSE_FILE" build --pull "$SERVICE"

# ---- 4. restart only if the image actually changed --------------------------
NEW_IMAGE_ID="$(docker image inspect "$IMAGE" --format '{{.Id}}')"
if [ -n "$OLD_IMAGE_ID" ] && [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ]; then
  log "image unchanged (cache hit); nothing to deploy"
  docker image prune -f >/dev/null
  log "done (no-op)"
  exit 0
fi

# Pre-swap safety net: snapshot /data and keep the previous image reachable.
if [ -d "$DATA_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  BACKUP="$BACKUP_DIR/data-$(date +%F-%H%M).tar.gz"
  log "backing up $DATA_DIR ($(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)) -> $BACKUP"
  tar -C "$COMPOSE_DIR" --exclude='music-assistant-server2/.cache' -czf "$BACKUP" "$(basename "$DATA_DIR")"
  # keep only the 2 most recent snapshots
  ls -1t "$BACKUP_DIR"/data-*.tar.gz 2>/dev/null | tail -n +3 | xargs -r rm -f
fi
if [ -n "$OLD_IMAGE_ID" ]; then
  log "re-tagging previously running image as $PREV_IMAGE"
  docker tag "$OLD_IMAGE_ID" "$PREV_IMAGE"
fi

log "docker compose up -d ($SERVICE)"
docker compose -f "$COMPOSE_FILE" up -d "$SERVICE"

# Drop dangling leftovers (untagged only; :local and :prev are tagged).
docker image prune -f >/dev/null

CID="$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE")"
log "done: $(docker inspect --format '{{.Name}} ({{.State.Status}}, started {{.State.StartedAt}})' "$CID" 2>/dev/null || echo "container ${CID:-unknown}")"
