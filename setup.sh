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

cleanup_path() {
  # Remove duplicates and keep only the most recent fnm multishell path.
  # Note: `fnm env` prepends its multishell bin dir to PATH, so the *first*
  # fnm_multishells/.../bin we encounter is the newest.
  local IFS=:
  # shellcheck disable=SC2206
  local -a parts=($PATH)
  local -A seen=()
  local -a out=()
  local fnm_keep=""
  local localbin="$HOME/.local/bin"
  local localbin_idx=-1

  local p norm
  for p in "${parts[@]}"; do
    [[ -z "$p" ]] && continue
    norm="${p%/}"

    if [[ "$norm" =~ ^/run/user/[0-9]+/fnm_multishells/[^/]+/bin$ ]]; then
      if [[ -z "$fnm_keep" ]]; then
        fnm_keep="$norm"
      fi
      continue
    fi

    if [[ -n "${seen[$norm]+x}" ]]; then
      continue
    fi

    seen[$norm]=1
    out+=("$norm")
    if [[ "$norm" == "$localbin" ]]; then
      localbin_idx=$((${#out[@]} - 1))
    fi
  done

  if [[ -n "$fnm_keep" ]] && [[ -z "${seen[$fnm_keep]+x}" ]]; then
    if [[ "$localbin_idx" -ge 0 ]]; then
      out=("${out[@]:0:$((localbin_idx + 1))}" "$fnm_keep" "${out[@]:$((localbin_idx + 1))}")
    else
      out=("$fnm_keep" "${out[@]}")
    fi
  fi

  PATH="$(IFS=:; echo "${out[*]}")"
  export PATH
}

ensure_bashrc_path_cleanup() {
  # Keeps PATH tidy in interactive shells (and when setup sources ~/.bashrc repeatedly).
  local bashrc="$HOME/.bashrc"
  [[ -f "$bashrc" ]] || return 0

  local start="# >>> setup-path-cleanup >>>"
  local end="# <<< setup-path-cleanup <<<"
  if grep -Fq "$start" "$bashrc" 2>/dev/null; then
    return 0
  fi

  {
    echo
    echo "$start"
    cat <<'EOF'
__setup_path_cleanup() {
  local IFS=:
  # shellcheck disable=SC2206
  local -a parts=($PATH)
  local -A seen=()
  local -a out=()
  # `fnm env` prepends its multishell bin dir to PATH, so the first match is newest.
  local fnm_keep=""
  local localbin="$HOME/.local/bin"
  local localbin_idx=-1

  local p norm
  for p in "${parts[@]}"; do
    [[ -z "$p" ]] && continue
    norm="${p%/}"

    if [[ "$norm" =~ ^/run/user/[0-9]+/fnm_multishells/[^/]+/bin$ ]]; then
      if [[ -z "$fnm_keep" ]]; then
        fnm_keep="$norm"
      fi
      continue
    fi

    if [[ -n "${seen[$norm]+x}" ]]; then
      continue
    fi

    seen[$norm]=1
    out+=("$norm")
    if [[ "$norm" == "$localbin" ]]; then
      localbin_idx=$((${#out[@]} - 1))
    fi
  done

  if [[ -n "$fnm_keep" ]] && [[ -z "${seen[$fnm_keep]+x}" ]]; then
    if [[ "$localbin_idx" -ge 0 ]]; then
      out=("${out[@]:0:$((localbin_idx + 1))}" "$fnm_keep" "${out[@]:$((localbin_idx + 1))}")
    else
      out=("$fnm_keep" "${out[@]}")
    fi
  fi

  (IFS=:; echo "${out[*]}")
}
PATH="$(__setup_path_cleanup)"
unset -f __setup_path_cleanup
EOF
    echo "$end"
  } >>"$bashrc"
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
  cleanup_path
  hash -r
}

ensure_common_prereqs
ensure_bashrc_path_cleanup
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
    y|yes) run_step "$SCRIPT_DIR/setup-tailscale.sh" ;;
    *) log "skipping tailscale" ;;
  esac

  read -r -p "Do you want to set up a firewall (ufw)? [y/N] " do_fw
  case "${do_fw,,}" in
    y|yes) run_step "$SCRIPT_DIR/setup-firewall.sh" ;;
    *) log "skipping firewall setup" ;;
  esac

  read -r -p "Do you want to clone and set up browserctrl (metlo-labs/browserctrl)? [y/N] " do_bc
  case "${do_bc,,}" in
    y|yes) run_step "$SCRIPT_DIR/setup-browserctrl.sh" ;;
    *) log "skipping browserctrl setup" ;;
  esac
else
  log "stdin is not a TTY; skipping interactive tailscale/firewall/browserctrl steps."
fi

log "done"
