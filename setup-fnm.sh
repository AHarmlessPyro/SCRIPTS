#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-fnm] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

FNM_PATH_DEFAULT="$HOME/.local/share/fnm"

have_fnm=0
if command -v fnm >/dev/null 2>&1; then
  have_fnm=1
fi

have_node=0
if command -v node >/dev/null 2>&1; then
  have_node=1
fi

if [[ "$FORCE" -ne 1 ]] && [[ "$have_fnm" -eq 1 ]]; then
  log "fnm already installed. Skipping (use --force to reinstall)."
  exit 0
fi

log "installing prerequisites"
if ! command -v curl >/dev/null 2>&1; then
  die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
fi
if ! command -v unzip >/dev/null 2>&1; then
  die "missing 'unzip'. Run ./setup.sh (or install unzip) and try again."
fi

if [[ "$FORCE" -eq 1 ]] || [[ "$have_fnm" -ne 1 ]]; then
  log "installing fnm"
  curl -fsSL "https://fnm.vercel.app/install" | bash
else
  log "fnm already present at: $(command -v fnm)"
fi

# The official installer installs into ~/.local/share/fnm and appends ~/.bashrc,
# but ~/.bashrc often early-returns for non-interactive shells. Ensure this script
# can see fnm immediately.
if [[ -d "$FNM_PATH_DEFAULT" ]]; then
  export PATH="$FNM_PATH_DEFAULT:$PATH"
fi

# Best-effort: ensure interactive shells can find fnm, even if the upstream installer
# didn't update ~/.bashrc (or the file was customized).
if [[ -f "$HOME/.bashrc" ]]; then
  if ! grep -Eq '(^|[^A-Za-z0-9_])FNM_PATH=|fnm env' "$HOME/.bashrc" 2>/dev/null; then
    {
      echo
      echo "# >>> setup-fnm >>>"
      echo 'FNM_PATH="$HOME/.local/share/fnm"'
      echo 'if [ -d "$FNM_PATH" ]; then'
      echo '  export PATH="$FNM_PATH:$PATH"'
      echo '  eval "$(fnm env --shell bash)"'
      echo 'fi'
      echo "# <<< setup-fnm <<<"
    } >>"$HOME/.bashrc"
  fi
fi

if ! command -v fnm >/dev/null 2>&1; then
  die "fnm install completed but 'fnm' is not on PATH (expected in $FNM_PATH_DEFAULT). Try: source ~/.bashrc"
fi

log "installed: $(fnm --version)"
