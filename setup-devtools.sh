#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-devtools] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }

missing_core=0
for c in rg htop jq git; do
  if ! need_cmd "$c"; then
    missing_core=1
  fi
done

if [[ "$FORCE" -ne 1 ]] && [[ "$missing_core" -eq 0 ]]; then
  log "core dev tools already present (rg/htop/jq/git). Will still ensure optional tools and AI CLIs."
fi

log "installing common packages via apt"
sudo apt-get update -y
if [[ "$FORCE" -eq 1 ]]; then
  sudo apt-get install -y --reinstall \
    ripgrep \
    htop \
    git \
    zip \
    xz-utils \
    build-essential \
    pkg-config \
    tree \
    fzf \
    tmux \
    shellcheck \
    openssh-client \
    fd-find \
    bat \
    direnv
else
  sudo apt-get install -y \
    ripgrep \
    htop \
    git \
    zip \
    xz-utils \
    build-essential \
    pkg-config \
    tree \
    fzf \
    tmux \
    shellcheck \
    openssh-client \
    fd-find \
    bat \
    direnv
fi

# Ubuntu packages often ship as batcat/fdfind; provide convenience shims in ~/.local/bin.
mkdir -p "$HOME/.local/bin"
if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# Ensure ~/.local/bin is on PATH for bash shells.
if [[ -f "$HOME/.bashrc" ]]; then
  start="# >>> setup-devtools >>>"
  end="# <<< setup-devtools <<<"
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

log "installing AI CLIs (best-effort)"
if ! command -v curl >/dev/null 2>&1; then
  die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
fi

have_npm=0
if command -v npm >/dev/null 2>&1; then
  have_npm=1
else
  if command -v fnm >/dev/null 2>&1; then
    # Try to make Node available in this non-interactive shell.
    set +u
    eval "$(fnm env --shell bash)"
    set -u
    if command -v npm >/dev/null 2>&1; then
      have_npm=1
    fi
  fi
fi

if [[ "$have_npm" -eq 1 ]]; then
  if [[ "$FORCE" -eq 1 ]] || ! command -v codex >/dev/null 2>&1; then
    log "installing OpenAI Codex CLI (@openai/codex)"
    npm i -g @openai/codex@latest
  else
    log "codex already present at: $(command -v codex)"
  fi
else
  log "npm not found; skipping Codex CLI install (run setup-fnm.sh first)."
fi

if [[ "$FORCE" -eq 1 ]] || ! command -v claude >/dev/null 2>&1; then
  log "installing Claude Code (native installer)"
  curl -fsSL "https://claude.ai/install.sh" | bash
else
  log "claude already present at: $(command -v claude)"
fi

set +e
if command -v codex >/dev/null 2>&1; then
  codex --version >/dev/null 2>&1
  log "codex installed (version check exit $?)"
fi
if command -v claude >/dev/null 2>&1; then
  claude --version >/dev/null 2>&1
  log "claude installed (version check exit $?)"
fi
set -e

log "dev tools installed"
