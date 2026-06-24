#!/usr/bin/env bash

ADDON_RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${PRODUCTIVE_K3S_CORE_REPO_DIR:-}" && -f "${PRODUCTIVE_K3S_CORE_REPO_DIR}/scripts/runtime-contract.sh" ]]; then
  # shellcheck disable=SC1091
  source "${PRODUCTIVE_K3S_CORE_REPO_DIR}/scripts/runtime-contract.sh"
elif [[ -f "${ADDON_RUNTIME_DIR}/../../productive-k3s-core/scripts/runtime-contract.sh" ]]; then
  # shellcheck disable=SC1091
  source "${ADDON_RUNTIME_DIR}/../../productive-k3s-core/scripts/runtime-contract.sh"
fi

pk3s_runtime_cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

pk3s_runtime_log() {
  if declare -F log >/dev/null 2>&1; then
    log "$@"
  else
    printf '[INFO] %s\n' "$*"
  fi
}

pk3s_runtime_warn() {
  if declare -F warn >/dev/null 2>&1; then
    warn "$@"
  else
    printf '[WARN] %s\n' "$*" >&2
  fi
}

pk3s_manifest_complete_optional() {
  local component="$1"
  local result="$2"
  local note="${3:-}"
  if declare -F manifest_complete_component >/dev/null 2>&1; then
    manifest_complete_component "${component}" "${result}" "${note}"
  fi
}

pk3s_track_install_optional() {
  if declare -F track_install >/dev/null 2>&1; then
    track_install "$1"
  fi
}

pk3s_track_reuse_optional() {
  if declare -F track_reuse >/dev/null 2>&1; then
    track_reuse "$1"
  fi
}

pk3s_result_for_mode_optional() {
  local success_result="$1"
  if declare -F result_for_mode >/dev/null 2>&1; then
    result_for_mode "${success_result}"
  else
    printf '%s\n' "${success_result}"
  fi
}

pk3s_service_active_optional() {
  if declare -F service_active >/dev/null 2>&1; then
    service_active "$1"
    return $?
  fi
  systemctl is-active --quiet "$1" >/dev/null 2>&1
}

pk3s_pkg_installed_optional() {
  if declare -F pkg_installed >/dev/null 2>&1; then
    pkg_installed "$1"
    return $?
  fi
  dpkg -s "$1" >/dev/null 2>&1
}

pk3s_runtime_run_cmd() {
  local label="$1"
  shift
  if declare -F run_cmd >/dev/null 2>&1; then
    run_cmd "${label}" "$@"
  else
    pk3s_runtime_log "${label}"
    "$@"
  fi
}

pk3s_ensure_packages_optional() {
  local label="$1"
  shift

  if declare -F ensure_packages >/dev/null 2>&1; then
    ensure_packages "${label}" "$@"
    return
  fi

  local missing=()
  local pkg
  for pkg in "$@"; do
    if ! pk3s_pkg_installed_optional "${pkg}"; then
      missing+=("${pkg}")
    fi
  done

  if ((${#missing[@]} == 0)); then
    pk3s_runtime_log "Required packages for ${label} are already installed."
    return
  fi

  pk3s_runtime_warn "Installing missing packages for ${label}: ${missing[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${missing[@]}"
}

pk3s_enable_service_optional() {
  local service_name="$1"
  if pk3s_service_active_optional "${service_name}"; then
    pk3s_runtime_log "Service '${service_name}' already active."
    return
  fi

  pk3s_runtime_run_cmd "Enabling and starting ${service_name}" sudo systemctl enable --now "${service_name}"
}

pk3s_ensure_directory_optional() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    return 0
  fi
  pk3s_runtime_run_cmd "Ensuring directory ${path} exists" sudo mkdir -p "${path}"
}

pk3s_replace_local_hosts_entry() {
  local host="$1"
  local ip="$2"
  local component="$3"
  local desired_line="${ip} ${host}"

  if grep -qxF "${desired_line}" /etc/hosts 2>/dev/null; then
    pk3s_track_reuse_optional "/etc/hosts ${host}"
    pk3s_manifest_complete_optional "${component}" "$(pk3s_result_for_mode_optional reused)" "${desired_line}"
    return 0
  fi

  pk3s_track_install_optional "/etc/hosts ${host}"
  pk3s_runtime_run_cmd "Updating /etc/hosts entry for ${host}" sudo sh -c "sed -i '/[[:space:]]${host//./\\.}\$/d' /etc/hosts && printf '%s\\n' '$desired_line' >> /etc/hosts"
  pk3s_manifest_complete_optional "${component}" "$(pk3s_result_for_mode_optional configured)" "${desired_line}"
}

pk3s_remove_local_hosts_entry() {
  local host="$1"
  sudo sed -i "/[[:space:]]${host//./\\.}\$/d" /etc/hosts || true
}

pk3s_export_tls_secret_cert() {
  local namespace="$1"
  local secret_name="$2"
  local output_path="$3"
  local kubectl_mode="${PK3S_KUBECTL_MODE:-kubectl}"
  local kubectl_bin="${PK3S_KUBECTL_BIN:-kubectl}"

  if [[ "${kubectl_mode}" == "k3s" ]]; then
    sudo k3s kubectl -n "${namespace}" get secret "${secret_name}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | sudo tee "${output_path}" >/dev/null
  else
    "${kubectl_bin}" -n "${namespace}" get secret "${secret_name}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | sudo tee "${output_path}" >/dev/null
  fi
}

pk3s_install_local_docker_trust() {
  local namespace="$1"
  local secret_name="$2"
  local registry_host="$3"
  local component="$4"

  local trust_dir="/etc/docker/certs.d/${registry_host}"
  local ca_path="${trust_dir}/ca.crt"

  if [[ -f "${ca_path}" ]]; then
    pk3s_track_reuse_optional "Docker trust ${registry_host}"
    pk3s_manifest_complete_optional "${component}" "$(pk3s_result_for_mode_optional reused)" "${registry_host}"
    return 0
  fi

  pk3s_track_install_optional "Docker trust ${registry_host}"
  sudo mkdir -p "${trust_dir}"
  pk3s_export_tls_secret_cert "${namespace}" "${secret_name}" "${ca_path}"
  if systemctl list-unit-files docker.service >/dev/null 2>&1; then
    sudo systemctl restart docker || true
  fi
  pk3s_manifest_complete_optional "${component}" "$(pk3s_result_for_mode_optional configured)" "${registry_host}"
}

pk3s_remove_local_docker_trust() {
  local registry_host="$1"
  sudo rm -rf "/etc/docker/certs.d/${registry_host}" || true
  if systemctl list-unit-files docker.service >/dev/null 2>&1; then
    sudo systemctl restart docker || true
  fi
}
