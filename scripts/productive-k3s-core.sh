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
  ./productive-k3s-core.sh addon <validate|install> --tgz <file>
  ./productive-k3s-core.sh dev addon validate --source <dir>
  ./productive-k3s-core.sh [bootstrap args...]

Operational commands:
  bundle      Show bundle metadata for automation
  preflight   Run host compatibility checks before bootstrap
  bootstrap   Run the interactive bootstrap flow
  backup      Capture a host and cluster backup snapshot
  validate    Run the post-bootstrap validator
  addon       Validate or install packaged add-ons
  dev         Development-oriented source-based addon workflows
  help        Show this help

Examples:
  ./productive-k3s-core.sh bundle info --json
  ./productive-k3s-core.sh preflight
  ./productive-k3s-core.sh preflight --strict
  ./productive-k3s-core.sh bootstrap --dry-run
  ./productive-k3s-core.sh validate --strict
  ./productive-k3s-core.sh addon validate --tgz ./longhorn-addon.tgz

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

trim_yaml_value() {
  local value="$1"
  value="${value#*:}"
  value="${value# }"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "${value}"
}

addon_yaml_get() {
  local file="$1"
  local key="$2"
  awk -v key="${key}" '
    /^metadata:/ { section="metadata"; subsection=""; next }
    /^spec:/ { section="spec"; subsection=""; next }
    section == "spec" && /^  install:/ { subsection="install"; next }
    section == "metadata" && key == "metadata.name" && /^  name:/ { print; exit }
    section == "metadata" && key == "metadata.version" && /^  version:/ { print; exit }
    section == "spec" && key == "spec.type" && /^  type:/ { print; exit }
    section == "spec" && subsection == "install" && key == "spec.install.script" && /^    script:/ { print; exit }
  ' "${file}"
}

extract_tgz_to_temp() {
  local archive="$1"
  [[ -f "${archive}" ]] || {
    printf 'tgz package not found: %s\n' "${archive}" >&2
    return 3
  }
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  tar -xzf "${archive}" -C "${tmp_dir}" || {
    rm -rf "${tmp_dir}"
    printf 'could not extract tgz package: %s\n' "${archive}" >&2
    return 4
  }
  printf '%s\n' "${tmp_dir}"
}

resolve_addon_manifest() {
  local package_root="$1"
  local manifest
  manifest="$(find "${package_root}" -type f -name 'addon.yaml' | head -n1)"
  [[ -n "${manifest}" ]] || {
    printf 'addon package is missing addon.yaml\n' >&2
    return 4
  }
  printf '%s\n' "${manifest}"
}

validate_addon_manifest() {
  local manifest="$1"
  local addon_name addon_type install_script
  addon_name="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "metadata.name")")"
  addon_type="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "spec.type")")"
  install_script="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "spec.install.script")")"

  [[ -n "${addon_name}" ]] || {
    printf 'addon package metadata.name is required\n' >&2
    return 4
  }
  [[ -n "${addon_type}" ]] || {
    printf 'addon package spec.type is required\n' >&2
    return 4
  }
  [[ -n "${install_script}" ]] || {
    printf 'addon package spec.install.script is required\n' >&2
    return 4
  }

  printf '%s\n%s\n%s\n' "${addon_name}" "${addon_type}" "${install_script}"
}

run_addon_validate() {
  local tgz_path=""
  while (($# > 0)); do
    case "$1" in
      --tgz)
        tgz_path="${2:-}"
        shift 2
        ;;
      *)
        printf 'Usage: ./productive-k3s-core.sh addon validate --tgz <file>\n' >&2
        return 2
        ;;
    esac
  done
  [[ -n "${tgz_path}" ]] || {
    printf 'Usage: ./productive-k3s-core.sh addon validate --tgz <file>\n' >&2
    return 2
  }

  local tmp_dir manifest metadata addon_name addon_type install_script
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")" || return $?
  manifest="$(resolve_addon_manifest "${tmp_dir}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  metadata="$(validate_addon_manifest "${manifest}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  addon_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  addon_type="$(printf '%s\n' "${metadata}" | sed -n '2p')"
  install_script="$(printf '%s\n' "${metadata}" | sed -n '3p')"

  printf 'Addon package: %s\n' "${addon_name}"
  printf 'Addon type: %s\n' "${addon_type}"
  printf 'Install script: %s\n' "${install_script}"
  printf 'Addon package validation passed\n'
  rm -rf "${tmp_dir}"
}

run_addon_install() {
  local tgz_path=""
  while (($# > 0)); do
    case "$1" in
      --tgz)
        tgz_path="${2:-}"
        shift 2
        ;;
      *)
        printf 'Usage: ./productive-k3s-core.sh addon install --tgz <file>\n' >&2
        return 2
        ;;
    esac
  done
  [[ -n "${tgz_path}" ]] || {
    printf 'Usage: ./productive-k3s-core.sh addon install --tgz <file>\n' >&2
    return 2
  }

  local tmp_dir manifest metadata install_script manifest_dir install_path
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")" || return $?
  manifest="$(resolve_addon_manifest "${tmp_dir}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  metadata="$(validate_addon_manifest "${manifest}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  install_script="$(printf '%s\n' "${metadata}" | sed -n '3p')"
  manifest_dir="$(dirname "${manifest}")"
  install_path="${manifest_dir}/${install_script}"
  [[ -f "${install_path}" ]] || {
    rm -rf "${tmp_dir}"
    printf 'addon package install script not found: %s\n' "${install_script}" >&2
    return 4
  }

  printf 'Executing packaged addon installer: %s\n' "${install_script}"
  (
    cd "${manifest_dir}"
    bash "${install_path}"
  )
  local rc=$?
  rm -rf "${tmp_dir}"
  return "${rc}"
}

run_dev_addon_validate() {
  local source_dir=""
  while (($# > 0)); do
    case "$1" in
      --source)
        source_dir="${2:-}"
        shift 2
        ;;
      *)
        printf 'Usage: ./productive-k3s-core.sh dev addon validate --source <dir>\n' >&2
        return 2
        ;;
    esac
  done
  [[ -n "${source_dir}" ]] || {
    printf 'Usage: ./productive-k3s-core.sh dev addon validate --source <dir>\n' >&2
    return 2
  }
  local manifest metadata
  manifest="${source_dir}/addon.yaml"
  [[ -f "${manifest}" ]] || {
    printf 'addon source is missing addon.yaml\n' >&2
    return 4
  }
  metadata="$(validate_addon_manifest "${manifest}")" || return $?
  printf 'Addon source validation passed\n'
}

run_addon() {
  local action="${1:-}"
  shift || true
  case "${action}" in
    validate)
      run_addon_validate "$@"
      ;;
    install)
      run_addon_install "$@"
      ;;
    *)
      printf 'Usage: ./productive-k3s-core.sh addon <validate|install> --tgz <file>\n' >&2
      return 2
      ;;
  esac
}

run_dev() {
  local area="${1:-}"
  local action="${2:-}"
  shift 2 || true
  case "${area}:${action}" in
    addon:validate)
      run_dev_addon_validate "$@"
      ;;
    *)
      printf 'Usage: ./productive-k3s-core.sh dev addon validate --source <dir>\n' >&2
      return 2
      ;;
  esac
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
    addon)
      shift
      run_addon "$@" || rc=$?
      ;;
    dev)
      shift
      run_dev "$@" || rc=$?
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
