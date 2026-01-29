#!/usr/bin/env bash
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
  esac
done

log() { echo "[setup-tailscale] $*"; }
die() { log "ERROR: $*"; exit 1; }
trap 'die "failed at line ${LINENO} (exit $?)"' ERR

if [[ "${EUID}" -eq 0 ]]; then
  log "refusing to run as root/sudo. Run as a normal user; this step will use sudo internally as needed."
  exit 1
fi

if [[ ! -t 0 ]]; then
  log "stdin is not a TTY; skipping interactive tailscale setup."
  exit 0
fi

have_tailscale=0
if command -v tailscale >/dev/null 2>&1; then
  have_tailscale=1
fi

if [[ "$FORCE" -eq 1 ]] || [[ "$have_tailscale" -ne 1 ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    die "missing 'curl'. Run ./setup.sh (or install curl) and try again."
  fi

  log "configuring Tailscale apt repository"
  . /etc/os-release
  sudo install -m 0755 -d /usr/share/keyrings

  # Official packages: write keyring + sources list without temp files.
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" \
    | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" \
    | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

  log "installing tailscale"
  sudo apt-get update -y
  if [[ "$FORCE" -eq 1 ]]; then
    sudo apt-get install -y --reinstall tailscale
  else
    sudo apt-get install -y tailscale
  fi
else
  log "tailscale already present at: $(command -v tailscale)"
fi

log "enabling and starting tailscaled"
sudo systemctl enable --now tailscaled
sudo systemctl status --no-pager tailscaled >/dev/null

log "checking current tailscale state"
status_ec=0
if sudo tailscale status >/dev/null 2>&1; then
  status_ec=0
else
  status_ec=$?
fi

already_up=0
if [[ "$status_ec" -eq 0 ]]; then
  # Best-effort: if an IP is assigned, we consider it up.
  ts_ip=""
  ts_ip_out=""
  if ts_ip_out="$(sudo tailscale ip -4 2>/dev/null)"; then
    ts_ip="${ts_ip_out%%$'\n'*}"
  fi
  if [[ -n "$ts_ip" ]]; then
    already_up=1
    log "tailscale appears up. IPv4: $ts_ip"
  fi
fi

if [[ "$FORCE" -eq 1 ]] || [[ "$already_up" -ne 1 ]]; then
  log "tailscale is not up yet (or --force). We'll run 'tailscale up'."
  echo
  echo "Tailscale will open a login URL in the output if needed."
  echo "If you need special options (e.g. --ssh, --accept-routes), enter them now."
  read -r -p "Extra args for 'tailscale up' (or press Enter for none): " ts_up_args

  if [[ -n "${ts_up_args}" ]]; then
    # shellcheck disable=SC2086
    sudo tailscale up ${ts_up_args}
  else
    sudo tailscale up
  fi
fi

ts_ip=""
ts_ip_out=""
if ts_ip_out="$(sudo tailscale ip -4 2>/dev/null)"; then
  ts_ip="${ts_ip_out%%$'\n'*}"
fi
if [[ -z "$ts_ip" ]]; then
  log "tailscale did not report an IPv4 address. You may still be logged out."
else
  log "tailscale IPv4: $ts_ip"
fi

read -r -p "Test tailscale access by SSH'ing to this machine over its tailscale IP? [y/N] " do_test
case "${do_test,,}" in
  y|yes)
    if [[ -z "$ts_ip" ]]; then
      die "cannot run self-SSH test: tailscale IPv4 is empty"
    fi
    if ! command -v ssh >/dev/null 2>&1; then
      die "cannot run self-SSH test: 'ssh' is not installed (install openssh-client)"
    fi

    default_user="${USER}"
    read -r -p "SSH username (default: ${default_user}): " ssh_user
    ssh_user="${ssh_user:-$default_user}"

    read -r -p "SSH port (default: 22; you can use 2222): " ssh_port
    ssh_port="${ssh_port:-22}"

    log "attempting: ssh -p ${ssh_port} ${ssh_user}@${ts_ip} 'echo ok'"
    ssh_ec=0
    if ssh -p "$ssh_port" \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=10 \
      "${ssh_user}@${ts_ip}" \
      "echo 'tailscale-ssh-ok from $(hostname)'"; then
      ssh_ec=0
    else
      ssh_ec=$?
    fi

    if [[ "$ssh_ec" -eq 0 ]]; then
      log "self-SSH over tailscale succeeded"
    else
      log "self-SSH over tailscale failed (exit $ssh_ec)."
      log "If you were prompted for a password/key and it failed, ensure sshd is running and the firewall allows port ${ssh_port}."
    fi
    ;;
  *)
    log "skipping self-SSH test"
    ;;
esac
