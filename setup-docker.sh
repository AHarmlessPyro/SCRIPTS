#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-docker] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if command -v docker >/dev/null 2>&1 && [[ "$FORCE" -ne 1 ]]; then
  log "docker already installed at: $(command -v docker). Skipping (use --force to reinstall)."
  exit 0
fi

log "installing prerequisites"
if ! command -v curl >/dev/null 2>&1; then
  die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
fi
if ! command -v gpg >/dev/null 2>&1; then
  die "missing 'gpg'. Run ./setup.sh (or install gnupg) and try again."
fi

log "configuring Docker apt repository"
sudo install -m 0755 -d /etc/apt/keyrings
if [[ "$FORCE" -eq 1 ]] || [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

. /etc/os-release
arch="$(dpkg --print-architecture)"
repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable"

if [[ "$FORCE" -eq 1 ]] || [[ ! -f /etc/apt/sources.list.d/docker.list ]] || ! grep -Fq "$repo_line" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
  echo "$repo_line" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
fi

log "installing Docker Engine and plugins"
sudo apt-get update -y
if [[ "$FORCE" -eq 1 ]]; then
  sudo apt-get install -y --reinstall docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

log "enabling and starting docker service"
sudo systemctl enable --now docker
sudo systemctl status --no-pager docker >/dev/null

log "adding user '$USER' to docker group (requires new login to take effect)"
if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$USER"
fi

if ! command -v docker >/dev/null 2>&1; then
  die "Docker install completed but 'docker' not found on PATH"
fi

log "installed: $(docker --version)"
