#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/addons-runtime.sh"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-}"

log(){ printf "\n\033[1;32m[+] %s\033[0m\n" "$*"; }
warn(){ printf "\n\033[1;33m[!] %s\033[0m\n" "$*"; }
err(){ printf "\n\033[1;31m[✗] %s\033[0m\n" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

sudo_keepalive() {
  if ! sudo -n true 2>/dev/null; then
    log "Requesting sudo..."
    sudo -v
  fi
  ( while true; do sudo -n true; sleep 30; done ) >/dev/null 2>&1 &
  SUDO_KA_PID=$!
  trap 'kill ${SUDO_KA_PID:-0} >/dev/null 2>&1 || true' EXIT
}

k() {
  sudo k3s kubectl "$@"
}

ensure_cmds() {
  local missing=()
  local cmd
  for cmd in sudo k3s tar date; do
    if ! need_cmd "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if ((${#missing[@]} > 0)); then
    err "Missing required commands: ${missing[*]}"
    exit 1
  fi
}

safe_write_cmd() {
  local out="$1"
  shift
  "$@" >"$out" 2>&1 || true
}

run_stack_addon_backup_hooks() {
  local output_dir="$1"
  local addon_name addon_dir backup_fn
  [[ -n "${PRODUCTIVE_K3S_STACK_NAME}" ]] || return 0
  if ! stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    err "Stack source '${PRODUCTIVE_K3S_STACK_NAME}' was not found. Set PRODUCTIVE_K3S_ADDONS_REPO_DIR or place productive-k3s-addons beside productive-k3s-core."
    exit 1
  fi

  while IFS= read -r addon_name; do
    [[ -n "${addon_name}" ]] || continue
    if ! addon_source_script_exists "${addon_name}" backup.sh; then
      err "Addon '${addon_name}' does not provide scripts/backup.sh"
      exit 1
    fi
    addon_dir="$(resolve_addon_source_dir "${addon_name}")"
    # shellcheck source=/dev/null
    source "${addon_dir}/scripts/backup.sh"
    backup_fn="pk3s_addon_backup"
    if ! declare -F "${backup_fn}" >/dev/null 2>&1; then
      err "Addon '${addon_name}' backup hook '${backup_fn}' is missing"
      exit 1
    fi
    "${backup_fn}" "${output_dir}"
  done < <(stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}")
}

main() {
  ensure_cmds
  sudo_keepalive

  local timestamp output_dir archive_path
  timestamp="$(date +%Y%m%d-%H%M%S)"
  output_dir="${1:-/tmp/k3s-stack-backup-${timestamp}}"
  mkdir -p "$output_dir"

  log "Writing backup to ${output_dir}"

  mkdir -p \
    "$output_dir/cluster" \
    "$output_dir/namespaces" \
    "$output_dir/host" \
    "$output_dir/k3s"

  log "Exporting cluster-wide resources"
  safe_write_cmd "$output_dir/cluster/nodes.txt" k get nodes -o wide
  safe_write_cmd "$output_dir/cluster/all.txt" k get all -A -o wide
  safe_write_cmd "$output_dir/cluster/all.yaml" k get all -A -o yaml
  safe_write_cmd "$output_dir/cluster/ingress.yaml" k get ingress -A -o yaml
  safe_write_cmd "$output_dir/cluster/storageclasses.yaml" k get sc -o yaml
  safe_write_cmd "$output_dir/cluster/pv.yaml" k get pv -A -o yaml
  safe_write_cmd "$output_dir/cluster/pvc.yaml" k get pvc -A -o yaml
  safe_write_cmd "$output_dir/cluster/configmaps.yaml" k get configmap -A -o yaml
  safe_write_cmd "$output_dir/cluster/secrets.yaml" k get secret -A -o yaml
  safe_write_cmd "$output_dir/cluster/certificates.yaml" k get certificates -A -o yaml
  safe_write_cmd "$output_dir/cluster/issuers.yaml" k get issuers -A -o yaml
  safe_write_cmd "$output_dir/cluster/clusterissuers.yaml" k get clusterissuers -o yaml
  safe_write_cmd "$output_dir/cluster/events.txt" k get events -A --sort-by=.lastTimestamp

  local ns
  for ns in kube-system; do
    if k get namespace "$ns" >/dev/null 2>&1; then
      log "Exporting namespace ${ns}"
      safe_write_cmd "$output_dir/namespaces/${ns}-all.yaml" k get all -n "$ns" -o yaml
      safe_write_cmd "$output_dir/namespaces/${ns}-pods.txt" k get pods -n "$ns" -o wide
      safe_write_cmd "$output_dir/namespaces/${ns}-ingress.yaml" k get ingress -n "$ns" -o yaml
      safe_write_cmd "$output_dir/namespaces/${ns}-secrets.yaml" k get secret -n "$ns" -o yaml
      safe_write_cmd "$output_dir/namespaces/${ns}-configmaps.yaml" k get configmap -n "$ns" -o yaml
      safe_write_cmd "$output_dir/namespaces/${ns}-pvc.yaml" k get pvc -n "$ns" -o yaml
    fi
  done

  run_stack_addon_backup_hooks "$output_dir"

  log "Exporting k3s host-side config"
  if [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
    sudo cp /etc/rancher/k3s/k3s.yaml "$output_dir/k3s/k3s.yaml"
    sudo chown "$(id -u):$(id -g)" "$output_dir/k3s/k3s.yaml"
  fi
  if [[ -d /var/lib/rancher/k3s/server/manifests ]]; then
    sudo cp -a /var/lib/rancher/k3s/server/manifests "$output_dir/k3s/manifests"
    sudo chown -R "$(id -u):$(id -g)" "$output_dir/k3s/manifests"
  fi

  log "Exporting host config"
  [[ -f /etc/exports ]] && sudo cp /etc/exports "$output_dir/host/exports"
  safe_write_cmd "$output_dir/host/exportfs.txt" sudo exportfs -v
  safe_write_cmd "$output_dir/host/k3s-service.txt" sudo systemctl status k3s --no-pager
  safe_write_cmd "$output_dir/host/inotify.txt" bash -lc 'cat /proc/sys/fs/inotify/max_user_watches; echo; cat /proc/sys/fs/inotify/max_user_instances'

  archive_path="${output_dir}.tar.gz"
  log "Creating archive ${archive_path}"
  tar -czf "$archive_path" -C "$(dirname "$output_dir")" "$(basename "$output_dir")"

  log "Backup complete"
  echo "  Directory: ${output_dir}"
  echo "  Archive:   ${archive_path}"
}

main "$@"
