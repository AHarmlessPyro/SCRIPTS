#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-node-lts] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if ! command -v fnm >/dev/null 2>&1; then
  die "fnm is not installed. Run setup-fnm.sh first."
fi

# Ensure fnm can be found even if ~/.bashrc doesn't run.
if [[ -d "$HOME/.local/share/fnm" ]]; then
  export PATH="$HOME/.local/share/fnm:$PATH"
fi

if ! command -v curl >/dev/null 2>&1; then
  die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
fi
if ! command -v jq >/dev/null 2>&1; then
  die "missing 'jq'. Run ./setup.sh (or install jq) and try again."
fi

arch_deb="$(dpkg --print-architecture)"
case "$arch_deb" in
  amd64) node_dist_file="linux-x64" ;;
  arm64) node_dist_file="linux-arm64" ;;
  i386) node_dist_file="linux-x86" ;;
  *)
    die "unsupported architecture for Node LTS selection: dpkg arch '$arch_deb'"
    ;;
esac

log "discovering latest Node.js LTS from nodejs.org for ${node_dist_file}"
node_lts_version="$(
  curl -fsSL "https://nodejs.org/dist/index.json" | jq -r --arg f "$node_dist_file" '
    map(select(.lts != false and (.files | index($f)))) |
    sort_by(.version | sub("^v"; "") | split(".") | map(tonumber)) |
    last |
    .version
  '
)"

if [[ -z "$node_lts_version" ]] || [[ "$node_lts_version" == "null" ]]; then
  die "failed to resolve Node LTS version from index.json"
fi

if [[ "$FORCE" -ne 1 ]] && command -v node >/dev/null 2>&1; then
  current_node="$(node --version 2>/dev/null || true)"
  if [[ "$current_node" == "$node_lts_version" ]]; then
    log "Node already at latest LTS ($node_lts_version). Skipping (use --force to re-run)."
    exit 0
  fi
fi

log "installing Node.js LTS ${node_lts_version} via fnm"
eval "$(fnm env --shell bash)"
fnm install "$node_lts_version"
fnm default "$node_lts_version"
fnm use "$node_lts_version"

if ! command -v node >/dev/null 2>&1; then
  die "fnm reported success but 'node' is not on PATH"
fi
if ! command -v npm >/dev/null 2>&1; then
  die "node is installed but 'npm' is not on PATH"
fi

installed_node="$(node --version 2>/dev/null || true)"
if [[ "$installed_node" != "$node_lts_version" ]]; then
  die "expected node --version to be '$node_lts_version', got '$installed_node'"
fi

log "node: $installed_node"
log "npm: $(npm --version)"
