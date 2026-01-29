#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-docker-rootless] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

sock="/run/user/$(id -u)/docker.sock"
if [[ -S "$sock" ]] && [[ "$FORCE" -ne 1 ]]; then
  log "rootless docker socket already exists at: $sock. Skipping (use --force to reinstall)."
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  die "docker is not installed. Run setup-docker.sh first."
fi

log "installing rootless prerequisites"
sudo apt-get update -y
sudo apt-get install -y uidmap dbus-user-session slirp4netns fuse-overlayfs

log "installing docker rootless extras"
if [[ "$FORCE" -eq 1 ]]; then
  sudo apt-get install -y --reinstall docker-ce-rootless-extras
else
  sudo apt-get install -y docker-ce-rootless-extras
fi

log "enabling lingering for user '$USER' (so user service can start without active login)"
sudo loginctl enable-linger "$USER"

if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
  die "dockerd-rootless-setuptool.sh not found (docker-ce-rootless-extras may not be installed correctly)"
fi

log "running rootless setup tool"
dockerd-rootless-setuptool.sh install

log "enabling and starting rootless docker user service"
systemctl --user daemon-reload
systemctl --user enable --now docker
systemctl --user status --no-pager docker >/dev/null

if [[ -f "$HOME/.bashrc" ]]; then
  start="# >>> setup-docker-rootless >>>"
  end="# <<< setup-docker-rootless <<<"
  if ! grep -Fq "$start" "$HOME/.bashrc" 2>/dev/null; then
    {
      echo
      echo "$start"
      echo 'export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"'
      echo "$end"
    } >>"$HOME/.bashrc"
  fi
fi

if [[ -S "$sock" ]]; then
  log "rootless docker socket ready at: $sock"
else
  die "rootless docker setup ran, but socket not found at: $sock"
fi
