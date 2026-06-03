#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/component-versions.sh"
BUNDLE_INFO_PATH="${SCRIPT_DIR}/../bundle-info.json"
TELEMETRY_EVENT_SENDER="${SCRIPT_DIR}/send-telemetry-event.sh"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"

usage() {
  cat <<'EOF'
Usage:
  ./productive-k3s-core.sh <command> [args...]
  ./productive-k3s-core.sh addon <validate|install> --tgz <file>
  ./productive-k3s-core.sh addon install --tgz <file> [--public-host <fqdn>] (--kubeconfig <file> | --cluster-context <name>)
  ./productive-k3s-core.sh dev addon validate --source <dir>
  ./productive-k3s-core.sh [bootstrap args...]

Operational commands:
  bundle      Show bundle metadata for automation
  bom         Show a JSON bill of materials for this CLI/runtime
  preflight   Run host compatibility checks before bootstrap
  bootstrap   Run the interactive bootstrap flow
  backup      Capture a host and cluster backup snapshot
  validate    Run the post-bootstrap validator
  addon       Validate or install packaged add-ons
  dev         Development-oriented source-based addon workflows
  help        Show this help

Examples:
  ./productive-k3s-core.sh bundle info --json
  ./productive-k3s-core.sh bom --json
  ./productive-k3s-core.sh preflight
  ./productive-k3s-core.sh preflight --strict
  ./productive-k3s-core.sh bootstrap --dry-run
  ./productive-k3s-core.sh validate --strict
  ./productive-k3s-core.sh addon validate --tgz ./longhorn-addon.tgz
  ./productive-k3s-core.sh addon install --tgz ./longhorn-addon.tgz --cluster-context default
  ./productive-k3s-core.sh addon install --tgz ./nginx-addon.tgz --public-host nginx-01.k3s.lab.internal --cluster-context default

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
    bootstrap)
      return 0
      ;;
    addon)
      [[ "${1:-}" == "install" ]]
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
  ingressClassName: traefik
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
  local kubeconfig_path="${KUBECONFIG:-}"
  local cluster_context="${PK3S_KUBE_CONTEXT:-}"
  local public_host="${PK3S_ADDON_PUBLIC_HOST:-}"
  while (($# > 0)); do
    case "$1" in
      --tgz)
        tgz_path="${2:-}"
        shift 2
        ;;
      --kubeconfig)
        kubeconfig_path="${2:-}"
        shift 2
        ;;
      --cluster-context)
        cluster_context="${2:-}"
        shift 2
        ;;
      --public-host)
        public_host="${2:-}"
        shift 2
        ;;
      *)
        printf 'Usage: ./productive-k3s-core.sh addon install --tgz <file> [--public-host <fqdn>] (--kubeconfig <file> | --cluster-context <name>)\n' >&2
        return 2
        ;;
    esac
  done
  [[ -n "${tgz_path}" ]] || {
    printf 'Usage: ./productive-k3s-core.sh addon install --tgz <file> [--public-host <fqdn>] (--kubeconfig <file> | --cluster-context <name>)\n' >&2
    return 2
  }
  [[ -n "${kubeconfig_path}" || -n "${cluster_context}" ]] || {
    printf 'addon install requires an explicit target; use --kubeconfig <file> or --cluster-context <name>\n' >&2
    return 2
  }

  local tmp_dir manifest metadata install_script manifest_dir install_path target_kubeconfig cleanup_kubeconfig=""
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
  if [[ -n "${cluster_context}" ]]; then
    local source_kubeconfig
    source_kubeconfig="${kubeconfig_path:-${KUBECONFIG:-${HOME}/.kube/config}}"
    [[ -f "${source_kubeconfig}" ]] || {
      rm -rf "${tmp_dir}"
      printf 'kubeconfig not found for requested cluster context: %s\n' "${source_kubeconfig}" >&2
      return 4
    }
    command -v kubectl >/dev/null 2>&1 || {
      rm -rf "${tmp_dir}"
      printf 'kubectl is required to resolve cluster contexts for addon installs\n' >&2
      return 4
    }
    cleanup_kubeconfig="$(mktemp)"
    cp "${source_kubeconfig}" "${cleanup_kubeconfig}"
    if ! kubectl --kubeconfig "${cleanup_kubeconfig}" config use-context "${cluster_context}" >/dev/null 2>&1; then
      rm -rf "${tmp_dir}"
      rm -f "${cleanup_kubeconfig}"
      printf 'cluster context not found in kubeconfig: %s\n' "${cluster_context}" >&2
      return 4
    fi
    target_kubeconfig="${cleanup_kubeconfig}"
  else
    [[ -f "${kubeconfig_path}" ]] || {
      rm -rf "${tmp_dir}"
      printf 'kubeconfig not found: %s\n' "${kubeconfig_path}" >&2
      return 4
    }
    target_kubeconfig="${kubeconfig_path}"
  fi

  printf 'Executing packaged addon installer: %s\n' "${install_script}"
  (
    cd "${manifest_dir}"
    export KUBECONFIG="${target_kubeconfig}"
    bash "${install_path}"
  )
  local rc=$?
  if (( rc == 0 )) && [[ -n "${public_host}" ]]; then
    apply_addon_public_ingress "${manifest}" "$(printf '%s\n' "${metadata}" | sed -n '1p')" "${target_kubeconfig}" "${public_host}" || rc=$?
  fi
  rm -f "${cleanup_kubeconfig}"
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
      printf 'Usage: ./productive-k3s-core.sh addon <validate|install> [flags]\n' >&2
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

  "${SCRIPT_DIR}/validate-k3s-stack.sh" "${translated_args[@]}"
}

main() {
  local command="${1:-bootstrap}"
  local rc=0

  if (($# == 0)); then
    command="bootstrap"
  fi

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

  if core_command_emits_telemetry "${command}" "$@" && is_truthy "${TELEMETRY_ENABLED:-false}"; then
    if (( rc == 0 )); then
      write_generic_telemetry_event "core.command.completed" "${command}" "success"
    else
      write_generic_telemetry_event "core.command.completed" "${command}" "failed"
    fi
  fi

  return "${rc}"
}

main "$@"
