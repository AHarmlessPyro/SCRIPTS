#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-python312] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

have_python312=0
if command -v python3.12 >/dev/null 2>&1; then
  if python3.12 --version 2>/dev/null | grep -Eq '^Python 3\.12(\.|$)'; then
    have_python312=1
  fi
fi

if [[ "$FORCE" -ne 1 ]] && [[ "$have_python312" -eq 1 ]]; then
  log "python3.12 already installed at: $(command -v python3.12). Skipping (use --force to re-run)."
  exit 0
fi

if ! command -v uv >/dev/null 2>&1; then
  die "uv is not installed. Run setup-uv.sh first."
fi

# uv installs managed Python executables into ~/.local/bin by default.
export PATH="$HOME/.local/bin:$PATH"
if [[ -f "$HOME/.local/bin/env" ]]; then
  set +u
  # shellcheck disable=SC1090
  source "$HOME/.local/bin/env"
  set -u
fi

log "installing Python 3.12 via uv"
if [[ "$FORCE" -eq 1 ]]; then
  uv python install 3.12 --reinstall --default
else
  uv python install 3.12 --default
fi

if ! command -v python3.12 >/dev/null 2>&1; then
  die "Python 3.12 install completed but 'python3.12' is not on PATH. Try: source ~/.local/bin/env or source ~/.bashrc"
fi

if ! python3.12 --version 2>/dev/null | grep -Eq '^Python 3\.12(\.|$)'; then
  die "python3.12 is present but does not report a 3.12 version"
fi

log "python3.12: $(python3.12 --version)"
