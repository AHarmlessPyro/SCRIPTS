#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-redis] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if command -v redis-server >/dev/null 2>&1 && [[ "$FORCE" -ne 1 ]]; then
  log "redis-server already installed at: $(command -v redis-server). Skipping (use --force to reinstall)."
  exit 0
fi

log "installing Redis via apt"
sudo apt-get update -y
if [[ "$FORCE" -eq 1 ]]; then
  sudo apt-get install -y --reinstall redis-server
else
  sudo apt-get install -y redis-server
fi

log "enabling and starting redis-server service"
sudo systemctl enable --now redis-server
sudo systemctl status --no-pager redis-server >/dev/null

if command -v redis-cli >/dev/null 2>&1; then
  log "redis-cli ping: $(redis-cli ping)"
fi

if command -v redis-server >/dev/null 2>&1; then
  log "installed: $(redis-server --version)"
else
  die "Redis install completed but 'redis-server' not found on PATH"
fi
