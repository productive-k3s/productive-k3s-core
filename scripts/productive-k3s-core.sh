#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/component-versions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/runtime-contract.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/addons-runtime.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/export-runtime.sh"
BUNDLE_INFO_PATH="${SCRIPT_DIR}/../bundle-info.json"
TELEMETRY_EVENT_SENDER="${SCRIPT_DIR}/send-telemetry-event.sh"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"
GLOBAL_EVENTS_FORMAT=""

usage() {
  cat <<'EOF'
Usage:
  ./productive-k3s-core.sh <command> [args...]
  ./productive-k3s-core.sh addon validate --tgz <file>
  ./productive-k3s-core.sh addon install --tgz <file> [--public-host <fqdn>]
  ./productive-k3s-core.sh stack <install|export|validate|backup|cleanup> <name> [args...]
  ./productive-k3s-core.sh stack install --tgz <file> [args...]
  ./productive-k3s-core.sh stack export --tgz <file> --output <dir|archive>
  ./productive-k3s-core.sh dev addon validate --source <dir>
  ./productive-k3s-core.sh dev stack validate --source <dir>
  ./productive-k3s-core.sh [apply args...]

Operational commands:
  bundle      Show bundle metadata for automation
  bom         Show a JSON bill of materials for this CLI/runtime
  preflight   Run host compatibility checks before apply
  apply       Install the local Productive K3S core only
  backup      Capture a host and cluster backup snapshot
  validate    Run the post-apply validator
  addon       Validate or install add-ons on the local host/cluster
  stack       Install or manage named stacks on the local host/cluster
  dev         Development-oriented source-based addon workflows
  help        Show this help

Examples:
  ./productive-k3s-core.sh bundle info --json
  ./productive-k3s-core.sh bom --json
  ./productive-k3s-core.sh preflight
  ./productive-k3s-core.sh preflight --strict
  ./productive-k3s-core.sh apply --dry-run
  ./productive-k3s-core.sh stack install base
  ./productive-k3s-core.sh stack export --tgz ./base-stack.tgz --output ./base-installer
  ./productive-k3s-core.sh stack validate base --strict
  ./productive-k3s-core.sh validate --strict
  ./productive-k3s-core.sh addon validate --tgz ./longhorn-addon.tgz
  ./productive-k3s-core.sh addon install --tgz ./nginx-addon.tgz --public-host nginx-01.k3s.lab.internal
  ./productive-k3s-core.sh addon install --events ndjson --tgz ./nginx-addon.tgz

If no command is provided, or the first argument is an option, the wrapper
defaults to `apply` for release-installer compatibility.
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

operation_events_enabled() {
  [[ "${GLOBAL_EVENTS_FORMAT:-}" == "ndjson" ]]
}

setup_operation_event_output() {
  [[ -z "${GLOBAL_EVENTS_FORMAT:-}" ]] && return 0
  if [[ "${GLOBAL_EVENTS_FORMAT}" != "ndjson" ]]; then
    printf 'unsupported --events format: %s; supported format: ndjson\n' "${GLOBAL_EVENTS_FORMAT}" >&2
    exit 2
  fi
  exec 3>&1
  export PK3S_OPERATION_EVENTS_FD=3
  exec 1>&2
}

emit_operation_event() {
  operation_events_enabled || return 0
  local operation="$1"
  local step="$2"
  local status="$3"
  local message="${4:-}"
  local subject="${5:-}"
  local fd="${PK3S_OPERATION_EVENTS_FD:-1}"
  printf '{"schema_version":"productive-k3s-operation-event/v1","component":"core","operation":"%s","step":"%s","status":"%s","message":"%s","subject":"%s","emitted_at":"%s"}\n' \
    "$(json_escape "${operation}")" \
    "$(json_escape "${step}")" \
    "$(json_escape "${status}")" \
    "$(json_escape "${message}")" \
    "$(json_escape "${subject}")" \
    "$(json_escape "$(date -Iseconds)")" >&"${fd}"
}

emit_operation_completed_event() {
  local operation="$1"
  local rc="$2"
  local subject="${3:-}"
  if (( rc == 0 )); then
    emit_operation_event "${operation}" "operation.completed" "success" "Operation completed" "${subject}"
  else
    emit_operation_event "${operation}" "operation.completed" "failed" "Operation failed with exit code ${rc}" "${subject}"
  fi
}

operation_name_for_args() {
  local command="${1:-apply}"
  local subcommand="${2:-}"
  case "${command}" in
    addon)
      printf 'addon.%s\n' "${subcommand:-unknown}"
      ;;
    stack)
      printf 'stack.%s\n' "${subcommand:-unknown}"
      ;;
    dev)
      printf 'dev.%s.%s\n' "${subcommand:-unknown}" "${3:-unknown}"
      ;;
    -*)
      printf 'core.apply\n'
      ;;
    *)
      printf 'core.%s\n' "${command}"
      ;;
  esac
}

events_exit_trap() {
  local rc=$?
  if operation_events_enabled && [[ "${OPERATION_COMPLETED_EMITTED:-0}" -ne 1 && -n "${OPERATION_NAME:-}" ]]; then
    emit_operation_completed_event "${OPERATION_NAME}" "${rc}" "${OPERATION_SUBJECT:-}"
  fi
}

write_generic_telemetry_event() {
  local event_name="$1"
  local command_name="$2"
  local result="$3"
  local event_file
  local telemetry_session_id
  local telemetry_run_id
  local telemetry_enabled

  telemetry_session_id="${TELEMETRY_SESSION_ID:-$(generate_telemetry_id)}"
  telemetry_run_id="${TELEMETRY_RUN_ID:-$(generate_telemetry_id)}"
  telemetry_enabled="${TELEMETRY_ENABLED:-false}"
  export TELEMETRY_SESSION_ID="${telemetry_session_id}"
  export TELEMETRY_RUN_ID="${telemetry_run_id}"

  event_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "event_family": "usage",\n'
    printf '  "event_name": "%s",\n' "$(json_escape "${event_name}")"
    printf '  "sent_at": "%s",\n' "$(json_escape "$(date -Iseconds)")"
    printf '  "session_id": "%s",\n' "$(json_escape "${telemetry_session_id}")"
    printf '  "run_id": "%s",\n' "$(json_escape "${telemetry_run_id}")"
    printf '  "parent_run_id": "%s",\n' "$(json_escape "${TELEMETRY_PARENT_RUN_ID:-}")"
    printf '  "component": "core",\n'
    printf '  "command": {\n'
    printf '    "name": "%s",\n' "$(json_escape "${command_name}")"
    printf '    "result": "%s"\n' "$(json_escape "${result}")"
    printf '  },\n'
    printf '  "client": {\n'
    printf '    "repository": "productive-k3s-core",\n'
    printf '    "script": "scripts/productive-k3s-core.sh",\n'
    printf '    "telemetry_enabled": "%s"\n' "$(json_escape "${telemetry_enabled}")"
    printf '  },\n'
    printf '  "telemetry_meta": {\n'
    printf '    "delivery_mode": "best-effort",\n'
    printf '    "anonymous_by_contract": true\n'
    printf '  }\n'
    printf '}\n'
  } > "${event_file}"

  TELEMETRY_RUN_ID="${telemetry_run_id}" TELEMETRY_MARKER="${TELEMETRY_MARKER:-}" bash "${TELEMETRY_EVENT_SENDER}" "${event_file}" >/dev/null 2>&1 || true
  rm -f "${event_file}"
}

prepare_telemetry_context() {
  resolve_telemetry_enabled
  export TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-$(generate_telemetry_id)}"
  export TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID:-$(generate_telemetry_id)}"
  export TELEMETRY_COMPONENT="core"
}

core_command_emits_telemetry() {
  local command="${1:-}"
  shift || true
  case "${command}" in
    apply)
      return 0
      ;;
    addon)
      [[ "${1:-}" == "install" ]]
      return
      ;;
    stack)
      [[ "${1:-}" == "install" || "${1:-}" == "cleanup" ]]
      return
      ;;
    -*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_preflight() {
  emit_operation_event "core.preflight" "core.preflight.run" "running" "Running host preflight"
  "${SCRIPT_DIR}/preflight-host.sh" "$@" || {
    local rc=$?
    emit_operation_event "core.preflight" "core.preflight.run" "failed" "Host preflight failed"
    return "${rc}"
  }
  emit_operation_event "core.preflight" "core.preflight.run" "success" "Host preflight completed"
}

run_apply() {
  local parent_run_id="${TELEMETRY_RUN_ID:-}"
  emit_operation_event "core.apply" "core.apply.run" "running" "Running Productive K3S core apply"
  TELEMETRY_PARENT_RUN_ID="${parent_run_id}" TELEMETRY_RUN_ID="" TELEMETRY_COMPONENT="core" "${SCRIPT_DIR}/apply.sh" "$@" || {
    local rc=$?
    emit_operation_event "core.apply" "core.apply.run" "failed" "Productive K3S core apply failed"
    return "${rc}"
  }
  emit_operation_event "core.apply" "core.apply.run" "success" "Productive K3S core apply completed"
}

run_backup() {
  emit_operation_event "core.backup" "core.backup.run" "running" "Running Productive K3S backup"
  "${SCRIPT_DIR}/backup.sh" "$@" || {
    local rc=$?
    emit_operation_event "core.backup" "core.backup.run" "failed" "Productive K3S backup failed"
    return "${rc}"
  }
  emit_operation_event "core.backup" "core.backup.run" "success" "Productive K3S backup completed"
}

run_cleanup() {
  emit_operation_event "core.cleanup" "core.cleanup.run" "running" "Running Productive K3S cleanup"
  "${SCRIPT_DIR}/cleanup.sh" "$@" || {
    local rc=$?
    emit_operation_event "core.cleanup" "core.cleanup.run" "failed" "Productive K3S cleanup failed"
    return "${rc}"
  }
  emit_operation_event "core.cleanup" "core.cleanup.run" "success" "Productive K3S cleanup completed"
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

resolve_current_core_version() {
  local version
  if [[ -f "$BUNDLE_INFO_PATH" ]]; then
    version="$(sed -n 's/.*"bundle_version": "\(.*\)".*/\1/p' "$BUNDLE_INFO_PATH" | head -n1)"
    if [[ -n "${version}" ]]; then
      printf '%s\n' "${version}"
      return 0
    fi
  fi

  resolve_bundle_version_fallback
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

print_bom_json() {
  local bundle_json version
  bundle_json="$(print_bundle_info_json)"
  version="$(printf '%s\n' "${bundle_json}" | sed -n 's/.*"bundle_version": "\(.*\)".*/\1/p' | head -n1)"
  cat <<EOF
{
  "schema_version": "1",
  "bom_type": "productive-k3s-cli-bom/v1",
  "cli": {
    "name": "productive-k3s-core",
    "version": "${version}",
    "entrypoint": "productive-k3s-core.sh"
  },
  "implementation": {
    "language": "bash",
    "bash_version": "$(json_escape "${BASH_VERSION:-unknown}")"
  },
  "bundle": ${bundle_json},
  "platform_support": {
    "host_os": ["ubuntu-24.04", "ubuntu-22.04", "debian-13", "debian-12"],
    "architectures": ["amd64", "arm64"],
    "supported_matrix": [
      {"os": "ubuntu-24.04", "architectures": ["amd64", "arm64"]},
      {"os": "ubuntu-22.04", "architectures": ["amd64"]},
      {"os": "debian-13", "architectures": ["amd64"]},
      {"os": "debian-12", "architectures": ["amd64"]}
    ],
    "retained_validation_evidence": {
      "amd64": ["ubuntu-24.04", "ubuntu-22.04", "debian-13", "debian-12"],
      "arm64": ["ubuntu-24.04"]
    }
  },
  "requirements": {
    "required_commands": [
      {"name": "bash", "min_version": "5.1", "reason": "public CLI and bootstrap runtime on supported Linux targets"},
      {"name": "sudo", "min_version": "1.9", "reason": "host package installation, systemd control, and filesystem changes"},
      {"name": "curl", "min_version": "7.81", "reason": "downloads k3s, Helm, release artifacts, and manifests"},
      {"name": "getent", "min_version": "glibc-2.35", "reason": "host user and group lookups during bootstrap"},
      {"name": "tar", "min_version": "1.34", "reason": "release bundle extraction and staging flows"},
      {"name": "sha256sum", "min_version": "8.32", "reason": "artifact checksum verification"},
      {"name": "mktemp", "min_version": "8.32", "reason": "safe temporary workspace creation"}
    ],
    "optional_commands": [
      {"name": "docker", "min_version": "20.10", "reason": "local registry trust checks and image-push workflows"},
      {"name": "multipass", "min_version": "1.14", "reason": "repository live validation on supported Linux VMs"},
      {"name": "jq", "min_version": "1.6", "reason": "operator inspection and selected bootstrap checks"},
      {"name": "kubectl", "min_version": "1.35.5", "reason": "standalone client convenience outside sudo k3s kubectl"},
      {"name": "helm", "min_version": "${PRODUCTIVE_K3S_HELM_VERSION#v}", "reason": "preinstalled Helm convenience; managed bootstrap pins the same version"}
    ]
  },
  "components": {
    "managed": ["k3s", "helm", "cert-manager", "longhorn", "rancher", "registry", "nfs", "local-hosts", "docker-registry-trust"],
    "bootstrap_modes": ["single-node", "server", "agent", "stack"],
    "versions": {
      "k3s": "$(json_escape "${PRODUCTIVE_K3S_K3S_VERSION}")",
      "helm": "$(json_escape "${PRODUCTIVE_K3S_HELM_VERSION}")",
      "cert-manager": "$(json_escape "${PRODUCTIVE_K3S_CERT_MANAGER_VERSION}")",
      "longhorn": "$(json_escape "${PRODUCTIVE_K3S_LONGHORN_VERSION}")",
      "rancher": "$(json_escape "${PRODUCTIVE_K3S_RANCHER_VERSION}")",
      "registry_image": "$(json_escape "${PRODUCTIVE_K3S_REGISTRY_IMAGE}")"
    },
    "version_policy": {
      "k3s": "pinned",
      "helm": "pinned",
      "cert-manager": "pinned",
      "longhorn": "pinned",
      "rancher": "pinned",
      "registry": "pinned-image",
      "nfs": "host-package-managed"
    }
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
    section == "spec" && /^  productiveK3s:/ { subsection="productiveK3s"; exposure=""; service=""; next }
    section == "spec" && subsection == "productiveK3s" && /^    exposure:/ { exposure="exposure"; service=""; next }
    section == "spec" && subsection == "productiveK3s" && exposure == "exposure" && /^      public:/ { exposure="public"; service=""; next }
    section == "spec" && subsection == "productiveK3s" && exposure == "public" && key == "spec.productiveK3s.exposure.public.mode" && /^        mode:/ { print; exit }
    section == "spec" && subsection == "productiveK3s" && exposure == "public" && key == "spec.productiveK3s.exposure.public.namespace" && /^        namespace:/ { print; exit }
    section == "spec" && subsection == "productiveK3s" && exposure == "public" && /^        service:/ { service="service"; next }
    section == "spec" && subsection == "productiveK3s" && exposure == "public" && service == "service" && key == "spec.productiveK3s.exposure.public.service.name" && /^          name:/ { print; exit }
    section == "spec" && subsection == "productiveK3s" && exposure == "public" && service == "service" && key == "spec.productiveK3s.exposure.public.service.port" && /^          port:/ { print; exit }
    section == "metadata" && key == "metadata.name" && /^  name:/ { print; exit }
    section == "metadata" && key == "metadata.version" && /^  version:/ { print; exit }
    section == "spec" && key == "spec.type" && /^  type:/ { print; exit }
    section == "spec" && subsection == "install" && key == "spec.install.script" && /^    script:/ { print; exit }
  ' "${file}"
}

stack_yaml_get() {
  local file="$1"
  local key="$2"
  awk -v key="${key}" '
    /^metadata:/ { section="metadata"; subsection=""; next }
    /^spec:/ { section="spec"; subsection=""; next }
    section == "spec" && /^  addons:/ { subsection="addons"; next }
    section == "spec" && /^  resolution:/ { subsection="resolution"; next }
    section == "spec" && /^  runtime:/ { subsection="runtime"; runtime_subsection=""; compatibility_subsection=""; next }
    section == "spec" && subsection == "runtime" && /^    compatibility:/ { runtime_subsection="compatibility"; compatibility_subsection=""; next }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && /^      core:/ { compatibility_subsection="core"; next }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && /^      kubernetes:/ { compatibility_subsection="kubernetes"; next }
    section == "metadata" && key == "metadata.name" && /^  name:/ { print; exit }
    section == "metadata" && key == "metadata.version" && /^  version:/ { print; exit }
    section == "spec" && subsection == "resolution" && key == "spec.resolution.mode" && /^    mode:/ { print; exit }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && compatibility_subsection == "core" && key == "spec.runtime.compatibility.core.minVersion" && /^        minVersion:/ { print; exit }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && compatibility_subsection == "kubernetes" && key == "spec.runtime.compatibility.kubernetes.minVersion" && /^        minVersion:/ { print; exit }
  ' "${file}"
}

stack_yaml_list() {
  local file="$1"
  local key="$2"
  awk -v key="${key}" '
    /^spec:/ { section="spec"; subsection=""; runtime_subsection=""; compatibility_subsection=""; kubernetes_subsection=""; next }
    section == "spec" && /^  runtime:/ { subsection="runtime"; runtime_subsection=""; compatibility_subsection=""; kubernetes_subsection=""; next }
    section == "spec" && subsection == "runtime" && /^    compatibility:/ { runtime_subsection="compatibility"; compatibility_subsection=""; kubernetes_subsection=""; next }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && /^      kubernetes:/ { compatibility_subsection="kubernetes"; kubernetes_subsection=""; next }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && compatibility_subsection == "kubernetes" && /^        distros:/ { kubernetes_subsection="distros"; next }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && compatibility_subsection == "kubernetes" && kubernetes_subsection == "distros" && key == "spec.runtime.compatibility.kubernetes.distros" && /^          - / {
      line=$0
      sub(/^          - /, "", line)
      print line
      next
    }
    section == "spec" && subsection == "runtime" && runtime_subsection == "compatibility" && compatibility_subsection == "kubernetes" && kubernetes_subsection == "distros" && !/^          - / { exit }
  ' "${file}"
}

stack_manifest_addon_records() {
  local manifest="$1"
  awk '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  addons:/ { in_addons=1; next }
    in_addons && /^  / && !/^    / { exit }
    !in_addons { next }
    /^    - / {
      flush_record()
      line=$0
      sub(/^    - /, "", line)
      current_name=""
      current_version=""
      current_source=""
      if (line ~ /^name:[[:space:]]*/) {
        sub(/^name:[[:space:]]*/, "", line)
        current_name=line
      } else if (line !~ /:/) {
        current_name=line
      }
      in_record=1
      next
    }
    in_record && /^      / {
      line=$0
      sub(/^      /, "", line)
      if (line ~ /^name:[[:space:]]*/) {
        sub(/^name:[[:space:]]*/, "", line)
        current_name=line
      } else if (line ~ /^version:[[:space:]]*/) {
        sub(/^version:[[:space:]]*/, "", line)
        current_version=line
      } else if (line ~ /^source:[[:space:]]*/) {
        sub(/^source:[[:space:]]*/, "", line)
        current_source=line
      }
      next
    }
    in_record { flush_record(); in_record=0 }
    END { flush_record() }
    function flush_record() {
      if (!in_record) {
        return
      }
      if (current_name != "" || current_version != "" || current_source != "") {
        printf "name=%s\tversion=%s\tsource=%s\n", current_name, current_version, current_source
      }
    }
  ' "${manifest}"
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

resolve_stack_manifest() {
  local package_root="$1"
  local manifest
  manifest="$(find "${package_root}" -type f -name 'stack.yaml' | head -n1)"
  [[ -n "${manifest}" ]] || {
    printf 'stack source is missing stack.yaml\n' >&2
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

validate_stack_manifest() {
  local manifest="$1"
  local stack_name stack_version resolution_mode addon_count=0
  local core_min_version kubernetes_min_version compatible_distros compatible_distro
  local seen_addon_names="" has_structured_source="n"
  stack_name="$(trim_yaml_value "$(stack_yaml_get "${manifest}" "metadata.name")")"
  stack_version="$(trim_yaml_value "$(stack_yaml_get "${manifest}" "metadata.version")")"
  resolution_mode="$(trim_yaml_value "$(stack_yaml_get "${manifest}" "spec.resolution.mode")")"
  core_min_version="$(trim_yaml_value "$(stack_yaml_get "${manifest}" "spec.runtime.compatibility.core.minVersion")")"
  kubernetes_min_version="$(trim_yaml_value "$(stack_yaml_get "${manifest}" "spec.runtime.compatibility.kubernetes.minVersion")")"

  [[ -n "${stack_name}" ]] || {
    printf 'stack source metadata.name is required\n' >&2
    return 4
  }
  [[ -n "${stack_version}" ]] || {
    printf 'stack source metadata.version is required\n' >&2
    return 4
  }
  if [[ -n "${resolution_mode}" && "${resolution_mode}" != "catalog" && "${resolution_mode}" != "bundled" ]]; then
    printf 'stack source spec.resolution.mode must be either catalog or bundled\n' >&2
    return 4
  fi
  while IFS= read -r addon_record; do
    [[ -n "${addon_record}" ]] || continue
    local addon_name addon_source
    addon_name="$(printf '%s\n' "${addon_record}" | awk -F '\t' '
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^name=/) {
            sub(/^name=/, "", $i)
            print $i
            exit
          }
        }
      }
    ')"
    [[ -n "${addon_name}" ]] || {
      printf 'stack source addon entries require a name\n' >&2
      return 4
    }
    if printf '%s\n' "${seen_addon_names}" | grep -Fxq "${addon_name}"; then
      printf 'stack source addon entries must be unique: %s\n' "${addon_name}" >&2
      return 4
    fi
    seen_addon_names+="${addon_name}"$'\n'
    addon_source="$(printf '%s\n' "${addon_record}" | awk -F '\t' '
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^source=/) {
            sub(/^source=/, "", $i)
            print $i
            exit
          }
        }
      }
    ')"
    if [[ -n "${addon_source}" ]]; then
      has_structured_source="y"
      [[ "${addon_source}" == addons/*.tgz ]] || {
        printf 'stack addon source must stay within addons/ and point to a .tgz: %s\n' "${addon_source}" >&2
        return 4
      }
    fi
    addon_count=$((addon_count + 1))
  done < <(stack_manifest_addon_records "${manifest}")
  (( addon_count > 0 )) || {
    printf 'stack source spec.addons must include at least one addon\n' >&2
    return 4
  }
  if [[ "${resolution_mode}" == "bundled" && "${has_structured_source}" != "y" ]]; then
    printf 'stack source spec.resolution.mode=bundled requires at least one addon source under addons/\n' >&2
    return 4
  fi

  compatible_distros="$(stack_yaml_list "${manifest}" "spec.runtime.compatibility.kubernetes.distros" || true)"
  if [[ -n "${compatible_distros}" ]]; then
    local seen_distros=""
    while IFS= read -r compatible_distro; do
      [[ -n "${compatible_distro}" ]] || continue
      case "${compatible_distro}" in
        k3s|rke2) ;;
        *)
          printf 'stack source runtime compatibility distro is not supported: %s\n' "${compatible_distro}" >&2
          return 4
          ;;
      esac
      if printf '%s\n' "${seen_distros}" | grep -Fxq "${compatible_distro}"; then
        printf 'stack source runtime compatibility distros must be unique: %s\n' "${compatible_distro}" >&2
        return 4
      fi
      seen_distros+="${compatible_distro}"$'\n'
    done <<< "${compatible_distros}"
  fi

  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "${stack_name}" \
    "${stack_version}" \
    "${addon_count}" \
    "${resolution_mode}" \
    "${core_min_version}" \
    "${kubernetes_min_version}" \
    "${compatible_distros}"
}

validate_stack_bundled_sources() {
  local manifest="$1"
  local package_root="$2"
  while IFS= read -r addon_record; do
    [[ -n "${addon_record}" ]] || continue
    local addon_source
    addon_source="$(printf '%s\n' "${addon_record}" | awk -F '\t' '
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^source=/) {
            sub(/^source=/, "", $i)
            print $i
            exit
          }
        }
      }
    ')"
    [[ -n "${addon_source}" ]] || continue
    [[ "${addon_source}" == addons/* ]] || {
      printf 'stack addon source must stay within addons/: %s\n' "${addon_source}" >&2
      return 4
    }
    [[ -f "${package_root}/${addon_source}" ]] || {
      printf 'Bundled addon package not found: %s\n' "${addon_source}" >&2
      return 4
    }
  done < <(stack_manifest_addon_records "${manifest}")
}

normalize_semver() {
  local version="${1#v}"
  printf '%s\n' "${version}"
}

semver_is_comparable() {
  local version
  version="$(normalize_semver "${1:-}")"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
}

semver_gte() {
  local left right
  left="$(normalize_semver "${1:-}")"
  right="$(normalize_semver "${2:-}")"
  [[ "$(printf '%s\n%s\n' "${right}" "${left}" | sort -V | head -n1)" == "${right}" ]]
}

stack_runtime_compatible_distro_list() {
  local manifest="$1"
  stack_yaml_list "${manifest}" "spec.runtime.compatibility.kubernetes.distros" || true
}

enforce_stack_runtime_compatibility() {
  local manifest="$1"
  local current_distro required_core_min_version current_core_version allowed_distro compatible_distro_list

  compatible_distro_list="$(stack_runtime_compatible_distro_list "${manifest}")"
  current_distro="${PRODUCTIVE_K3S_DISTRO:-k3s}"
  if [[ -n "${compatible_distro_list}" ]]; then
    local distro_allowed="n"
    while IFS= read -r allowed_distro; do
      [[ -n "${allowed_distro}" ]] || continue
      if [[ "${allowed_distro}" == "${current_distro}" ]]; then
        distro_allowed="y"
        break
      fi
    done <<< "${compatible_distro_list}"
    if [[ "${distro_allowed}" != "y" ]]; then
      printf 'stack runtime compatibility does not support distro %s (allowed: %s)\n' \
        "${current_distro}" \
        "$(printf '%s' "${compatible_distro_list}" | paste -sd ', ' -)" >&2
      return 4
    fi
  fi

  required_core_min_version="$(trim_yaml_value "$(stack_yaml_get "${manifest}" "spec.runtime.compatibility.core.minVersion")")"
  [[ -n "${required_core_min_version}" ]] || return 0

  current_core_version="$(resolve_current_core_version || true)"
  if ! semver_is_comparable "${required_core_min_version}"; then
    printf 'stack runtime compatibility core.minVersion is not comparable: %s\n' "${required_core_min_version}" >&2
    return 4
  fi
  if ! semver_is_comparable "${current_core_version}"; then
    printf 'warning: skipping stack core version compatibility check because current productive-k3s-core version is not semver-like: %s\n' "${current_core_version:-unknown}" >&2
    return 0
  fi
  if ! semver_gte "${current_core_version}" "${required_core_min_version}"; then
    printf 'stack runtime compatibility requires productive-k3s-core >= %s (current: %s)\n' \
      "${required_core_min_version}" \
      "${current_core_version}" >&2
    return 4
  fi
}

resolve_addon_public_ingress_support() {
  local manifest="$1"
  local mode namespace service_name service_port
  mode="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "spec.productiveK3s.exposure.public.mode")")"
  namespace="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "spec.productiveK3s.exposure.public.namespace")")"
  service_name="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "spec.productiveK3s.exposure.public.service.name")")"
  service_port="$(trim_yaml_value "$(addon_yaml_get "${manifest}" "spec.productiveK3s.exposure.public.service.port")")"
  printf '%s\n%s\n%s\n%s\n' "${mode}" "${namespace}" "${service_name}" "${service_port}"
}

is_valid_public_host() {
  local host="${1:-}"
  [[ -n "${host}" && "${host}" != *" "* && "${host}" == *.* && "${host}" =~ ^[A-Za-z0-9.-]+$ ]]
}

apply_addon_public_ingress() {
  local manifest="$1"
  local addon_name="$2"
  local kubeconfig_path="$3"
  local public_host="$4"
  local ingress_metadata mode namespace service_name service_port ingress_name existing

  is_valid_public_host "${public_host}" || {
    printf 'invalid public host: %s\n' "${public_host}" >&2
    return 4
  }
  ingress_metadata="$(resolve_addon_public_ingress_support "${manifest}")"
  mode="$(printf '%s\n' "${ingress_metadata}" | sed -n '1p')"
  namespace="$(printf '%s\n' "${ingress_metadata}" | sed -n '2p')"
  service_name="$(printf '%s\n' "${ingress_metadata}" | sed -n '3p')"
  service_port="$(printf '%s\n' "${ingress_metadata}" | sed -n '4p')"
  [[ "${mode}" == "ingress" && -n "${namespace}" && -n "${service_name}" && -n "${service_port}" ]] || {
    printf 'addon package does not declare basic public ingress exposure support\n' >&2
    return 4
  }
  command -v kubectl >/dev/null 2>&1 || {
    printf 'kubectl is required to publish addon ingresses\n' >&2
    return 4
  }

  ingress_name="${addon_name}-public"
  existing="$(
    kubectl --kubeconfig "${kubeconfig_path}" get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' 2>/dev/null || true
  )"
  while IFS='|' read -r existing_namespace existing_name existing_host; do
    [[ -n "${existing_host}" ]] || continue
    if [[ "${existing_host}" == "${public_host}" && ! ( "${existing_namespace}" == "${namespace}" && "${existing_name}" == "${ingress_name}" ) ]]; then
      printf 'public host is already in use by another ingress: %s\n' "${public_host}" >&2
      return 4
    fi
  done <<< "${existing}"

  kubectl --kubeconfig "${kubeconfig_path}" apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${ingress_name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/managed-by: productive-k3s-core
    addons.productive-k3s.io/name: ${addon_name}
spec:
  ingressClassName: ${PK3S_INGRESS_CLASS_NAME:-$(pk3s_runtime_default_ingress_class)}
  rules:
    - host: ${public_host}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${service_name}
                port:
                  number: ${service_port}
EOF
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
  emit_operation_event "addon.validate" "addon.package.extract" "running" "Extracting add-on package" "${tgz_path}"
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")" || {
    local rc=$?
    emit_operation_event "addon.validate" "addon.package.extract" "failed" "Could not extract add-on package" "${tgz_path}"
    return "${rc}"
  }
  emit_operation_event "addon.validate" "addon.package.extract" "success" "Add-on package extracted" "${tgz_path}"
  emit_operation_event "addon.validate" "addon.manifest.resolve" "running" "Resolving add-on manifest" "${tgz_path}"
  manifest="$(resolve_addon_manifest "${tmp_dir}")" || {
    local rc=$?
    emit_operation_event "addon.validate" "addon.manifest.resolve" "failed" "Add-on manifest could not be resolved" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  emit_operation_event "addon.validate" "addon.manifest.resolve" "success" "Add-on manifest resolved" "${tgz_path}"
  emit_operation_event "addon.validate" "addon.package.validate" "running" "Validating add-on package metadata" "${tgz_path}"
  metadata="$(validate_addon_manifest "${manifest}")" || {
    local rc=$?
    emit_operation_event "addon.validate" "addon.package.validate" "failed" "Add-on package validation failed" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  addon_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  addon_type="$(printf '%s\n' "${metadata}" | sed -n '2p')"
  install_script="$(printf '%s\n' "${metadata}" | sed -n '3p')"
  OPERATION_SUBJECT="${addon_name}"

  printf 'Addon package: %s\n' "${addon_name}"
  printf 'Addon type: %s\n' "${addon_type}"
  printf 'Install script: %s\n' "${install_script}"
  printf 'Addon package validation passed\n'
  emit_operation_event "addon.validate" "addon.package.validate" "success" "Add-on package validation passed" "${addon_name}"
  rm -rf "${tmp_dir}"
}

resolve_local_cluster_kubeconfig() {
  local system_kubeconfig_path="${PRODUCTIVE_K3S_SYSTEM_KUBECONFIG_PATH:-$(pk3s_runtime_system_kubeconfig_path)}"
  local distro_user_kubeconfig
  distro_user_kubeconfig="$(pk3s_runtime_default_user_kubeconfig_path)"
  local candidate
  for candidate in \
    "${KUBECONFIG:-}" \
    "${distro_user_kubeconfig}" \
    "${HOME}/.kube/config" \
    "${system_kubeconfig_path}"
  do
    [[ -n "${candidate}" && -r "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return 0
  done
  return 1
}

run_packaged_addon_install() {
  local tgz_path="$1"
  local public_host="${PK3S_ADDON_PUBLIC_HOST:-}"
  local target_kubeconfig=""
  local core_repo_dir tmp_root addon_name package_root
  emit_operation_event "addon.install" "addon.kubeconfig.resolve" "running" "Resolving target kubeconfig"
  target_kubeconfig="$(resolve_local_cluster_kubeconfig)" || {
    emit_operation_event "addon.install" "addon.kubeconfig.resolve" "failed" "Target kubeconfig could not be resolved"
    printf 'addon install could not find a readable local kubeconfig. Run apply first or set KUBECONFIG.\n' >&2
    return 4
  }
  emit_operation_event "addon.install" "addon.kubeconfig.resolve" "success" "Target kubeconfig resolved"

  local tmp_dir manifest metadata install_script manifest_dir install_path
  emit_operation_event "addon.install" "addon.package.extract" "running" "Extracting add-on package" "${tgz_path}"
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")" || {
    local rc=$?
    emit_operation_event "addon.install" "addon.package.extract" "failed" "Could not extract add-on package" "${tgz_path}"
    return "${rc}"
  }
  emit_operation_event "addon.install" "addon.package.extract" "success" "Add-on package extracted" "${tgz_path}"
  emit_operation_event "addon.install" "addon.manifest.resolve" "running" "Resolving add-on manifest" "${tgz_path}"
  manifest="$(resolve_addon_manifest "${tmp_dir}")" || {
    local rc=$?
    emit_operation_event "addon.install" "addon.manifest.resolve" "failed" "Add-on manifest could not be resolved" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  emit_operation_event "addon.install" "addon.manifest.resolve" "success" "Add-on manifest resolved" "${tgz_path}"
  emit_operation_event "addon.install" "addon.package.validate" "running" "Validating add-on package metadata" "${tgz_path}"
  metadata="$(validate_addon_manifest "${manifest}")" || {
    local rc=$?
    emit_operation_event "addon.install" "addon.package.validate" "failed" "Add-on package validation failed" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  addon_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  install_script="$(printf '%s\n' "${metadata}" | sed -n '3p')"
  OPERATION_SUBJECT="${addon_name}"
  emit_operation_event "addon.install" "addon.package.validate" "success" "Add-on package validation passed" "${addon_name}"
  core_repo_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
  tmp_root="$(mktemp -d)"
  package_root="${tmp_root}/addons/${addon_name}"
  mkdir -p "${package_root}" "${tmp_root}/scripts"
  cp -R "${tmp_dir}/." "${package_root}/"
  cp "${SCRIPT_DIR}/addon-host-runtime.sh" "${tmp_root}/scripts/addon-host-runtime.sh"
  manifest_dir="${package_root}"
  install_path="${manifest_dir}/${install_script}"
  [[ -f "${install_path}" ]] || {
    emit_operation_event "addon.install" "addon.install.script" "failed" "Add-on install script not found" "${addon_name}"
    rm -rf "${tmp_dir}" "${tmp_root}"
    printf 'addon package install script not found: %s\n' "${install_script}" >&2
    return 4
  }

  printf 'Executing packaged addon installer: %s\n' "${install_script}"
  emit_operation_event "addon.install" "addon.install.run" "running" "Executing packaged add-on installer" "${addon_name}"
  (
    cd "${manifest_dir}"
    export KUBECONFIG="${target_kubeconfig}"
    export PRODUCTIVE_K3S_CORE_REPO_DIR="${core_repo_dir}"
    export PK3S_KUBECTL_MODE="${PK3S_KUBECTL_MODE:-$(pk3s_runtime_addon_kubectl_mode)}"
    export PK3S_KUBECTL_BIN="${PK3S_KUBECTL_BIN:-$(pk3s_runtime_addon_kubectl_bin)}"
    export PK3S_INGRESS_CLASS_NAME="${PK3S_INGRESS_CLASS_NAME:-$(pk3s_runtime_default_ingress_class)}"
    bash "${install_path}"
  ) || {
    local rc=$?
    emit_operation_event "addon.install" "addon.install.run" "failed" "Packaged add-on installer failed" "${addon_name}"
    rm -rf "${tmp_dir}" "${tmp_root}"
    return "${rc}"
  }
  emit_operation_event "addon.install" "addon.install.run" "success" "Packaged add-on installer completed" "${addon_name}"
  local rc=$?
  if (( rc == 0 )) && [[ -n "${public_host}" ]]; then
    emit_operation_event "addon.install" "addon.public-ingress.apply" "running" "Applying add-on public ingress" "${addon_name}"
    apply_addon_public_ingress "${manifest}" "$(printf '%s\n' "${metadata}" | sed -n '1p')" "${target_kubeconfig}" "${public_host}" || rc=$?
    if (( rc == 0 )); then
      emit_operation_event "addon.install" "addon.public-ingress.apply" "success" "Add-on public ingress applied" "${addon_name}"
    else
      emit_operation_event "addon.install" "addon.public-ingress.apply" "failed" "Add-on public ingress failed" "${addon_name}"
    fi
  fi
  rm -rf "${tmp_dir}" "${tmp_root}"
  return "${rc}"
}

with_stack_source_env() {
  local repo_dir="$1"
  local stack_name="$2"
  shift 2
  (
    export PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo_dir}"
    export PRODUCTIVE_K3S_STACK_NAME="${stack_name}"
    "$@"
  )
}

create_overlay_repo_for_stack_manifest() {
  local manifest_path="$1"
  local overlay_root real_repo metadata stack_name
  real_repo="$(resolve_addons_repo_dir)" || {
    printf 'could not resolve productive-k3s-addons source repository. Set PRODUCTIVE_K3S_ADDONS_REPO_DIR.\n' >&2
    return 4
  }
  metadata="$(validate_stack_manifest "${manifest_path}")" || return $?
  stack_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"

  overlay_root="$(mktemp -d)"
  mkdir -p "${overlay_root}/stacks/${stack_name}"
  ln -s "${real_repo}/addons" "${overlay_root}/addons"
  cp "${manifest_path}" "${overlay_root}/stacks/${stack_name}/stack.yaml"

  printf '%s\n%s\n' "${overlay_root}" "${stack_name}"
}

create_overlay_repo_for_stack_tgz() {
  local tgz_path="$1"
  local tmp_dir manifest metadata stack_name overlay_root real_repo
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")" || return $?
  manifest="$(resolve_stack_manifest "${tmp_dir}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  metadata="$(validate_stack_manifest "${manifest}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  validate_stack_bundled_sources "${manifest}" "${tmp_dir}" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  stack_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  real_repo="$(resolve_addons_repo_dir || true)"
  overlay_root="$(mktemp -d)"
  mkdir -p "${overlay_root}/stacks/${stack_name}" "${overlay_root}/bundled-addons"
  if [[ -n "${real_repo}" ]]; then
    ln -s "${real_repo}/addons" "${overlay_root}/addons"
  else
    mkdir -p "${overlay_root}/addons"
  fi
  cp "${manifest}" "${overlay_root}/stacks/${stack_name}/stack.yaml"
  if [[ -d "${tmp_dir}/addons" ]]; then
    cp -R "${tmp_dir}/addons/." "${overlay_root}/bundled-addons/"
  fi
  rm -rf "${tmp_dir}"
  printf '%s\n%s\n' "${overlay_root}" "${stack_name}"
}

run_stack_install_from_overlay() {
  local overlay_repo="$1"
  local stack_name="$2"
  shift 2
  local manifest_path
  manifest_path="${overlay_repo}/stacks/${stack_name}/stack.yaml"
  emit_operation_event "stack.install" "stack.runtime.validate" "running" "Validating stack runtime compatibility" "${stack_name}"
  enforce_stack_runtime_compatibility "${manifest_path}" || return $?
  emit_operation_event "stack.install" "stack.runtime.validate" "success" "Stack runtime compatibility validated" "${stack_name}"
  emit_operation_event "stack.install" "stack.install.run" "running" "Running stack install" "${stack_name}"
  (
    export PRODUCTIVE_K3S_ADDONS_REPO_DIR="${overlay_repo}"
    export PRODUCTIVE_K3S_STACK_NAME="${stack_name}"
    export PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${overlay_repo}/bundled-addons"
    "${SCRIPT_DIR}/apply.sh" --mode stack "$@"
  ) || {
    local rc=$?
    emit_operation_event "stack.install" "stack.install.run" "failed" "Stack install failed" "${stack_name}"
    return "${rc}"
  }
  emit_operation_event "stack.install" "stack.install.run" "success" "Stack install completed" "${stack_name}"
}

materialize_export_output() {
  local stage_dir="$1"
  local output_path="$2"
  local output_parent output_base

  [[ -n "${output_path}" ]] || {
    printf 'missing output path for export\n' >&2
    return 2
  }
  [[ ! -e "${output_path}" ]] || {
    printf 'export output already exists: %s\n' "${output_path}" >&2
    return 2
  }

  case "${output_path}" in
    *.tgz|*.tar.gz)
      output_parent="$(dirname "${output_path}")"
      mkdir -p "${output_parent}"
      output_base="$(basename "${output_path}")"
      tar -czf "${output_path}" -C "$(dirname "${stage_dir}")" "$(basename "${stage_dir}")"
      ;;
    *)
      mkdir -p "${output_path}"
      cp -R "${stage_dir}/." "${output_path}/"
      ;;
  esac
}

run_stack_export_from_tgz() {
  local tgz_path="$1"
  local output_path="$2"
  shift 2
  local repo_root tmp_dir manifest metadata stack_name stage_root bundle_root rc=0

  repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
  emit_operation_event "stack.export" "stack.package.extract" "running" "Extracting stack package" "${tgz_path}"
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")" || {
    local rc=$?
    emit_operation_event "stack.export" "stack.package.extract" "failed" "Could not extract stack package" "${tgz_path}"
    return "${rc}"
  }
  emit_operation_event "stack.export" "stack.package.extract" "success" "Stack package extracted" "${tgz_path}"
  emit_operation_event "stack.export" "stack.manifest.resolve" "running" "Resolving stack manifest" "${tgz_path}"
  manifest="$(resolve_stack_manifest "${tmp_dir}")" || {
    rc=$?
    emit_operation_event "stack.export" "stack.manifest.resolve" "failed" "Stack manifest could not be resolved" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  emit_operation_event "stack.export" "stack.manifest.resolve" "success" "Stack manifest resolved" "${tgz_path}"
  emit_operation_event "stack.export" "stack.package.validate" "running" "Validating stack package metadata" "${tgz_path}"
  metadata="$(validate_stack_manifest "${manifest}")" || {
    rc=$?
    emit_operation_event "stack.export" "stack.package.validate" "failed" "Stack package validation failed" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  validate_stack_bundled_sources "${manifest}" "${tmp_dir}" || {
    rc=$?
    emit_operation_event "stack.export" "stack.package.validate" "failed" "Stack bundled sources validation failed" "${tgz_path}"
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  stack_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  emit_operation_event "stack.export" "stack.package.validate" "success" "Stack package validation passed" "${stack_name}"

  stage_root="$(mktemp -d)"
  bundle_root="${stage_root}/stack-export-${stack_name}"

  emit_operation_event "stack.export" "stack.export.materialize" "running" "Materializing stack export" "${stack_name}"
  mkdir -p "${bundle_root}"
  export_runtime_init
  export_runtime_set_metadata "command" "stack export"
  export_runtime_set_metadata "subject_kind" "stack"
  export_runtime_set_metadata "subject_ref" "${stack_name}"
  export_runtime_set_metadata "artifact_name" "stack.tgz"
  export_runtime_set_metadata "interactive" "$(can_use_tty && printf true || printf false)"
  export_runtime_set_metadata "telemetry_enabled" "${TELEMETRY_ENABLED:-}"
  export_runtime_add_env "PRODUCTIVE_K3S_DISTRO" "${PRODUCTIVE_K3S_DISTRO:-k3s}"
  export_runtime_add_env "PRODUCTIVE_K3S_ENGINE" "${PRODUCTIVE_K3S_ENGINE:-native}"
  if [[ -n "${TELEMETRY_ENABLED:-}" ]]; then
    export_runtime_add_env "TELEMETRY_ENABLED" "${TELEMETRY_ENABLED}"
  fi

  export_runtime_copy_core_runtime "${repo_root}" "${bundle_root}"
  cp "${tgz_path}" "${bundle_root}/stack.tgz"
  export_runtime_write_install_config "${bundle_root}/install-config.env"
  export_runtime_write_manifest "${bundle_root}/manifest.json"
  export_runtime_write_stack_preflight_script "${bundle_root}/preflight.sh" "stack.tgz"
  export_runtime_write_readme "${bundle_root}/README.md" "${stack_name}" "stack.tgz"
  export_runtime_write_stack_agents_md "${bundle_root}/AGENTS.md" "${stack_name}" "stack.tgz"
  export_runtime_write_stack_install_script "${bundle_root}/install.sh" "stack.tgz" "$@"
  materialize_export_output "${bundle_root}" "${output_path}" || rc=$?
  if (( rc == 0 )); then
    emit_operation_event "stack.export" "stack.export.materialize" "success" "Stack export materialized" "${stack_name}"
  else
    emit_operation_event "stack.export" "stack.export.materialize" "failed" "Stack export materialization failed" "${stack_name}"
  fi

  rm -rf "${tmp_dir}" "${stage_root}"
  return "${rc}"
}

run_addon_install() {
  local tgz_path=""
  local public_host="${PK3S_ADDON_PUBLIC_HOST:-}"
  while (($# > 0)); do
    case "$1" in
      --tgz)
        tgz_path="${2:-}"
        shift 2
        ;;
      --public-host)
        public_host="${2:-}"
        shift 2
        ;;
      *)
        printf 'Usage: ./productive-k3s-core.sh addon install --tgz <file> [--public-host <fqdn>]\n' >&2
        printf 'source-name addon install is no longer part of the public core contract; package the addon as .tgz first.\n' >&2
        return 2
        ;;
    esac
  done

  if [[ -n "${tgz_path}" ]]; then
    PK3S_ADDON_PUBLIC_HOST="${public_host}" run_packaged_addon_install "${tgz_path}"
    return $?
  fi

  [[ -n "${tgz_path}" ]] || {
    printf 'Usage: ./productive-k3s-core.sh addon install --tgz <file> [--public-host <fqdn>]\n' >&2
    return 2
  }
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

run_dev_stack_validate() {
  local source_dir=""
  while (($# > 0)); do
    case "$1" in
      --source)
        source_dir="${2:-}"
        shift 2
        ;;
      *)
        printf 'Usage: ./productive-k3s-core.sh dev stack validate --source <dir>\n' >&2
        return 2
        ;;
    esac
  done
  [[ -n "${source_dir}" ]] || {
    printf 'Usage: ./productive-k3s-core.sh dev stack validate --source <dir>\n' >&2
    return 2
  }
  local manifest metadata stack_name stack_version addon_count resolution_mode core_min_version kubernetes_min_version compatible_distros compatible_distro_summary
  manifest="$(resolve_stack_manifest "${source_dir}")" || return $?
  metadata="$(validate_stack_manifest "${manifest}")" || return $?
  stack_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  stack_version="$(printf '%s\n' "${metadata}" | sed -n '2p')"
  addon_count="$(printf '%s\n' "${metadata}" | sed -n '3p')"
  resolution_mode="$(printf '%s\n' "${metadata}" | sed -n '4p')"
  core_min_version="$(printf '%s\n' "${metadata}" | sed -n '5p')"
  kubernetes_min_version="$(printf '%s\n' "${metadata}" | sed -n '6p')"
  compatible_distros="$(printf '%s\n' "${metadata}" | tail -n +7)"
  compatible_distro_summary="$(printf '%s' "${compatible_distros}" | paste -sd ', ' -)"
  printf 'Stack source: %s\n' "${stack_name}"
  printf 'Stack version: %s\n' "${stack_version}"
  printf 'Referenced addons: %s\n' "${addon_count}"
  printf 'Stack resolution mode: %s\n' "${resolution_mode:-catalog-or-legacy}"
  printf 'Minimum core version: %s\n' "${core_min_version:-none}"
  printf 'Minimum Kubernetes version: %s\n' "${kubernetes_min_version:-none}"
  printf 'Compatible distros: %s\n' "${compatible_distro_summary:-any}"
  printf 'Stack source validation passed\n'
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
      printf 'Usage: ./productive-k3s-core.sh addon <validate|install> [flags]\n' >&2
      return 2
      ;;
  esac
}

run_stack() {
  local action="${1:-}"
  shift || true
  local stack_name="" tgz_path=""
  case "${action}" in
    install)
      while (($# > 0)); do
        case "$1" in
          --tgz)
            tgz_path="${2:-}"
            shift 2
            ;;
          -*)
            break
            ;;
          *)
            if [[ -z "${stack_name}" ]]; then
              stack_name="$1"
              shift
            else
              break
            fi
            ;;
        esac
      done

      if [[ -n "${tgz_path}" ]]; then
        local overlay_repo_tgz stack_name_tgz
        emit_operation_event "stack.install" "stack.overlay.prepare" "running" "Preparing stack overlay from package" "${tgz_path}"
        mapfile -t _stack_overlay < <(create_overlay_repo_for_stack_tgz "${tgz_path}") || return $?
        overlay_repo_tgz="${_stack_overlay[0]:-}"
        stack_name_tgz="${_stack_overlay[1]:-}"
        [[ -n "${overlay_repo_tgz}" && -n "${stack_name_tgz}" ]] || {
          emit_operation_event "stack.install" "stack.overlay.prepare" "failed" "Stack overlay preparation failed" "${tgz_path}"
          printf 'failed to build a temporary stack overlay for stack install\n' >&2
          return 4
        }
        emit_operation_event "stack.install" "stack.overlay.prepare" "success" "Stack overlay prepared" "${stack_name_tgz}"
        local rc=0
        run_stack_install_from_overlay "${overlay_repo_tgz}" "${stack_name_tgz}" "$@" || rc=$?
        rm -rf "${overlay_repo_tgz}"
        return "${rc}"
      fi

      [[ -n "${stack_name}" ]] || {
        printf 'Usage: ./productive-k3s-core.sh stack install <name> [apply args...]\n' >&2
        printf '   or: ./productive-k3s-core.sh stack install --tgz <file> [apply args...]\n' >&2
        return 2
      }
      emit_operation_event "stack.install" "stack.install.run" "running" "Running source stack install" "${stack_name}"
      with_stack_source_env "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-$(resolve_addons_repo_dir)}" "${stack_name}" "${SCRIPT_DIR}/apply.sh" --mode stack "$@" || {
        local rc=$?
        emit_operation_event "stack.install" "stack.install.run" "failed" "Source stack install failed" "${stack_name}"
        return "${rc}"
      }
      emit_operation_event "stack.install" "stack.install.run" "success" "Source stack install completed" "${stack_name}"
      ;;
    export)
      local output_path=""
      while (($# > 0)); do
        case "$1" in
          --tgz)
            tgz_path="${2:-}"
            shift 2
            ;;
          --output)
            output_path="${2:-}"
            shift 2
            ;;
          -*)
            break
            ;;
          *)
            if [[ -z "${stack_name}" ]]; then
              stack_name="$1"
              shift
            else
              break
            fi
            ;;
        esac
      done
      [[ -n "${output_path}" ]] || {
        printf 'Usage: ./productive-k3s-core.sh stack export --tgz <file> --output <dir|archive> [install args...]\n' >&2
        return 2
      }
      [[ -n "${tgz_path}" ]] || {
        printf 'Usage: ./productive-k3s-core.sh stack export --tgz <file> --output <dir|archive> [install args...]\n' >&2
        return 2
      }
      run_stack_export_from_tgz "${tgz_path}" "${output_path}" "$@"
      ;;
    validate)
      stack_name="${1:-}"
      [[ -n "${stack_name}" ]] || {
        printf 'Usage: ./productive-k3s-core.sh stack validate <name> [validate args...]\n' >&2
        return 2
      }
      shift
      emit_operation_event "stack.validate" "stack.validate.run" "running" "Running stack validation" "${stack_name}"
      with_stack_source_env "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-$(resolve_addons_repo_dir)}" "${stack_name}" "${SCRIPT_DIR}/validate.sh" "$@" || {
        local rc=$?
        emit_operation_event "stack.validate" "stack.validate.run" "failed" "Stack validation failed" "${stack_name}"
        return "${rc}"
      }
      emit_operation_event "stack.validate" "stack.validate.run" "success" "Stack validation completed" "${stack_name}"
      ;;
    backup)
      stack_name="${1:-}"
      [[ -n "${stack_name}" ]] || {
        printf 'Usage: ./productive-k3s-core.sh stack backup <name> [backup args...]\n' >&2
        return 2
      }
      shift
      emit_operation_event "stack.backup" "stack.backup.run" "running" "Running stack backup" "${stack_name}"
      with_stack_source_env "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-$(resolve_addons_repo_dir)}" "${stack_name}" "${SCRIPT_DIR}/backup.sh" "$@" || {
        local rc=$?
        emit_operation_event "stack.backup" "stack.backup.run" "failed" "Stack backup failed" "${stack_name}"
        return "${rc}"
      }
      emit_operation_event "stack.backup" "stack.backup.run" "success" "Stack backup completed" "${stack_name}"
      ;;
    cleanup)
      stack_name="${1:-}"
      [[ -n "${stack_name}" ]] || {
        printf 'Usage: ./productive-k3s-core.sh stack cleanup <name> [cleanup args...]\n' >&2
        return 2
      }
      shift
      emit_operation_event "stack.cleanup" "stack.cleanup.run" "running" "Running stack cleanup" "${stack_name}"
      with_stack_source_env "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-$(resolve_addons_repo_dir)}" "${stack_name}" "${SCRIPT_DIR}/cleanup.sh" "$@" || {
        local rc=$?
        emit_operation_event "stack.cleanup" "stack.cleanup.run" "failed" "Stack cleanup failed" "${stack_name}"
        return "${rc}"
      }
      emit_operation_event "stack.cleanup" "stack.cleanup.run" "success" "Stack cleanup completed" "${stack_name}"
      ;;
    *)
      printf 'Usage: ./productive-k3s-core.sh stack <install|export|validate|backup|cleanup> ...\n' >&2
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
    stack:validate)
      run_dev_stack_validate "$@"
      ;;
    *)
      printf 'Usage: ./productive-k3s-core.sh dev <addon|stack> validate --source <dir>\n' >&2
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

run_bom() {
  if (($# != 1)) || [[ "$1" != "--json" ]]; then
    printf 'Usage: ./productive-k3s-core.sh bom --json\n' >&2
    return 2
  fi
  print_bom_json
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

  emit_operation_event "core.validate" "core.validate.run" "running" "Running Productive K3S validation"
  "${SCRIPT_DIR}/validate.sh" "${translated_args[@]}" || {
    local rc=$?
    emit_operation_event "core.validate" "core.validate.run" "failed" "Productive K3S validation failed"
    return "${rc}"
  }
  emit_operation_event "core.validate" "core.validate.run" "success" "Productive K3S validation completed"
}

main() {
  local parsed_args=()
  local command="${1:-apply}"
  local rc=0

  while (($# > 0)); do
    case "$1" in
      --events)
        [[ $# -ge 2 ]] || {
          printf '%s\n' "--events requires a value" >&2
          return 2
        }
        GLOBAL_EVENTS_FORMAT="$2"
        shift 2
        ;;
      *)
        parsed_args+=("$1")
        shift
        ;;
    esac
  done
  set -- "${parsed_args[@]}"

  if (($# == 0)); then
    command="apply"
  else
    command="${1:-apply}"
  fi

  setup_operation_event_output
  OPERATION_NAME="$(operation_name_for_args "$@")"
  OPERATION_SUBJECT=""
  OPERATION_COMPLETED_EMITTED=0
  trap events_exit_trap EXIT
  emit_operation_event "${OPERATION_NAME}" "operation.started" "running" "Operation started" "${OPERATION_SUBJECT}"

  if core_command_emits_telemetry "${command}" "$@"; then
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
    bom)
      shift
      run_bom "$@"
      ;;
    preflight)
      shift
      run_preflight "$@" || rc=$?
      ;;
    apply)
      shift
      run_apply "$@" || rc=$?
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
    stack)
      shift
      run_stack "$@" || rc=$?
      ;;
    dev)
      shift
      run_dev "$@" || rc=$?
      ;;
    -*)
      command="apply"
      run_apply "$@" || rc=$?
      ;;
    *)
      printf 'Unsupported command: %s\n\n' "$command" >&2
      usage >&2
      exit 2
      ;;
  esac

  if core_command_emits_telemetry "${command}" "$@" && is_truthy "${TELEMETRY_ENABLED:-false}"; then
    if (( rc == 0 )); then
      write_generic_telemetry_event "core.command.completed" "${command}" "success"
    else
      write_generic_telemetry_event "core.command.completed" "${command}" "failed"
    fi
  fi

  emit_operation_completed_event "${OPERATION_NAME}" "${rc}" "${OPERATION_SUBJECT}"
  OPERATION_COMPLETED_EMITTED=1
  return "${rc}"
}

main "$@"
