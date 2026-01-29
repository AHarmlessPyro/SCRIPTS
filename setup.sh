#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; steps will use sudo internally as needed."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

path_prepend_if_missing() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    case ":${PATH}:" in
      *":${dir}:"*) ;;
      *) export PATH="${dir}:${PATH}" ;;
    esac
  fi
}

ensure_common_prereqs() {
  # Keep this list small and universal: tools used by many setup steps.
  local pkgs=(
    ca-certificates
    curl
    jq
    unzip
    gnupg
    apt-transport-https
  )

  local missing=0
  for p in "${pkgs[@]}"; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then
      missing=1
      break
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    log "common prerequisites already installed"
    return 0
  fi

  log "installing common prerequisites (${pkgs[*]})"
  sudo apt-get update -y
  sudo apt-get install -y "${pkgs[@]}"
}

refresh_bash_env() {
  # Best-effort: many ~/.bashrc files return early in non-interactive shells.
  # We still source it, but also source known env shims and prepend common tool paths.
  path_prepend_if_missing "$HOME/.local/bin"
  path_prepend_if_missing "$HOME/.local/share/fnm"
  path_prepend_if_missing "/usr/local/go/bin"

  if [[ -f "$HOME/.local/bin/env" ]]; then
    set +u
    # shellcheck disable=SC1090
    source "$HOME/.local/bin/env"
    set -u
  fi

  if [[ -f "$HOME/.bashrc" ]]; then
    set +u
    # shellcheck disable=SC1090
    source "$HOME/.bashrc"
    set -u
  fi
  hash -r
}

ensure_common_prereqs
refresh_bash_env

run_step() {
  local script="$1"
  shift
  if [[ ! -f "$script" ]]; then
    die "missing script: $script"
  fi

  log "running $(basename "$script")"
  if [[ "$FORCE" -eq 1 ]]; then
    bash "$script" --force "$@"
  else
    bash "$script" "$@"
  fi

  log "refreshing shell environment from ~/.bashrc"
  refresh_bash_env
}

run_step "$SCRIPT_DIR/setup-uv.sh"
run_step "$SCRIPT_DIR/setup-python312.sh"
run_step "$SCRIPT_DIR/setup-fnm.sh"
run_step "$SCRIPT_DIR/setup-node-lts.sh"
run_step "$SCRIPT_DIR/setup-devtools.sh"
run_step "$SCRIPT_DIR/setup-go.sh"
run_step "$SCRIPT_DIR/setup-postgres.sh"
run_step "$SCRIPT_DIR/setup-redis.sh"
run_step "$SCRIPT_DIR/setup-docker.sh"
run_step "$SCRIPT_DIR/setup-docker-rootless.sh"

if [[ -t 0 ]]; then
  read -r -p "Do you want to set up Tailscale? [y/N] " do_ts
  case "${do_ts,,}" in
    y|yes)
      run_step "$SCRIPT_DIR/setup-tailscale.sh"
      read -r -p "Do you want to set up a firewall (ufw)? [y/N] " do_fw
      case "${do_fw,,}" in
        y|yes) run_step "$SCRIPT_DIR/setup-firewall.sh" ;;
        *) log "skipping firewall setup" ;;
      esac
      ;;
    *)
      log "skipping tailscale"
      ;;
  esac
else
  log "stdin is not a TTY; skipping interactive tailscale/firewall steps."
fi

log "done"
