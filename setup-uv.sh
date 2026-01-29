#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-uv] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if command -v uv >/dev/null 2>&1 && [[ "$FORCE" -ne 1 ]]; then
  log "uv already installed at: $(command -v uv). Skipping (use --force to reinstall)."
  exit 0
fi

log "installing prerequisites"
if ! command -v curl >/dev/null 2>&1; then
  die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
fi

log "installing uv (Astral)"
curl -LsSf "https://astral.sh/uv/install.sh" | sh

# Ensure ~/.local/bin is on PATH for bash shells.
if [[ -f "$HOME/.bashrc" ]]; then
  start="# >>> setup-uv >>>"
  end="# <<< setup-uv <<<"
  if ! grep -Fq "$start" "$HOME/.bashrc" 2>/dev/null; then
    {
      echo
      echo "$start"
      echo 'export PATH="$HOME/.local/bin:$PATH"'
      echo "$end"
    } >>"$HOME/.bashrc"
  fi
fi

export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv >/dev/null 2>&1; then
  die "uv install completed but 'uv' is not on PATH. Try: source ~/.bashrc"
fi

log "uv: $(uv --version)"
