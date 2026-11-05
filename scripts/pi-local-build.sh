#!/usr/bin/env bash
# pi-local-build.sh — build & deploy the music-assistant-ja image on the Pi itself.
#
# Runs on the Raspberry Pi that serves music-assistant-server via the compose
# stack in $MA_JA_COMPOSE_DIR. Weekly cron entry (see README):
#
#   10 5 * * 1  /bin/bash /home/mikan/src/music-assistant-ja/scripts/pi-local-build.sh
#
# Flow: git pull -> docker compose build --pull -> docker compose up -d (service only).
# If the build fails, `set -e` aborts before `up -d` and the running container
# is left untouched — no downtime from a broken build.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="${MA_JA_COMPOSE_DIR:-/home/mikan/homeassistant}"
SERVICE="${MA_JA_SERVICE:-music-assistant-server}"
LOG_FILE="${MA_JA_LOG_FILE:-$REPO_DIR/pi-local-build.log}"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

# Serialise overlapping runs (cron + manual) with a non-blocking flock.
exec 9>"$REPO_DIR/.pi-local-build.lock"
if ! flock -n 9; then
  log "another run holds the lock; exiting"
  exit 0
fi

# Log to a file; stderr too, so build failures are captured.
exec >>"$LOG_FILE" 2>&1

log "=== start (repo: $REPO_DIR)"
log "git HEAD: $(git -C "$REPO_DIR" log -1 --format='%h %s' 2>/dev/null || echo 'n/a')"

# Update from GitHub unless the clone is checked out to a specific commit.
if git -C "$REPO_DIR" symbolic-ref -q HEAD >/dev/null; then
  log "git pull --ff-only"
  git -C "$REPO_DIR" pull --ff-only --quiet
else
  log "detached HEAD; skipping git pull"
fi

log "docker compose build --pull ($SERVICE)"
docker compose -f "$COMPOSE_DIR/docker-compose.yml" build --pull "$SERVICE"

log "docker compose up -d ($SERVICE)"
docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d "$SERVICE"

# Drop dangling leftovers of replaced images (untagged only; tagged images keep).
docker image prune -f >/dev/null

CID="$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q "$SERVICE")"
log "done: $(docker inspect --format '{{.Name}} ({{.State.Status}}, started {{.State.StartedAt}})' "$CID" 2>/dev/null || echo "container ${CID:-unknown}")"
