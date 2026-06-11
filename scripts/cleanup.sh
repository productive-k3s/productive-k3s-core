#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  - k3s cluster components and local k3s state
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

kubectl_k3s() { sudo k3s kubectl "$@"; }
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
  if ! service_active k3s; then
    return
  fi
  delete_named_resources_matching validatingwebhookconfigurations 'rancher|fleet|cattle'
  delete_named_resources_matching mutatingwebhookconfigurations 'rancher|fleet|cattle'
  delete_named_resources_matching apiservices 'cattle|fleet'
  delete_named_resources_matching crd 'cattle\.io|fleet\.cattle\.io'
}

delete_longhorn_cluster_artifacts() {
  if ! service_active k3s; then
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
  add_plan_item "Uninstall k3s and remove local k3s state directories if present"

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
  line "  It can uninstall k3s and delete cluster namespaces and local host integrations."
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
  if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
    sudo /usr/local/bin/k3s-uninstall.sh || true
  elif [[ -x /usr/local/bin/k3s-killall.sh ]]; then
    sudo /usr/local/bin/k3s-killall.sh || true
  fi

  sudo rm -rf /etc/rancher/k3s
  sudo rm -rf /var/lib/rancher/k3s
  sudo rm -rf /var/lib/kubelet
  sudo rm -rf /etc/cni/net.d
  sudo rm -rf /var/lib/cni
  sudo rm -rf /run/flannel
  sudo rm -rf /run/k3s
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

  log "Uninstalling k3s and removing local k3s state"
  uninstall_k3s

  log "Cleanup completed"
  line "  Manual review recommended:"
  line "  - verify /etc/exports"
  line "  - verify no k3s processes remain"
}

main() {
  parse_args "$@"
  bind_stdin_to_tty
  trap cleanup_exit EXIT
  build_plan
  print_plan

  if [[ "$MODE" == "apply" ]]; then
    apply_cleanup
  fi
}

main "$@"
