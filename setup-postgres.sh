#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-postgres] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if command -v psql >/dev/null 2>&1 && [[ "$FORCE" -ne 1 ]]; then
  log "postgres client already installed at: $(command -v psql). Skipping (use --force to reinstall)."
  exit 0
fi

log "installing PostgreSQL via apt"
sudo apt-get update -y
if [[ "$FORCE" -eq 1 ]]; then
  sudo apt-get install -y --reinstall postgresql postgresql-contrib
else
  sudo apt-get install -y postgresql postgresql-contrib
fi

log "enabling and starting postgresql service"
sudo systemctl enable --now postgresql
sudo systemctl status --no-pager postgresql >/dev/null

if command -v psql >/dev/null 2>&1; then
  log "installed: $(psql --version)"
else
  die "PostgreSQL install completed but 'psql' not found on PATH"
fi
