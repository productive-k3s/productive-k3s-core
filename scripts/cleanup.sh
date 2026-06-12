#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime-contract.sh"
source "${SCRIPT_DIR}/addons-runtime.sh"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_RESET=""
fi

line() { printf '%s\n' "$*"; }
log(){ printf "\n%s[INFO]%s %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
warn(){ printf "\n%s[WARN]%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }
err(){ printf "\n%s[ERROR]%s %s\n" "$COLOR_RED" "$COLOR_RESET" "$*"; }

PRODUCTIVE_K3S_DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
MODE="plan"
SUDO_KA_PID=""
AUTO_APPROVE="n"
FORCE_CONFIRM="n"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-}"
DEFAULT_NFS_EXPORT="/srv/nfs/k8s-share"
DEFAULT_REGISTRY_HOST="registry.home.arpa"
DEFAULT_RANCHER_HOST="rancher.home.arpa"
declare -a PLAN_ITEMS=()

can_use_tty() {
  [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] || return 1
  : > /dev/tty 2>/dev/null || return 1
  return 0
}

bind_stdin_to_tty() {
  if can_use_tty; then
    exec </dev/tty
  fi
}

prompt_yesno() {
  local var="$1" default="$2" msg="$3"
  local val d="$default"
  if can_use_tty; then
    printf '%s [%s] (y/n): ' "$msg" "$d" > /dev/tty
    IFS= read -r val < /dev/tty
  else
    printf '%s [%s] (y/n): ' "$msg" "$d"
    IFS= read -r val
  fi
  val="${val:-$d}"
  case "$val" in
    y|Y) printf -v "$var" 'y' ;;
    n|N) printf -v "$var" 'n' ;;
    *) printf -v "$var" '%s' "$d" ;;
  esac
}

prompt_text() {
  local var="$1" msg="$2"
  local val
  if can_use_tty; then
    printf '%s: ' "$msg" > /dev/tty
    IFS= read -r val < /dev/tty
  else
    printf '%s: ' "$msg"
    IFS= read -r val
  fi
  printf -v "$var" '%s' "$val"
}

sudo_keepalive() {
  if ! sudo -n true 2>/dev/null; then
    log "Requesting sudo..."
    sudo -v
  fi
  ( while true; do sudo -n true; sleep 30; done ) </dev/null >/dev/null 2>&1 &
  SUDO_KA_PID=$!
}

cleanup_exit() {
  if [[ -n "${SUDO_KA_PID:-}" ]]; then
    kill "${SUDO_KA_PID}" >/dev/null 2>&1 || true
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1"; }
path_is_within_dir() {
  local path="$1" dir="$2"
  [[ "${path}" == "${dir}" || "${path}" == "${dir}/"* ]]
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/cleanup.sh [--plan|--apply] [--yes] [--confirm-clean]

Modes:
  --plan   Show what would be removed (default)
  --apply  Apply the destructive cleanup

Options:
  --yes            Auto-approve the yes/no cleanup prompt
  --confirm-clean  Auto-approve the typed CLEAN confirmation

What it removes:
  - cluster runtime components and local runtime state
  - apply-managed namespaces: cert-manager, longhorn-system, cattle-system, cattle-fleet-system, cattle-fleet-local-system, cattle-capi-system, cattle-turtles-system, registry
  - common bootstrap ClusterIssuers: selfsigned, letsencrypt-staging, letsencrypt-production
  - Rancher/Fleet/Turtles webhook configurations and cattle-related CRDs/APIService objects when present
  - Longhorn CRDs, StorageClasses, and CSIDriver objects when present
  - local /etc/hosts entries for rancher.home.arpa and registry.home.arpa
  - local Docker trust for registry.home.arpa
  - NFS export line for /srv/nfs/k8s-share

What it does not remove:
  - Helm binary
  - this repository
  - arbitrary user data under Longhorn data paths or NFS export directories
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --plan)
        MODE="plan"
        ;;
      --apply)
        MODE="apply"
        ;;
      --yes)
        AUTO_APPROVE="y"
        ;;
      --confirm-clean)
        FORCE_CONFIRM="y"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

kubectl_k3s() { pk3s_runtime_kubectl "$@"; }
namespace_exists() { kubectl_k3s get namespace "$1" >/dev/null 2>&1; }
clusterissuer_exists() { kubectl_k3s get clusterissuer "$1" >/dev/null 2>&1; }

delete_named_resources_matching() {
  local resource="$1" pattern="$2"
  while read -r name; do
    [[ -n "$name" ]] || continue
    log "Deleting ${name}"
    kubectl_k3s delete "$name" --ignore-not-found --wait=false || true
  done < <(kubectl_k3s get "$resource" -o name 2>/dev/null | grep -E "$pattern" || true)
}

delete_rancher_cluster_artifacts() {
  if ! pk3s_runtime_server_active; then
    return
  fi
  delete_named_resources_matching validatingwebhookconfigurations 'rancher|fleet|cattle'
  delete_named_resources_matching mutatingwebhookconfigurations 'rancher|fleet|cattle'
  delete_named_resources_matching apiservices 'cattle|fleet'
  delete_named_resources_matching crd 'cattle\.io|fleet\.cattle\.io'
}

delete_longhorn_cluster_artifacts() {
  if ! pk3s_runtime_server_active; then
    return
  fi
  delete_named_resources_matching validatingwebhookconfigurations 'longhorn'
  delete_named_resources_matching mutatingwebhookconfigurations 'longhorn'
  kubectl_k3s delete storageclass longhorn longhorn-static --ignore-not-found || true
  kubectl_k3s delete csidriver driver.longhorn.io --ignore-not-found || true
  delete_named_resources_matching crd 'longhorn\.io'
}

add_plan_item() {
  PLAN_ITEMS+=("$1")
}

build_plan() {
  add_plan_item "Uninstall $(pk3s_runtime_cluster_label) and remove local runtime state directories if present"

  local ns
  for ns in cert-manager longhorn-system cattle-system cattle-fleet-system cattle-fleet-local-system cattle-capi-system cattle-turtles-system registry; do
    add_plan_item "Delete namespace '${ns}' if present"
  done

  local issuer
  for issuer in selfsigned letsencrypt-staging letsencrypt-production; do
    add_plan_item "Delete ClusterIssuer '${issuer}' if present"
  done

  add_plan_item "Delete Rancher/Fleet/Turtles webhook configurations if present"
  add_plan_item "Delete cattle/fleet-related APIService and CRD objects if present"
  add_plan_item "Delete Longhorn StorageClasses, CSIDriver, and CRDs if present"
  add_plan_item "Remove NFS export '${DEFAULT_NFS_EXPORT}' from /etc/exports and reload exports if present"
}

print_warning_block() {
  err "DESTRUCTIVE CLEANUP"
  line "  This script is intended to remove the local productive-k3s-core stack completely."
  line "  It can uninstall $(pk3s_runtime_cluster_label) and delete cluster namespaces and local host integrations."
  line "  It does not try to preserve cluster state."
  line "  It does not remove arbitrary user files under storage paths, but Longhorn-backed data may become unreachable once the stack is removed."
}

print_plan() {
  print_warning_block
  log "Clean plan"
  local item
  for item in "${PLAN_ITEMS[@]}"; do
    line "  - ${item}"
  done
}

remove_hosts_entries() {
  sudo sed -i "/[[:space:]]${DEFAULT_RANCHER_HOST}\b/d; /[[:space:]]${DEFAULT_REGISTRY_HOST}\b/d" /etc/hosts
}

remove_docker_trust() {
  sudo rm -rf "/etc/docker/certs.d/${DEFAULT_REGISTRY_HOST}"
  if systemctl list-unit-files docker.service >/dev/null 2>&1; then
    sudo systemctl restart docker || true
  fi
}

remove_nfs_export() {
  if [[ ! -f /etc/exports ]]; then
    return 0
  fi
  sudo sed -i "\|^[[:space:]]*${DEFAULT_NFS_EXPORT//\//\\/}[[:space:]]|d" /etc/exports
  sudo exportfs -ra || true
}

run_stack_addon_clean_hooks() {
  local addon_name addon_dir clean_fn
  [[ -n "${PRODUCTIVE_K3S_STACK_NAME}" ]] || return 0
  if ! stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    err "Stack source '${PRODUCTIVE_K3S_STACK_NAME}' was not found. Set PRODUCTIVE_K3S_ADDONS_REPO_DIR or place productive-k3s-addons beside productive-k3s-core."
    exit 1
  fi

  while IFS= read -r addon_name; do
    [[ -n "${addon_name}" ]] || continue
    if ! addon_source_script_exists "${addon_name}" clean.sh; then
      err "Addon '${addon_name}' does not provide scripts/clean.sh"
      exit 1
    fi
    addon_dir="$(resolve_addon_source_dir "${addon_name}")"
    # shellcheck source=/dev/null
    source "${addon_dir}/scripts/clean.sh"
    clean_fn="pk3s_addon_clean"
    if ! declare -F "${clean_fn}" >/dev/null 2>&1; then
      err "Addon '${addon_name}' clean hook '${clean_fn}' is missing"
      exit 1
    fi
    "${clean_fn}"
  done < <(stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}")
}

uninstall_k3s() {
  local uninstall_script killall_script runtime_path
  stop_runtime_services
  uninstall_script="$(pk3s_runtime_uninstall_script_path)"
  killall_script="$(pk3s_runtime_killall_script_path)"
  if [[ -x "${uninstall_script}" ]]; then
    sudo "${uninstall_script}" || true
  fi
  if [[ -x "${killall_script}" ]]; then
    sudo "${killall_script}" || true
  fi

  unmount_runtime_state_dirs

  while IFS= read -r runtime_path; do
    [[ -n "${runtime_path}" ]] || continue
    sudo rm -rf "${runtime_path}"
  done < <(pk3s_runtime_state_dirs)

  reload_runtime_service_manager
}

runtime_mount_points() {
  awk '{print $5}' /proc/self/mountinfo | sort -r
}

unmount_runtime_state_dirs() {
  local runtime_path mount_path
  while IFS= read -r mount_path; do
    [[ -n "${mount_path}" ]] || continue
    while IFS= read -r runtime_path; do
      [[ -n "${runtime_path}" ]] || continue
      if path_is_within_dir "${mount_path}" "${runtime_path}"; then
        sudo umount "${mount_path}" >/dev/null 2>&1 \
          || sudo umount -l "${mount_path}" >/dev/null 2>&1 \
          || true
        break
      fi
    done < <(pk3s_runtime_state_dirs)
  done < <(runtime_mount_points)
}

stop_runtime_services() {
  local service_name
  for service_name in "$(pk3s_runtime_server_service)" "$(pk3s_runtime_agent_service)"; do
    [[ -n "${service_name}" ]] || continue
    sudo systemctl stop "${service_name}" >/dev/null 2>&1 || true
    sudo systemctl disable "${service_name}" >/dev/null 2>&1 || true
  done
}

reload_runtime_service_manager() {
  sudo systemctl daemon-reload >/dev/null 2>&1 || true
  sudo systemctl reset-failed >/dev/null 2>&1 || true
}

apply_cleanup() {
  local confirm typed

  print_warning_block
  if [[ "$AUTO_APPROVE" == "y" ]]; then
    confirm="y"
  else
    prompt_yesno confirm "n" "Apply the full destructive cleanup?"
  fi
  [[ "$confirm" == "y" ]] || { warn "Cleanup cancelled."; exit 0; }

  if [[ "$FORCE_CONFIRM" == "y" ]]; then
    typed="CLEAN"
  else
    prompt_text typed "Type CLEAN to continue"
  fi
  [[ "$typed" == "CLEAN" ]] || { warn "Cleanup cancelled because confirmation text did not match."; exit 0; }

  sudo_keepalive

  log "Deleting cluster-level resources"
  run_stack_addon_clean_hooks

  log "Removing local host integrations owned by the engine"
  remove_nfs_export

  log "Uninstalling $(pk3s_runtime_cluster_label) and removing local runtime state"
  uninstall_k3s

  log "Cleanup completed"
  line "  Manual review recommended:"
  line "  - verify /etc/exports"
  line "  - verify no $(pk3s_runtime_cluster_label) processes remain"
}

main() {
  parse_args "$@"
  pk3s_runtime_validate_selection || { err "Unsupported cluster distro/engine selection."; exit 1; }
  bind_stdin_to_tty
  trap cleanup_exit EXIT
  build_plan
  print_plan

  if [[ "$MODE" == "apply" ]]; then
    apply_cleanup
  fi
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
