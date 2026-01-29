#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-go] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if command -v go >/dev/null 2>&1 && [[ "$FORCE" -ne 1 ]]; then
  log "go already installed at: $(command -v go). Skipping (use --force to reinstall)."
  exit 0
fi

arch_deb="$(dpkg --print-architecture)"
case "$arch_deb" in
  amd64) arch_go="amd64" ;;
  arm64) arch_go="arm64" ;;
  386) arch_go="386" ;;
  *)
    die "unsupported architecture for Go install: dpkg arch '$arch_deb'"
    ;;
esac

log "installing prerequisites"
if ! command -v curl >/dev/null 2>&1; then
  die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
fi
if ! command -v jq >/dev/null 2>&1; then
  die "missing 'jq'. Run ./setup.sh (or install jq) and try again."
fi

log "discovering latest stable Go for linux/$arch_go"
go_filename="$(
  curl -fsSL "https://go.dev/dl/?mode=json" | jq -r --arg arch "$arch_go" '
    map(select(.stable == true))[0].files
    | map(select(.kind == "archive" and .os == "linux" and .arch == $arch and (.filename | endswith(".tar.gz"))))
    | .[0].filename
  ' | { IFS= read -r first || true; echo "${first:-}"; }
)"

if [[ -z "$go_filename" ]] || [[ "$go_filename" == "null" ]]; then
  die "failed to resolve Go archive filename from https://go.dev/dl/?mode=json"
fi

go_version="${go_filename%%.linux-*}"
go_url="https://go.dev/dl/${go_filename}"

log "installing ${go_version} from ${go_url}"
sudo rm -rf /usr/local/go
curl -fsSL "$go_url" | sudo tar -C /usr/local -xzf -

# Make Go available immediately in this script run.
export PATH="/usr/local/go/bin:$PATH"
hash -r

# Ensure /usr/local/go/bin is on PATH for bash shells.
if [[ -f "$HOME/.bashrc" ]]; then
  start="# >>> setup-go >>>"
  end="# <<< setup-go <<<"
  if ! grep -Fq "$start" "$HOME/.bashrc" 2>/dev/null; then
    {
      echo
      echo "$start"
      echo 'export PATH="/usr/local/go/bin:$PATH"'
      echo "$end"
    } >>"$HOME/.bashrc"
  fi
fi

if ! command -v go >/dev/null 2>&1; then
  if [[ -x /usr/local/go/bin/go ]]; then
    log "Go installed to /usr/local/go/bin/go but isn't on PATH yet. Try: source ~/.bashrc"
  fi
  die "Go install completed but 'go' not found on PATH"
fi

log "installed: $(go version)"
