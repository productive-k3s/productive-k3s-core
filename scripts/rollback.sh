#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/component-versions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/runtime-contract.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/addons-runtime.sh"
ADDONS_REPO_DIR="$(resolve_addons_repo_dir || true)"
if [[ -n "${ADDONS_REPO_DIR}" && -f "${ADDONS_REPO_DIR}/scripts/addon-host-runtime.sh" ]]; then
  # shellcheck disable=SC1091
  source "${ADDONS_REPO_DIR}/scripts/addon-host-runtime.sh"
fi

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
MANIFEST=""
MANIFEST_PRIVATE_CONTEXT=""
SUDO_KA_PID=""
AUTO_APPROVE="n"
PRODUCTIVE_K3S_DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
declare -a PLAN_IDS=()
declare -A PLAN_DESCRIPTIONS=()
declare -A PLAN_SAFETY=()
declare -A PLAN_APPLY_KIND=()

can_use_tty() {
  [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] || return 1
  : > /dev/tty 2>/dev/null || return 1
  return 0
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

bind_stdin_to_tty() {
  if can_use_tty; then
    exec </dev/tty
  fi
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

resolve_kubeconfig() {
  local distro_candidate system_kubeconfig
  system_kubeconfig="$(pk3s_runtime_system_kubeconfig_path)"
  distro_candidate="$(pk3s_runtime_default_user_kubeconfig_path)"
  local candidate
  for candidate in "${distro_candidate}" "${HOME}/.kube/config" "${system_kubeconfig}"; do
    if [[ -r "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

delete_named_resources_matching() {
  local resource="$1" pattern="$2"
  while read -r name; do
    [[ -n "$name" ]] || continue
    log "Deleting ${name}"
    kubectl_k3s delete "$name" --ignore-not-found --wait=false || true
  done < <(kubectl_k3s get "$resource" -o name 2>/dev/null | grep -E "$pattern" || true)
}

run_addon_clean_hook() {
  local addon_name="$1"
  shift || true
  local addon_dir clean_fn
  addon_dir="$(resolve_addon_source_dir "${addon_name}")" || return 1
  # shellcheck source=/dev/null
  source "${addon_dir}/scripts/clean.sh"
  clean_fn="pk3s_addon_clean"
  if ! declare -F "${clean_fn}" >/dev/null 2>&1; then
    err "Addon '${addon_name}' clean hook '${clean_fn}' is missing"
    return 1
  fi
  "${clean_fn}" "$@"
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/rollback.sh --to runs/apply-...json [--plan|--apply] [--yes]

Options:
  --to <file>   Bootstrap run manifest JSON to evaluate
  --plan        Show the rollback plan only (default)
  --apply       Execute the safe rollback actions derived from the manifest
  --yes         Auto-approve apply without prompting
  -h, --help    Show this help

Notes:
  - Dry-run manifests can be planned, but not applied.
  - High-impact host actions such as uninstalling k3s or helm are intentionally
    left as manual review items in this first rollback implementation.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --to)
        MANIFEST="${2:-}"
        shift
        ;;
      --plan)
        MODE="plan"
        ;;
      --apply)
        MODE="apply"
        ;;
      --yes)
        AUTO_APPROVE="y"
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

  if [[ -z "$MANIFEST" ]]; then
    err "You must pass --to <manifest.json>."
    usage
    exit 1
  fi
}

require_prereqs() {
  need_cmd jq || { err "jq is required."; exit 1; }
  [[ -f "$MANIFEST" ]] || { err "Manifest not found: $MANIFEST"; exit 1; }
  if [[ "$MANIFEST" =~ \.private-context$ ]]; then
    MANIFEST="${MANIFEST%.private-context}.json"
  elif [[ "$MANIFEST" =~ -private\.json$ ]]; then
    MANIFEST="${MANIFEST%-private.json}.json"
  fi
  [[ -f "$MANIFEST" ]] || { err "Public manifest not found: $MANIFEST"; exit 1; }

  if [[ -f "${MANIFEST%.json}.private-context" ]]; then
    MANIFEST_PRIVATE_CONTEXT="${MANIFEST%.json}.private-context"
  elif [[ -f "${MANIFEST%.json}-private.json" ]]; then
    MANIFEST_PRIVATE_CONTEXT="${MANIFEST%.json}-private.json"
  fi

  local manifest_distro
  manifest_distro="$(jq -r '.settings.cluster_distro // empty' "$MANIFEST")"
  if [[ -n "${manifest_distro}" ]]; then
    PRODUCTIVE_K3S_DISTRO="${manifest_distro}"
  fi
  pk3s_runtime_validate_selection || { err "Manifest requested unsupported cluster distro/engine selection."; exit 1; }
}

manifest_string() {
  local jq_expr="$1"
  jq -r "$jq_expr // empty" "$MANIFEST"
}

private_component_field() {
  local component="$1" field="$2"
  [[ -f "$MANIFEST_PRIVATE_CONTEXT" ]] || return 0
  jq -r --arg c "$component" --arg f "$field" '.components[$c][$f] // empty' "$MANIFEST_PRIVATE_CONTEXT"
}

private_setting() {
  local key="$1"
  [[ -f "$MANIFEST_PRIVATE_CONTEXT" ]] || return 0
  jq -r --arg k "$key" '.settings[$k] // empty' "$MANIFEST_PRIVATE_CONTEXT"
}

component_field() {
  local component="$1" field="$2"
  local value
  value="$(jq -r --arg c "$component" --arg f "$field" '.components[$c][$f] // empty' "$MANIFEST")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  private_component_field "$component" "$field"
}

manifest_mode() { manifest_string '.mode'; }
manifest_status() { manifest_string '.status'; }
manifest_run_id() { manifest_string '.run_id'; }

setting() {
  local key="$1"
  local value
  value="$(jq -r --arg k "$key" '.settings[$k] // empty' "$MANIFEST")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  private_setting "$key"
}

kubectl_k3s() { pk3s_runtime_kubectl "$@"; }

ns_exists() { kubectl_k3s get ns "$1" >/dev/null 2>&1; }
deployment_exists() { kubectl_k3s get deployment "$2" -n "$1" >/dev/null 2>&1; }
clusterissuer_exists() { kubectl_k3s get clusterissuer "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1"; }

force_finalize_namespace_if_present() {
  local namespace="$1"
  if ! ns_exists "$namespace"; then
    return 0
  fi

  warn "Namespace '${namespace}' still exists after rollback actions; forcing namespace finalization."
  kubectl_k3s get namespace "$namespace" -o json \
    | jq '.spec.finalizers = []' \
    | kubectl_k3s replace --raw "/api/v1/namespaces/${namespace}/finalize" -f - >/dev/null || true
}

current_state() {
  local component="$1"
  case "$component" in
    k3s)
      pk3s_runtime_server_active && echo present || echo missing
      ;;
    helm)
      need_cmd helm && echo present || echo missing
      ;;
    cert_manager)
      deployment_exists cert-manager cert-manager && echo present || echo missing
      ;;
    clusterissuer)
      local issuer
      issuer="$(component_field clusterissuer note)"
      [[ -n "$issuer" ]] && clusterissuer_exists "$issuer" && echo present || echo missing
      ;;
    longhorn)
      deployment_exists longhorn-system longhorn-driver-deployer && echo present || echo missing
      ;;
    rancher)
      deployment_exists cattle-system rancher && echo present || echo missing
      ;;
    registry)
      deployment_exists registry registry && echo present || echo missing
      ;;
    nfs)
      local export_path
      export_path="$(setting nfs_export_path)"
      if [[ -n "$export_path" ]] && grep -qE "^[[:space:]]*${export_path//\//\\/}[[:space:]]" /etc/exports 2>/dev/null; then
        echo present
      else
        echo missing
      fi
      ;;
    *)
      echo unknown
      ;;
  esac
}

add_plan_item() {
  local id="$1" description="$2" safety="$3" kind="$4"
  PLAN_IDS+=("$id")
  PLAN_DESCRIPTIONS["$id"]="$description"
  PLAN_SAFETY["$id"]="$safety"
  PLAN_APPLY_KIND["$id"]="$kind"
}

plan_remove_hosts_entry_if_managed() {
  local id_prefix="$1" host_key="$2" manage_key="$3" label="$4"
  local host manage
  host="$(setting "${host_key}")"
  manage="$(setting "${manage_key}")"
  if [[ "${manage}" == "y" && -n "${host}" ]]; then
    add_plan_item "${id_prefix}_hosts" "Remove local /etc/hosts entry for ${label} hostname '${host}'" "safe" "remove_hosts_line"
  fi
}

plan_remove_docker_trust_if_managed() {
  local id_prefix="$1" host_key="$2" manage_key="$3"
  local host manage
  host="$(setting "${host_key}")"
  manage="$(setting "${manage_key}")"
  if [[ "${manage}" == "y" && -n "${host}" ]]; then
    add_plan_item "${id_prefix}_docker_trust" "Remove local Docker trust material for registry hostname '${host}'" "safe" "remove_docker_trust"
  fi
}

apply_remove_hosts_line() {
  local host
  host="$(setting rancher_host)"
  if [[ -n "${host}" ]]; then
    pk3s_remove_local_hosts_entry "${host}"
  fi
  host="$(setting registry_host)"
  if [[ -n "${host}" ]]; then
    pk3s_remove_local_hosts_entry "${host}"
  fi
}

apply_remove_docker_trust() {
  local host
  host="$(setting registry_host)"
  [[ -n "${host}" ]] || return 0
  pk3s_remove_local_docker_trust "${host}"
}

build_plan() {
  local mode status
  mode="$(manifest_mode)"
  status="$(manifest_status)"

  if [[ "$mode" == "dry-run" ]]; then
    warn "Manifest was generated in dry-run mode. No real changes were applied by that run."
    return
  fi

  if [[ "$status" != "success" ]]; then
    warn "Manifest status is '$status'. Rollback planning will be conservative."
  fi

  local detected planned result now

  detected="$(component_field clusterissuer detected_before)"
  planned="$(component_field clusterissuer planned_action)"
  result="$(component_field clusterissuer result)"
  now="$(current_state clusterissuer)"
  if [[ "$detected" == "missing" && "$planned" == "ensure" && "$result" == "installed" && "$now" == "present" ]]; then
    add_plan_item "clusterissuer" "Delete ClusterIssuer '$(component_field clusterissuer note)'" "safe" "kubectl_delete_clusterissuer"
  fi

  detected="$(component_field cert_manager detected_before)"
  planned="$(component_field cert_manager planned_action)"
  result="$(component_field cert_manager result)"
  now="$(current_state cert_manager)"
  if [[ "$detected" == "missing" && "$planned" == "install" && "$result" == "installed" && "$now" == "present" ]]; then
    add_plan_item "cert_manager" "Delete cert-manager resources that were installed by the bootstrap run" "safe" "kubectl_delete_cert_manager"
  fi

  detected="$(component_field longhorn detected_before)"
  planned="$(component_field longhorn planned_action)"
  result="$(component_field longhorn result)"
  now="$(current_state longhorn)"
  if [[ "$detected" == "missing" && "$planned" == "install" && "$result" == "installed" && "$now" == "present" ]]; then
    add_plan_item "longhorn" "Uninstall Longhorn release and namespace resources" "moderate" "helm_uninstall_longhorn"
  fi

  detected="$(component_field rancher detected_before)"
  planned="$(component_field rancher planned_action)"
  result="$(component_field rancher result)"
  now="$(current_state rancher)"
  if [[ "$detected" == "missing" && "$planned" == "install" && "$result" == "installed" && "$now" == "present" ]]; then
    plan_remove_hosts_entry_if_managed "rancher" "rancher_host" "rancher_manage_local_hosts" "Rancher"
    add_plan_item "rancher" "Uninstall Rancher release and cattle-system/Fleet/Turtles resources" "moderate" "helm_uninstall_rancher"
  fi

  detected="$(component_field registry detected_before)"
  planned="$(component_field registry planned_action)"
  result="$(component_field registry result)"
  now="$(current_state registry)"
  if [[ "$detected" == "missing" && "$planned" == "install" && "$result" == "installed" && "$now" == "present" ]]; then
    plan_remove_hosts_entry_if_managed "registry" "registry_host" "registry_manage_local_hosts" "registry"
    plan_remove_docker_trust_if_managed "registry" "registry_host" "registry_trust_docker"
    add_plan_item "registry" "Delete registry namespace resources created by the bootstrap run" "moderate" "kubectl_delete_registry"
  fi

  detected="$(component_field nfs detected_before)"
  planned="$(component_field nfs planned_action)"
  result="$(component_field nfs result)"
  now="$(current_state nfs)"
  if [[ "$planned" =~ ^(install|add-export)$ && "$result" == "configured" && "$now" == "present" ]]; then
    add_plan_item "nfs_export" "Remove NFS export '$(setting nfs_export_path)' from /etc/exports and reload exports" "moderate" "remove_nfs_export"
    if [[ "$detected" == "missing" ]]; then
      add_plan_item "nfs_service_manual" "Review whether the NFS service/package installed by bootstrap should also be removed manually" "manual" "manual"
    fi
  fi

  detected="$(component_field k3s detected_before)"
  planned="$(component_field k3s planned_action)"
  result="$(component_field k3s result)"
  if [[ "$detected" == "missing" && "$planned" == "install" && "$result" == "installed" ]]; then
    add_plan_item "k3s_manual" "$(pk3s_runtime_cluster_label) was installed by this run. Uninstalling it is high-impact and remains manual in this rollback implementation." "manual" "manual"
  fi

  detected="$(component_field helm detected_before)"
  planned="$(component_field helm planned_action)"
  result="$(component_field helm result)"
  if [[ "$detected" == "missing" && "$planned" == "install" && "$result" == "installed" ]]; then
    add_plan_item "helm_manual" "helm was installed by this run. Removing it remains manual in this rollback implementation." "manual" "manual"
  fi
}

print_plan() {
  log "Rollback plan for $(manifest_run_id)"
  line "  Manifest: $MANIFEST"
  line "  Mode: $(manifest_mode)"
  line "  Status: $(manifest_status)"

  if (( ${#PLAN_IDS[@]} == 0 )); then
    line "  No rollback actions are required or safely derivable from this manifest."
    return
  fi

  line "  Proposed actions:"
  local id
  for id in "${PLAN_IDS[@]}"; do
    line "    - [${PLAN_SAFETY[$id]}] ${PLAN_DESCRIPTIONS[$id]}"
  done
}

apply_kubectl_delete_cert_manager() {
  kubectl_k3s delete -f "https://github.com/cert-manager/cert-manager/releases/download/${PRODUCTIVE_K3S_CERT_MANAGER_VERSION:-v1.19.4}/cert-manager.yaml" || true
  kubectl_k3s delete namespace cert-manager --ignore-not-found --wait=false || true
}

apply_kubectl_delete_clusterissuer() {
  local issuer
  issuer="$(component_field clusterissuer note)"
  [[ -n "$issuer" ]] || return 0
  kubectl_k3s delete clusterissuer "$issuer" --ignore-not-found
}

delete_rancher_cluster_artifacts() {
  delete_named_resources_matching validatingwebhookconfigurations 'rancher|fleet|cattle'
  delete_named_resources_matching mutatingwebhookconfigurations 'rancher|fleet|cattle'
  delete_named_resources_matching apiservices 'cattle|fleet'
  delete_named_resources_matching crd 'cattle\.io|fleet\.cattle\.io'
}

delete_longhorn_cluster_artifacts() {
  delete_named_resources_matching validatingwebhookconfigurations 'longhorn'
  delete_named_resources_matching mutatingwebhookconfigurations 'longhorn'
  kubectl_k3s delete storageclass longhorn longhorn-static --ignore-not-found || true
  kubectl_k3s delete csidriver driver.longhorn.io --ignore-not-found || true
  delete_named_resources_matching crd 'longhorn\.io'
}

apply_helm_uninstall_longhorn() {
  helm uninstall longhorn -n longhorn-system || true
  run_addon_clean_hook longhorn || true
  force_finalize_namespace_if_present longhorn-system
}

apply_helm_uninstall_rancher() {
  local rancher_host
  rancher_host="$(setting rancher_host)"
  run_addon_clean_hook rancher "${rancher_host}" || true
  helm uninstall rancher -n cattle-system || true
  force_finalize_namespace_if_present cattle-turtles-system
  force_finalize_namespace_if_present cattle-capi-system
  force_finalize_namespace_if_present cattle-fleet-local-system
  force_finalize_namespace_if_present cattle-fleet-system
  force_finalize_namespace_if_present cattle-system
}

apply_kubectl_delete_registry() {
  local registry_host
  registry_host="$(setting registry_host)"
  run_addon_clean_hook registry "${registry_host}" || true
  force_finalize_namespace_if_present registry
}

apply_remove_nfs_export() {
  local export_path
  export_path="$(setting nfs_export_path)"
  [[ -n "$export_path" ]] || return 0
  sudo sed -i "\|^[[:space:]]*${export_path//\//\\/}[[:space:]]|d" /etc/exports
  sudo exportfs -ra
}

apply_plan() {
  local mode
  mode="$(manifest_mode)"
  if [[ "$mode" == "dry-run" ]]; then
    err "Refusing to apply rollback from a dry-run manifest."
    exit 1
  fi

  if (( ${#PLAN_IDS[@]} == 0 )); then
    log "Nothing to apply."
    return
  fi

  local confirm
  if [[ "$AUTO_APPROVE" == "y" ]]; then
    confirm="y"
  else
    prompt_yesno confirm "n" "Apply the safe rollback actions from this manifest?"
  fi
  [[ "$confirm" == "y" ]] || { warn "Rollback cancelled."; exit 0; }

  bind_stdin_to_tty
  sudo_keepalive

  local kubeconfig
  kubeconfig="$(resolve_kubeconfig)" || {
    err "Could not find a readable kubeconfig for helm-based rollback actions."
    exit 1
  }
  export KUBECONFIG="$kubeconfig"

  local id
  for id in "${PLAN_IDS[@]}"; do
    case "${PLAN_APPLY_KIND[$id]}" in
      kubectl_delete_cert_manager)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_kubectl_delete_cert_manager
        ;;
      kubectl_delete_clusterissuer)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_kubectl_delete_clusterissuer
        ;;
      helm_uninstall_longhorn)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_helm_uninstall_longhorn
        ;;
      helm_uninstall_rancher)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_helm_uninstall_rancher
        ;;
      kubectl_delete_registry)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_kubectl_delete_registry
        ;;
      remove_nfs_export)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_remove_nfs_export
        ;;
      remove_hosts_line)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_remove_hosts_line
        ;;
      remove_docker_trust)
        log "${PLAN_DESCRIPTIONS[$id]}"
        apply_remove_docker_trust
        ;;
      manual)
        warn "Manual follow-up: ${PLAN_DESCRIPTIONS[$id]}"
        ;;
      *)
        warn "Unknown rollback action kind for ${id}: ${PLAN_APPLY_KIND[$id]}"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  bind_stdin_to_tty
  trap cleanup_exit EXIT
  require_prereqs
  build_plan
  print_plan

  if [[ "$MODE" == "apply" ]]; then
    apply_plan
  fi
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
