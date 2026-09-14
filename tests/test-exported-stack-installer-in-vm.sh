#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_IMAGES_ENV="${SCRIPT_DIR}/vm-images.env"

# shellcheck disable=SC1090
source "${VM_IMAGES_ENV}"

STACK_TGZ_URL="${STACK_TGZ_URL:-https://downloads.productive-k3s.io/addons/base-0.1.0.tgz}"
STACK_EXPECTED_NAME="${STACK_EXPECTED_NAME:-base}"
EXPORT_TELEMETRY_ENABLED="${EXPORT_TELEMETRY_ENABLED:-false}"
LOCAL_STACK_TGZ_PATH="${LOCAL_STACK_TGZ_PATH:-}"
LOCAL_INSTALLER_TGZ_PATH="${LOCAL_INSTALLER_TGZ_PATH:-}"
REMOTE_INSTALLER_TGZ_PATH="${REMOTE_INSTALLER_TGZ_PATH:-/tmp/pk3s-base-installer.tgz}"
REMOTE_INSTALLER_ROOT="${REMOTE_INSTALLER_ROOT:-/tmp/pk3s-base-installer}"
PLATFORM="${STACK_TEST_PLATFORM:-debian12}"
IMAGE="${STACK_TEST_IMAGE:-${DEBIAN_12_IMAGE}}"
PROFILE="${STACK_TEST_PROFILE:-core}"
DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
ENGINE="${PRODUCTIVE_K3S_ENGINE:-native}"
REMOTE_USER="${STACK_TEST_REMOTE_USER:-ubuntu}"
REMOTE_DIR="${STACK_TEST_REMOTE_DIR:-/home/${REMOTE_USER}/productive-k3s-core}"
REMOTE_ADDONS_DIR="${STACK_TEST_REMOTE_ADDONS_DIR:-/home/${REMOTE_USER}/productive-k3s-addons}"
VM_NAME="${STACK_TEST_VM_NAME:-pk3s-exported-stack-$(date +%Y%m%d-%H%M%S)}"
HOST_STAGING_ROOT="${HOST_STAGING_ROOT:-${HOME}/pk3s-exported-stack-staging}"
INNER_ARTIFACTS_DIR=""
EXPORTED_INSTALLER_TGZ_PATH=""
VM_CREATED="n"

cleanup() {
  if [[ -n "${INNER_ARTIFACTS_DIR}" ]]; then
    rm -rf "${INNER_ARTIFACTS_DIR}"
  fi
  if [[ "${VM_CREATED}" == "y" ]]; then
    multipass delete "${VM_NAME}" >/dev/null 2>&1 || true
    multipass purge >/dev/null 2>&1 || true
  fi
}

usage() {
  cat <<'EOF'
Usage:
  ./tests/test-exported-stack-installer-in-vm.sh

Environment:
  STACK_TGZ_URL              Published stack tgz URL used to build the exported installer
                             (default: https://downloads.productive-k3s.io/addons/base-0.1.0.tgz)
  STACK_EXPECTED_NAME        Expected stack name for logs and basic checks (default: base)
  EXPORT_TELEMETRY_ENABLED   TELEMETRY_ENABLED value frozen into the exported installer (default: false)
  STACK_TEST_VM_NAME         Optional explicit Multipass VM name
  STACK_TEST_PLATFORM        Optional platform passed to tests/test-in-vm.sh (default: debian12)
  STACK_TEST_IMAGE           Optional image passed to tests/test-in-vm.sh (default: pinned Debian 12 bookworm cloud image)
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[ERROR] Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

log() {
  printf '[INFO] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

run_in_vm() {
  multipass exec "${VM_NAME}" -- bash -lc "$1" </dev/null
}

assert_in_vm() {
  local cmd="$1"
  local label="$2"
  if ! run_in_vm "$cmd" >/dev/null 2>&1; then
    fail "${label}"
  fi
}

full_answers() {
  cat <<'EOF'
y
y
y
y
home.arpa
2



y

admin





y
EOF
}

exported_stack_install_command() {
  local answers escaped_answers
  answers="$(full_answers)"
  escaped_answers="$(printf '%q' "${answers}")"
  printf "installer_dir=\"\$(find '%s' -mindepth 1 -maxdepth 1 -type d | head -1)\" && test -n \"\${installer_dir}\" && cd \"\${installer_dir}\" && bootstrap_answers_file=\"\$(mktemp)\" && printf '%%s' %s > \"\${bootstrap_answers_file}\" && export PRODUCTIVE_K3S_DISTRO='%s' PRODUCTIVE_K3S_ENGINE='%s' PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true && ./install.sh < \"\${bootstrap_answers_file}\"; stack_rc=\$?; rm -f \"\${bootstrap_answers_file}\"; exit \"\${stack_rc}\"" \
    "${REMOTE_INSTALLER_ROOT}" \
    "${escaped_answers}" \
    "${DISTRO}" \
    "${ENGINE}"
}

download_and_export_installer() {
  local stack_tgz_path installer_tgz_path

  if [[ -n "${LOCAL_STACK_TGZ_PATH}" ]]; then
    stack_tgz_path="${LOCAL_STACK_TGZ_PATH}"
  else
    stack_tgz_path="${INNER_ARTIFACTS_DIR}/${STACK_EXPECTED_NAME}-stack.tgz"
    log "Downloading published stack artifact from ${STACK_TGZ_URL}" >&2
    curl -fsSL "${STACK_TGZ_URL}" -o "${stack_tgz_path}"
  fi

  if [[ -n "${LOCAL_INSTALLER_TGZ_PATH}" ]]; then
    installer_tgz_path="${LOCAL_INSTALLER_TGZ_PATH}"
  else
    installer_tgz_path="${INNER_ARTIFACTS_DIR}/${STACK_EXPECTED_NAME}-installer.tgz"
    log "Exporting self-contained installer from ${stack_tgz_path}" >&2
    (
      cd "${REPO_DIR}" &&
      PRODUCTIVE_K3S_DISTRO="${DISTRO}" PRODUCTIVE_K3S_ENGINE="${ENGINE}" TELEMETRY_ENABLED="${EXPORT_TELEMETRY_ENABLED}" ./productive-k3s-core.sh stack export --tgz "${stack_tgz_path}" --output "${installer_tgz_path}"
    )
  fi

  [[ -f "${installer_tgz_path}" ]] || fail "exported installer archive was not created"
  EXPORTED_INSTALLER_TGZ_PATH="${installer_tgz_path}"
}

main() {
  validate_runtime_matrix
  need_cmd multipass
  need_cmd curl
  trap cleanup EXIT
  mkdir -p "${HOST_STAGING_ROOT}"
  INNER_ARTIFACTS_DIR="$(mktemp -d "${HOST_STAGING_ROOT}/run.XXXXXX")"

  download_and_export_installer
  [[ -n "${EXPORTED_INSTALLER_TGZ_PATH}" ]] || fail "exported installer path was not recorded"

  log "Running core bootstrap profile in VM '${VM_NAME}'"
  TEST_ARTIFACTS_DIR="${INNER_ARTIFACTS_DIR}" PRODUCTIVE_K3S_DISTRO="${DISTRO}" PRODUCTIVE_K3S_ENGINE="${ENGINE}" \
    "${REPO_DIR}/tests/test-in-vm.sh" \
      --platform "${PLATFORM}" \
      --image "${IMAGE}" \
      --profile "${PROFILE}" \
      --name "${VM_NAME}" \
      --keep-vm
  VM_CREATED="y"

  log "Removing staged Productive K3S source checkouts from the VM"
  run_in_vm "rm -rf '${REMOTE_ADDONS_DIR}' '${REMOTE_DIR}'"
  assert_in_vm "test ! -d '${REMOTE_ADDONS_DIR}'" "remote addons checkout was not removed"
  assert_in_vm "test ! -d '${REMOTE_DIR}'" "remote core checkout was not removed"

  log "Transferring exported installer bundle to the VM"
  multipass transfer "${EXPORTED_INSTALLER_TGZ_PATH}" "${VM_NAME}:${REMOTE_INSTALLER_TGZ_PATH}" >/dev/null
  assert_in_vm "test -f '${REMOTE_INSTALLER_TGZ_PATH}'" "exported installer archive was not copied into the VM"

  log "Checking exported installer contents"
  assert_in_vm "tar -tzf '${REMOTE_INSTALLER_TGZ_PATH}' | grep -q '/install.sh$'" "exported installer archive is missing install.sh"
  assert_in_vm "tar -tzf '${REMOTE_INSTALLER_TGZ_PATH}' | grep -q '/preflight.sh$'" "exported installer archive is missing preflight.sh"
  assert_in_vm "tar -tzf '${REMOTE_INSTALLER_TGZ_PATH}' | grep -q '/AGENTS.md$'" "exported installer archive is missing AGENTS.md"
  assert_in_vm "tar -tzf '${REMOTE_INSTALLER_TGZ_PATH}' | grep -q '/stack.tgz$'" "exported installer archive is missing stack.tgz"
  assert_in_vm "tar -tzf '${REMOTE_INSTALLER_TGZ_PATH}' | grep -q '/manifest.json$'" "exported installer archive is missing manifest.json"

  log "Extracting exported installer bundle in the VM"
  run_in_vm "rm -rf '${REMOTE_INSTALLER_ROOT}' && mkdir -p '${REMOTE_INSTALLER_ROOT}' && tar -xzf '${REMOTE_INSTALLER_TGZ_PATH}' -C '${REMOTE_INSTALLER_ROOT}'"
  assert_in_vm "find '${REMOTE_INSTALLER_ROOT}' -mindepth 1 -maxdepth 1 -type d | grep -q ." "exported installer archive did not unpack a bundle directory"

  log "Running exported installer in the VM"
  run_in_vm "$(exported_stack_install_command)"

  log "Validating installed stack resources"
  if [[ "${DISTRO}" == "rke2" ]]; then
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace cert-manager >/dev/null 2>&1" "cert-manager namespace was not created from the exported installer"
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace longhorn-system >/dev/null 2>&1" "longhorn-system namespace was not created from the exported installer"
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace cattle-system >/dev/null 2>&1" "cattle-system namespace was not created from the exported installer"
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace registry >/dev/null 2>&1" "registry namespace was not created from the exported installer"
  else
    assert_in_vm "sudo k3s kubectl get namespace cert-manager >/dev/null 2>&1" "cert-manager namespace was not created from the exported installer"
    assert_in_vm "sudo k3s kubectl get namespace longhorn-system >/dev/null 2>&1" "longhorn-system namespace was not created from the exported installer"
    assert_in_vm "sudo k3s kubectl get namespace cattle-system >/dev/null 2>&1" "cattle-system namespace was not created from the exported installer"
    assert_in_vm "sudo k3s kubectl get namespace registry >/dev/null 2>&1" "registry namespace was not created from the exported installer"
  fi

  log "Exported stack installer flow succeeded"
}

validate_runtime_matrix() {
  if [[ "${DISTRO}" == "rke2" && "${PLATFORM}" != "ubuntu" ]]; then
    fail "rke2 exported stack installer tests currently support Ubuntu only (requested platform: ${PLATFORM})"
  fi
  if [[ "${DISTRO}" == "rke2" && "${ENGINE}" != "native" ]]; then
    fail "rke2 exported stack installer tests require the native engine (requested engine: ${ENGINE})"
  fi
  if [[ "${ENGINE}" == "k3sup" && "${PLATFORM}" != "ubuntu" ]]; then
    fail "k3sup exported stack installer tests currently support Ubuntu only (requested platform: ${PLATFORM})"
  fi
}

main "$@"
