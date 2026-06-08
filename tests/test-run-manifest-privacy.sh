#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/apply.sh"
ROLLBACK_SCRIPT="${ROOT_DIR}/scripts/rollback.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

search_file() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q -- "${pattern}" "${file}"
  else
    grep -Eq -- "${pattern}" "${file}"
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! search_file "${pattern}" "${file}"; then
    printf '[FAIL] expected %s to contain %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  if search_file "${pattern}" "${file}"; then
    printf '[FAIL] expected %s to omit %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${BOOTSTRAP_SCRIPT}"

RUNS_DIR="${TMP_DIR}"
RUN_STATUS="success"
CURRENT_STEP="registry"
manifest_set_setting "bootstrap_mode" "single-node"
manifest_set_setting "host_os_id" "ubuntu"
manifest_set_setting "host_os_version_id" "24.04"
manifest_set_setting "agent_server_url" "https://10.0.0.10:6443"
manifest_set_setting "agent_server_url_provided" "y"
manifest_set_setting "base_domain" "example.local"
manifest_set_setting "rancher_host" "rancher.example.local"
manifest_set_setting "registry_host" "registry.example.local"
manifest_set_setting "longhorn_data_path" "/data"
manifest_set_setting "registry_storage_class" "longhorn-single"
manifest_set_setting "registry_storage_class_configured" "y"
manifest_set_setting "nfs_export_path" "/srv/nfs/k8s-share"
manifest_set_setting "nfs_allowed_network" "10.0.0.0/24"
manifest_record_component "clusterissuer" "missing" "ensure"
manifest_complete_component "clusterissuer" "installed" "selfsigned"
manifest_record_component "rancher_host_local" "unknown" "configure"
manifest_complete_component "rancher_host_local" "configured" "10.0.0.10 rancher.example.local"
manifest_record_component "registry_host_local" "unknown" "configure"
manifest_complete_component "registry_host_local" "configured" "10.0.0.10 registry.example.local"
manifest_record_component "registry_docker_trust" "unknown" "configure"
manifest_complete_component "registry_docker_trust" "configured" "registry.example.local"
manifest_record_component "nfs" "missing" "install"
manifest_complete_component "nfs" "configured" "/srv/nfs/k8s-share 10.0.0.0/24"
init_run_manifest
write_run_manifest 0
write_private_run_context 0

PUBLIC_MANIFEST="${RUN_MANIFEST}"
PRIVATE_CONTEXT="${RUN_PRIVATE_CONTEXT}"

assert_file_not_contains "${PUBLIC_MANIFEST}" '"host"'
assert_file_not_contains "${PUBLIC_MANIFEST}" '"user"'
assert_file_not_contains "${PUBLIC_MANIFEST}" '"cwd"'
assert_file_not_contains "${PUBLIC_MANIFEST}" '10\.0\.0\.10'
assert_file_not_contains "${PUBLIC_MANIFEST}" 'example\.local'
assert_file_not_contains "${PUBLIC_MANIFEST}" '/srv/nfs/k8s-share'
assert_file_contains "${PUBLIC_MANIFEST}" '"agent_server_url_provided": "y"'
assert_file_contains "${PUBLIC_MANIFEST}" '"registry_storage_class_configured": "y"'
assert_file_contains "${PUBLIC_MANIFEST}" '"clusterissuer": \{"detected_before": "missing", "planned_action": "ensure", "result": "installed", "note": "selfsigned"\}'

assert_file_contains "${PRIVATE_CONTEXT}" '10\.0\.0\.10'
assert_file_contains "${PRIVATE_CONTEXT}" 'example\.local'
assert_file_contains "${PRIVATE_CONTEXT}" '/srv/nfs/k8s-share'

unset MANIFEST MANIFEST_PRIVATE_CONTEXT
PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${ROLLBACK_SCRIPT}"
MANIFEST="${PUBLIC_MANIFEST}"
require_prereqs

if [[ "$(setting nfs_export_path)" != "/srv/nfs/k8s-share" ]]; then
  printf '[FAIL] rollback did not read nfs_export_path from private context\n' >&2
  exit 1
fi

if [[ "$(component_field rancher_host_local note)" != "10.0.0.10 rancher.example.local" ]]; then
  printf '[FAIL] rollback did not read rancher_host_local note from private context\n' >&2
  exit 1
fi

if [[ "$(component_field registry_host_local note)" != "10.0.0.10 registry.example.local" ]]; then
  printf '[FAIL] rollback did not read registry_host_local note from private context\n' >&2
  exit 1
fi

if [[ "$(component_field registry_docker_trust note)" != "registry.example.local" ]]; then
  printf '[FAIL] rollback did not read registry_docker_trust note from private context\n' >&2
  exit 1
fi

MANIFEST="${PRIVATE_CONTEXT}"
require_prereqs
if [[ "${MANIFEST}" != "${PUBLIC_MANIFEST}" ]]; then
  printf '[FAIL] rollback did not normalize the private context path back to the public manifest\n' >&2
  exit 1
fi

printf '[PASS] public manifest is anonymous and rollback reads the private context locally\n'
