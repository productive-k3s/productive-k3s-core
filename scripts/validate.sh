#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime-contract.sh"
source "${SCRIPT_DIR}/addons-runtime.sh"

STRICT=0
JSON=0
PRODUCTIVE_K3S_DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-}"
CHECKS=()

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --strict) STRICT=1 ;;
      --json) JSON=1 ;;
      -h|--help)
        cat <<EOF
Usage: $0 [--strict] [--json]

Validates the generic Productive K3S runtime. When PRODUCTIVE_K3S_STACK_NAME is
set, stack-specific validation is delegated to add-on validate hooks.
EOF
        exit 0
        ;;
      *) fail "Unknown argument: $1" ;;
    esac
    shift
  done
}

record_check() {
  local status="$1" name="$2" message="${3:-}"
  CHECKS+=("${status}|${name}|${message}")
  if [[ "$JSON" != "1" ]]; then
    printf '[%s] %s' "$status" "$name"
    [[ -z "$message" ]] || printf ': %s' "$message"
    printf '\n'
  fi
}

kubectl_cmd() {
  pk3s_runtime_kubectl "$@"
}

validate_runtime() {
  if ! pk3s_runtime_validate_selection; then
    record_check FAIL runtime "unsupported runtime selection"
    return
  fi
  record_check OK runtime "$(pk3s_runtime_cluster_label) selected"

  if ! pk3s_runtime_server_active; then
    record_check FAIL runtime-service "$(pk3s_runtime_cluster_label) server service is not active"
    return
  fi
  record_check OK runtime-service "$(pk3s_runtime_cluster_label) server service is active"

  if kubectl_cmd get nodes >/dev/null 2>&1; then
    record_check OK api "Kubernetes API is reachable"
  else
    record_check FAIL api "Kubernetes API is not reachable"
    return
  fi

  local ready_nodes
  ready_nodes="$(kubectl_cmd get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{count++} END{print count+0}')"
  if (( ready_nodes > 0 )); then
    record_check OK nodes "${ready_nodes} Ready node(s)"
  else
    record_check FAIL nodes "no Ready nodes"
  fi
}

validate_stack_addons() {
  [[ -n "${PRODUCTIVE_K3S_STACK_NAME}" ]] || return 0
  local addon_name
  if ! stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    record_check FAIL stack "stack source '${PRODUCTIVE_K3S_STACK_NAME}' not found"
    return
  fi
  while IFS= read -r addon_name; do
    [[ -n "${addon_name}" ]] || continue
    if addon_source_script_exists "${addon_name}" validate.sh; then
      if run_addon_source_script "${addon_name}" validate.sh; then
        record_check OK "addon:${addon_name}" "validate hook passed"
      else
        record_check FAIL "addon:${addon_name}" "validate hook failed"
      fi
    else
      record_check WARN "addon:${addon_name}" "no validate hook"
    fi
  done < <(stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}")
}

json_escape_value() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

print_json() {
  local first=1 record status name message
  printf '{ "checks": ['
  for record in "${CHECKS[@]}"; do
    IFS='|' read -r status name message <<< "${record}"
    if (( first == 0 )); then printf ', '; fi
    first=0
    printf '{"status":"%s","name":"%s","message":"%s"}' \
      "$(json_escape_value "$status")" \
      "$(json_escape_value "$name")" \
      "$(json_escape_value "$message")"
  done
  printf '] }\n'
}

main() {
  parse_args "$@"
  validate_runtime
  validate_stack_addons
  [[ "$JSON" == "1" ]] && print_json
  local record failed=0 warned=0 status
  for record in "${CHECKS[@]}"; do
    status="${record%%|*}"
    [[ "$status" == "FAIL" ]] && failed=1
    [[ "$status" == "WARN" ]] && warned=1
  done
  (( failed == 0 )) || exit 1
  (( STRICT == 0 || warned == 0 )) || exit 1
}

main "$@"
