#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-firewall] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if [[ ! -t 0 ]]; then
  log "stdin is not a TTY; skipping firewall setup."
  exit 0
fi

have_ufw=0
if command -v ufw >/dev/null 2>&1; then
  have_ufw=1
fi

if [[ "$FORCE" -eq 1 ]] || [[ "$have_ufw" -ne 1 ]]; then
  log "installing ufw"
  sudo apt-get update -y
  if [[ "$FORCE" -eq 1 ]]; then
    sudo apt-get install -y --reinstall ufw
  else
    sudo apt-get install -y ufw
  fi
fi

if ! command -v ufw >/dev/null 2>&1; then
  die "ufw not found after install"
fi

log "ensuring allow rules exist (all interfaces)"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp
sudo ufw allow 2222/tcp

log "enabling ufw (if not already enabled)"
ufw_status=""
if ufw_status="$(sudo ufw status 2>/dev/null)"; then
  :
else
  die "failed to read ufw status"
fi

is_active=0
if [[ "$ufw_status" == Status:\ active* ]]; then
  is_active=1
fi

if [[ "$is_active" -ne 1 ]] || [[ "$FORCE" -eq 1 ]]; then
  # --force avoids ufw's interactive "Proceed with operation (y|n)" prompt.
  sudo ufw --force enable
fi

log "ufw status:"
sudo ufw status verbose
