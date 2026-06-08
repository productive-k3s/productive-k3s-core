#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/addons-runtime.sh"

STRICT=0
JSON_OUTPUT=0
DOCKER_REGISTRY_TEST=0
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-base}"
FAILURES=0
WARNINGS=0
CHECK_RESULTS=()

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

append_result() {
  local level="$1" message="$2"
  CHECK_RESULTS+=("{\"level\":\"$(json_escape "$level")\",\"message\":\"$(json_escape "$message")\"}")
}

ok() {
  append_result "ok" "$1"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\033[1;32m[OK]\033[0m %s\n" "$1"
  fi
}

warn() {
  append_result "warn" "$1"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\033[1;33m[WARN]\033[0m %s\n" "$1"
  fi
}

fail() {
  append_result "fail" "$1"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\033[1;31m[FAIL]\033[0m %s\n" "$1"
  fi
}

info() {
  append_result "info" "$1"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\n\033[1;34m[INFO]\033[0m %s\n" "$1"
  fi
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --strict)
        STRICT=1
        ;;
      --json)
        JSON_OUTPUT=1
        ;;
      -h|--help)
        cat <<EOF
Usage: $0 [--strict] [--json] [--docker-registry-test]

  --strict   Exit non-zero on warnings as well as failures
  --json     Emit machine-readable JSON instead of human-readable output
  --docker-registry-test
             Run docker push/pull validation against registry.home.arpa
             If REGISTRY_USER and REGISTRY_PASSWORD are set, it also validates docker login
EOF
        exit 0
        ;;
      --docker-registry-test)
        DOCKER_REGISTRY_TEST=1
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

record_ok() {
  ok "$1"
}

record_warn() {
  WARNINGS=$((WARNINGS + 1))
  warn "$1"
}

record_fail() {
  FAILURES=$((FAILURES + 1))
  fail "$1"
}

sudo_keepalive() {
  if ! sudo -n true 2>/dev/null; then
    info "Requesting sudo"
    sudo -v || {
      record_fail "sudo authentication failed"
      exit 1
    }
  fi
  ( while true; do sudo -n true; sleep 30; done ) >/dev/null 2>&1 &
  SUDO_KA_PID=$!
  trap 'kill ${SUDO_KA_PID:-0} >/dev/null 2>&1 || true' EXIT
}

k() {
  sudo k3s kubectl "$@"
}

safe_run() {
  local output
  if ! output="$("$@" 2>&1)"; then
    printf '%s' "$output"
    return 1
  fi
  printf '%s' "$output"
}

cluster_node_count() {
  k get nodes --no-headers 2>/dev/null | awk 'END {print NR+0}'
}

default_storageclasses() {
  k get sc -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
  | awk -F'|' '$2 == "true" {print $1}'
}

longhorn_setting_value() {
  local setting_name="$1"
  k get settings.longhorn.io -n longhorn-system "$setting_name" -o jsonpath='{.value}' 2>/dev/null || true
}

check_longhorn_volume_health() {
  need_cmd jq || {
    record_warn "jq is not available; skipping detailed Longhorn volume health checks"
    return
  }

  local volumes_json active_problematic inactive_problematic
  if ! volumes_json="$(safe_run k get volumes.longhorn.io -n longhorn-system -o json 2>/dev/null)"; then
    record_warn "unable to query detailed Longhorn volume state"
    return
  fi

  active_problematic="$(printf '%s\n' "$volumes_json" | jq -r '
    .items[]
    | . as $v
    | ((.status.kubernetesStatus.workloadsStatus // [])
        | map(select((.podStatus // "") != "" and (.podStatus != "Succeeded") and (.podStatus != "Failed")))
      ) as $active
    | select(($active | length) > 0)
    | select((.status.state // "") != "attached" or (.status.robustness // "") != "healthy")
    | [
        .metadata.name,
        "state=" + (.status.state // "unknown"),
        "robustness=" + (.status.robustness // "unknown"),
        "workloads=" + ($active | map((.workloadType // "?") + "/" + (.workloadName // "?") + " pod=" + (.podName // "?") + " status=" + (.podStatus // "?")) | join("; "))
      ]
    | join(" ")
  ')"

  inactive_problematic="$(printf '%s\n' "$volumes_json" | jq -r '
    .items[]
    | . as $v
    | ((.status.kubernetesStatus.workloadsStatus // [])
        | map(select((.podStatus // "") != "" and (.podStatus != "Succeeded") and (.podStatus != "Failed")))
      ) as $active
    | select(($active | length) == 0)
    | select((.status.state // "") != "attached" or (.status.robustness // "") != "healthy")
    | [
        .metadata.name,
        "state=" + (.status.state // "unknown"),
        "robustness=" + (.status.robustness // "unknown")
      ]
    | join(" ")
  ')"

  if [[ -n "$active_problematic" ]]; then
    record_fail "Longhorn has problematic volumes backing active workloads"
    printf '%s\n' "$active_problematic"
  else
    record_ok "Longhorn volumes backing active workloads are attached and healthy"
  fi

  if [[ -n "$inactive_problematic" ]]; then
    record_warn "Longhorn has problematic volumes without active workloads"
    printf '%s\n' "$inactive_problematic"
  fi
}

active_pod_table() {
  k get pods "$@" --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide
}

count_terminal_pods() {
  local count status_col=3
  if [[ " $* " == *" -A "* ]]; then
    status_col=4
  fi
  count="$(k get pods "$@" --no-headers 2>/dev/null | awk -v status_col="$status_col" '
    {
      status=$status_col
      if (status == "Completed" || status == "Error" || status == "Evicted" || status == "ContainerStatusUnknown") count++
    }
    END {print count+0}
  ')"
  printf '%s' "$count"
}

check_namespace_workloads() {
  local ns="$1"
  local label="$2"
  local deployments statefulsets daemonsets bad=""

  if deployments="$(safe_run k get deploy -n "$ns" --no-headers 2>/dev/null)"; then
    local deploy_bad
    deploy_bad="$(printf '%s\n' "$deployments" | awk '
      NF == 0 {next}
      /^No resources found/ {next}
      {
        split($2, ready, "/")
        if (ready[1] != ready[2]) print "deployment/" $1 " " $2
      }
    ')"
    [[ -n "$deploy_bad" ]] && bad+="${deploy_bad}"$'\n'
  fi

  if statefulsets="$(safe_run k get statefulset -n "$ns" --no-headers 2>/dev/null)"; then
    local sts_bad
    sts_bad="$(printf '%s\n' "$statefulsets" | awk '
      NF == 0 {next}
      /^No resources found/ {next}
      {
        split($2, ready, "/")
        if (ready[1] != ready[2]) print "statefulset/" $1 " " $2
      }
    ')"
    [[ -n "$sts_bad" ]] && bad+="${sts_bad}"$'\n'
  fi

  if daemonsets="$(safe_run k get daemonset -n "$ns" --no-headers 2>/dev/null)"; then
    local ds_bad
    ds_bad="$(printf '%s\n' "$daemonsets" | awk '
      NF == 0 {next}
      /^No resources found/ {next}
      {
        desired=$2
        ready=$4
        if (ready != desired) print "daemonset/" $1 " ready=" ready "/" desired
      }
    ')"
    [[ -n "$ds_bad" ]] && bad+="${ds_bad}"$'\n'
  fi

  printf '%s' "$bad"
}

check_cmds() {
  info "Checking required commands"
  local missing=()
  local cmd
  for cmd in sudo k3s kubectl curl getent; do
    if ! need_cmd "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if ((${#missing[@]} > 0)); then
    record_fail "missing required commands: ${missing[*]}"
  else
    record_ok "required commands are available"
  fi

  if (( DOCKER_REGISTRY_TEST == 1 )); then
    if need_cmd docker; then
      record_ok "docker is available for registry functional validation"
    else
      record_fail "docker is required for --docker-registry-test"
    fi
  fi
}

check_k3s_service() {
  info "Checking k3s service"
  if sudo systemctl is-active --quiet k3s; then
    record_ok "k3s service is active"
  else
    record_fail "k3s service is not active"
  fi
}

check_nodes() {
  info "Checking cluster nodes"
  local nodes statuses
  if ! nodes="$(safe_run k get nodes -o wide)"; then
    record_fail "unable to query cluster nodes"
    return
  fi

  statuses="$(printf '%s\n' "$nodes" | awk 'NR>1 {print $2}')"
  if [[ -z "$statuses" ]]; then
    record_fail "cluster returned no nodes"
    return
  fi

  if printf '%s\n' "$statuses" | grep -qv '^Ready$'; then
    record_fail "one or more nodes are not Ready"
    printf '%s\n' "$nodes"
  else
    record_ok "all nodes are Ready"
  fi
}

check_all_pods() {
  info "Checking all pods"
  local pods bad historical_failed
  if ! pods="$(safe_run active_pod_table -A)"; then
    record_fail "unable to list pods"
    return
  fi

  bad="$(printf '%s\n' "$pods" | awk '
    NR==1 {next}
    {
      ready=$3
      status=$4
      split(ready,a,"/")
      if (status != "Running" && status != "Completed") print
      else if (status == "Running" && a[1] != a[2]) print
    }
  ')"

  if [[ -n "$bad" ]]; then
    record_fail "there are active pods not healthy enough"
    printf '%s\n' "$bad"
  else
    record_ok "all active pods are Running and Ready"
  fi

  historical_failed="$(count_terminal_pods -A)"
  if [[ "$historical_failed" != "0" ]]; then
    info "Ignoring ${historical_failed} historical terminal pod(s) with statuses like Completed, Error, Evicted, or ContainerStatusUnknown"
  fi
}

check_storage_classes() {
  info "Checking storage classes"
  local sc defaults
  if ! sc="$(safe_run k get sc)"; then
    record_fail "unable to query storage classes"
    return
  fi

  defaults="$(printf '%s\n' "$sc" | awk 'NR>1 && $1 ~ /\(default\)$/ {count++} END {print count+0}')"
  if [[ "$defaults" == "0" ]]; then
    defaults="$(printf '%s\n' "$sc" | grep -c '(default)' || true)"
  fi
  if [[ "$defaults" == "1" ]]; then
    record_ok "exactly one default StorageClass is configured"
  elif [[ "$defaults" == "0" ]]; then
    record_warn "no default StorageClass is configured"
  else
    record_fail "multiple default StorageClasses are configured"
    printf '%s\n' "$sc"
  fi
}

check_ingress() {
  info "Checking ingress resources"
  local ingress
  if ! ingress="$(safe_run k get ingress -A)"; then
    record_fail "unable to query ingress resources"
    return
  fi

  if printf '%s\n' "$ingress" | awk 'NR>1 {print}' | grep -q .; then
    record_ok "ingress resources are present"
  else
    record_warn "no ingress resources found"
  fi
}

check_namespace_rollup() {
  local ns="$1" label="$2"
  info "Checking ${label} namespace"

  if ! k get namespace "$ns" >/dev/null 2>&1; then
    record_warn "namespace '${ns}' does not exist"
    return
  fi

  local pods
  if ! pods="$(safe_run active_pod_table -n "$ns")"; then
    record_fail "unable to query pods in namespace '${ns}'"
    return
  fi

  local bad
  bad="$(printf '%s\n' "$pods" | awk '
    NR==1 {next}
    {
      ready=$2
      status=$3
      split(ready,a,"/")
      if (status != "Running" && status != "Completed") print
      else if (status == "Running" && a[1] != a[2]) print
    }
  ')"

  local workload_bad
  workload_bad="$(check_namespace_workloads "$ns" "$label")"

  if [[ -n "$bad" ]]; then
    record_fail "${label} has unhealthy pods"
    printf '%s\n' "$bad"
  elif [[ -n "$workload_bad" ]]; then
    record_fail "${label} has workloads that are not fully ready"
    printf '%s\n' "$workload_bad"
  else
    record_ok "${label} active pods and workloads are healthy"
  fi

  local historical_terminal
  historical_terminal="$(count_terminal_pods -n "$ns")"
  if [[ "$historical_terminal" != "0" ]]; then
    info "Ignoring ${historical_terminal} historical terminal pod(s) in namespace '${ns}'"
  fi
}

run_stack_addon_validations() {
  local addon_name addon_dir validate_fn
  if ! stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    record_fail "stack source '${PRODUCTIVE_K3S_STACK_NAME}' could not be resolved for validation"
    return
  fi

  while IFS= read -r addon_name; do
    [[ -n "${addon_name}" ]] || continue
    if ! addon_source_script_exists "${addon_name}" validate.sh; then
      record_fail "addon '${addon_name}' does not provide scripts/validate.sh"
      continue
    fi
    addon_dir="$(resolve_addon_source_dir "${addon_name}")"
    # shellcheck source=/dev/null
    source "${addon_dir}/scripts/validate.sh"
    validate_fn="pk3s_addon_validate"
    if ! declare -F "${validate_fn}" >/dev/null 2>&1; then
      record_fail "addon '${addon_name}' validate hook '${validate_fn}' is missing"
      continue
    fi
    "${validate_fn}"
  done < <(stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}")
}

check_nfs() {
  info "Checking NFS exports"
  local service_name="nfs-kernel-server"
  if systemctl list-unit-files nfs-server.service >/dev/null 2>&1; then
    service_name="nfs-server"
  fi

  if sudo systemctl is-active --quiet "$service_name"; then
    record_ok "NFS service '${service_name}' is active"
  else
    record_warn "NFS service '${service_name}' is not active"
  fi

  local exports
  if ! exports="$(safe_run sudo exportfs -v)"; then
    record_warn "unable to query NFS exports"
    return
  fi

  if printf '%s\n' "$exports" | grep -q '^/srv/nfs/k8s-share'; then
    record_ok "expected NFS export '/srv/nfs/k8s-share' is present"
  else
    record_warn "expected NFS export '/srv/nfs/k8s-share' is not present"
  fi
}

print_summary() {
  local exit_code=0
  if (( FAILURES > 0 )); then
    exit_code=1
  elif (( STRICT == 1 && WARNINGS > 0 )); then
    exit_code=1
  fi

  if [[ "$JSON_OUTPUT" == "1" ]]; then
    local status="ok"
    if (( FAILURES > 0 )); then
      status="fail"
    elif (( WARNINGS > 0 )); then
      status="warn"
    fi

    printf '{'
    printf '"status":"%s",' "$status"
    printf '"strict":%s,' "$( (( STRICT == 1 )) && echo true || echo false )"
    printf '"failures":%d,' "$FAILURES"
    printf '"warnings":%d,' "$WARNINGS"
    printf '"results":['
    local i
    for i in "${!CHECK_RESULTS[@]}"; do
      [[ "$i" -gt 0 ]] && printf ','
      printf '%s' "${CHECK_RESULTS[$i]}"
    done
    printf ']}\n'
  else
    echo
    info "Validation summary"
    echo "Failures: ${FAILURES}"
    echo "Warnings: ${WARNINGS}"
    if (( STRICT == 1 )); then
      echo "Mode: strict"
    fi
  fi

  exit "$exit_code"
}

main() {
  parse_args "$@"
  sudo_keepalive
  check_cmds
  check_k3s_service
  check_nodes
  check_all_pods
  check_storage_classes
  check_ingress
  run_stack_addon_validations
  check_nfs
  print_summary
}

main "$@"
