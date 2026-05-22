#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_INFO_PATH="${SCRIPT_DIR}/../bundle-info.json"
TELEMETRY_EVENT_SENDER="${SCRIPT_DIR}/send-telemetry-event.sh"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"

usage() {
  cat <<'EOF'
Usage:
  ./productive-k3s-core.sh <command> [args...]
  ./productive-k3s-core.sh [bootstrap args...]

Operational commands:
  bundle      Show bundle metadata for automation
  preflight   Run host compatibility checks before bootstrap
  bootstrap   Run the interactive bootstrap flow
  backup      Capture a host and cluster backup snapshot
  validate    Run the post-bootstrap validator
  help        Show this help

Examples:
  ./productive-k3s-core.sh bundle info --json
  ./productive-k3s-core.sh preflight
  ./productive-k3s-core.sh preflight --strict
  ./productive-k3s-core.sh bootstrap --dry-run
  ./productive-k3s-core.sh validate --strict

If no command is provided, or the first argument is an option, the wrapper
defaults to `bootstrap` for release-installer compatibility.
EOF
}

can_use_tty() {
  [[ -t 0 && -t 1 ]]
}

prompt_yesno() {
  local var="$1" default="$2" msg="$3"
  local answer
  if can_use_tty; then
    printf '%s [%s]: ' "$msg" "$default" > /dev/tty
    IFS= read -r answer < /dev/tty
  else
    answer="$default"
  fi
  answer="${answer:-$default}"
  printf -v "$var" '%s' "$answer"
}

resolve_telemetry_enabled() {
  if [[ -n "${TELEMETRY_ENABLED:-}" ]]; then
    return 0
  fi

  if can_use_tty; then
    local telemetry_consent="y"
    prompt_yesno telemetry_consent "y" "Productive K3S can send anonymous telemetry about this run to help improve the installation flow. It does not include any sensitive information like hostnames or other environment-specific identifiers. Enable anonymous telemetry for this run?"
    if [[ "${telemetry_consent}" == "y" ]]; then
      TELEMETRY_ENABLED="true"
    else
      TELEMETRY_ENABLED="false"
    fi
    export TELEMETRY_ENABLED
    return 0
  fi

  TELEMETRY_ENABLED="false"
  export TELEMETRY_ENABLED
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

generate_telemetry_id() {
  od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
}

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e ':a;N;$!ba;s/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

write_generic_telemetry_event() {
  local event_name="$1"
  local command_name="$2"
  local result="$3"
  local event_file

  event_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "event_family": "usage",\n'
    printf '  "event_name": "%s",\n' "$(json_escape "${event_name}")"
    printf '  "sent_at": "%s",\n' "$(json_escape "$(date -Iseconds)")"
    printf '  "session_id": "%s",\n' "$(json_escape "${TELEMETRY_SESSION_ID}")"
    printf '  "run_id": "%s",\n' "$(json_escape "${TELEMETRY_RUN_ID}")"
    printf '  "parent_run_id": "%s",\n' "$(json_escape "${TELEMETRY_PARENT_RUN_ID:-}")"
    printf '  "component": "core",\n'
    printf '  "command": {\n'
    printf '    "name": "%s",\n' "$(json_escape "${command_name}")"
    printf '    "result": "%s"\n' "$(json_escape "${result}")"
    printf '  },\n'
    printf '  "client": {\n'
    printf '    "repository": "productive-k3s-core",\n'
    printf '    "script": "scripts/productive-k3s-core.sh",\n'
    printf '    "telemetry_enabled": "%s"\n' "$(json_escape "${TELEMETRY_ENABLED}")"
    printf '  },\n'
    printf '  "telemetry_meta": {\n'
    printf '    "delivery_mode": "best-effort",\n'
    printf '    "anonymous_by_contract": true\n'
    printf '  }\n'
    printf '}\n'
  } > "${event_file}"

  TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID}" TELEMETRY_MARKER="${TELEMETRY_MARKER}" bash "${TELEMETRY_EVENT_SENDER}" "${event_file}" >/dev/null 2>&1 || true
  rm -f "${event_file}"
}

prepare_telemetry_context() {
  resolve_telemetry_enabled
  export TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-$(generate_telemetry_id)}"
  export TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID:-$(generate_telemetry_id)}"
  export TELEMETRY_COMPONENT="core"
}

run_preflight() {
  "${SCRIPT_DIR}/preflight-host.sh" "$@"
}

run_bootstrap() {
  local parent_run_id="${TELEMETRY_RUN_ID:-}"
  TELEMETRY_PARENT_RUN_ID="${parent_run_id}" TELEMETRY_RUN_ID="" TELEMETRY_COMPONENT="core" "${SCRIPT_DIR}/bootstrap-k3s-stack.sh" "$@"
}

run_backup() {
  "${SCRIPT_DIR}/backup-k3s-stack.sh" "$@"
}

resolve_bundle_version_fallback() {
  local repo_root version
  repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
  if version="$(git -C "$repo_root" describe --tags --exact-match 2>/dev/null)"; then
    printf '%s\n' "$version"
    return 0
  fi

  if version="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null)"; then
    printf '%s\n' "$version"
    return 0
  fi

  return 1
}

print_bundle_info_json() {
  local version
  if [[ -f "$BUNDLE_INFO_PATH" ]]; then
    cat "$BUNDLE_INFO_PATH"
    return 0
  fi

  if ! version="$(resolve_bundle_version_fallback)"; then
    printf 'Unable to resolve bundle metadata\n' >&2
    return 1
  fi

  cat <<EOF
{
  "schema_version": "1",
  "bundle_name": "productive-k3s-core",
  "bundle_type": "productive-k3s-core",
  "bundle_version": "${version}",
  "cli_entrypoint": "productive-k3s-core.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF
}

run_bundle() {
  if (($# != 2)) || [[ "$1" != "info" || "$2" != "--json" ]]; then
    printf 'Usage: ./productive-k3s-core.sh bundle info --json\n' >&2
    return 2
  fi
  print_bundle_info_json
}

run_validate() {
  local translated_args=()
  while (($# > 0)); do
    case "$1" in
      --json-output)
        translated_args+=(--json)
        ;;
      *)
        translated_args+=("$1")
        ;;
    esac
    shift
  done

  "${SCRIPT_DIR}/validate-k3s-stack.sh" "${translated_args[@]}"
}

main() {
  local command="${1:-bootstrap}"
  local rc=0

  if (($# == 0)); then
    command="bootstrap"
  fi

  if [[ "${command}" != "bundle" && "${command}" != "help" && "${command}" != "-h" && "${command}" != "--help" ]]; then
    prepare_telemetry_context
    if is_truthy "${TELEMETRY_ENABLED:-false}"; then
      write_generic_telemetry_event "core.command.started" "${command}" "started"
    fi
  fi

  case "$command" in
    -h|--help|help)
      usage
      ;;
    bundle)
      shift
      run_bundle "$@"
      ;;
    preflight)
      shift
      run_preflight "$@" || rc=$?
      ;;
    bootstrap)
      shift
      run_bootstrap "$@" || rc=$?
      ;;
    backup)
      shift
      run_backup "$@" || rc=$?
      ;;
    validate)
      shift
      run_validate "$@" || rc=$?
      ;;
    -*)
      command="bootstrap"
      run_bootstrap "$@" || rc=$?
      ;;
    *)
      printf 'Unsupported command: %s\n\n' "$command" >&2
      usage >&2
      exit 2
      ;;
  esac

  if [[ "${command}" != "bundle" && "${command}" != "help" && "${command}" != "-h" && "${command}" != "--help" ]] && is_truthy "${TELEMETRY_ENABLED:-false}"; then
    if (( rc == 0 )); then
      write_generic_telemetry_event "core.command.completed" "${command}" "success"
    else
      write_generic_telemetry_event "core.command.completed" "${command}" "failed"
    fi
  fi

  return "${rc}"
}

main "$@"
