#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STACK_TGZ_URL="${STACK_TGZ_URL:-}"
STACK_EXPECTED_NAME="${STACK_EXPECTED_NAME:-base}"
STACK_TGZ_REMOTE_PATH="${STACK_TGZ_REMOTE_PATH:-/tmp/pk3s-stack.tgz}"
PLATFORM="${STACK_TEST_PLATFORM:-ubuntu}"
IMAGE="${STACK_TEST_IMAGE:-24.04}"
PROFILE="${STACK_TEST_PROFILE:-core}"
DISTRO="${PRODUCTIVE_K3S_DISTRO:-rke2}"
REMOTE_USER="${STACK_TEST_REMOTE_USER:-ubuntu}"
REMOTE_DIR="${STACK_TEST_REMOTE_DIR:-/home/${REMOTE_USER}/productive-k3s-core}"
REMOTE_ADDONS_DIR="${STACK_TEST_REMOTE_ADDONS_DIR:-/home/${REMOTE_USER}/productive-k3s-addons}"
VM_NAME="${STACK_TEST_VM_NAME:-pk3s-stack-artifact-$(date +%Y%m%d-%H%M%S)}"
INNER_ARTIFACTS_DIR="$(mktemp -d)"
VM_CREATED="n"

# TODO: Once published stacks can declare a minimum/maximum supported core runtime,
# replace the plain STACK_TGZ_URL input with a version-aware resolver.

cleanup() {
  rm -rf "${INNER_ARTIFACTS_DIR}"
  if [[ "${VM_CREATED}" == "y" ]]; then
    multipass delete "${VM_NAME}" >/dev/null 2>&1 || true
    multipass purge >/dev/null 2>&1 || true
  fi
}

usage() {
  cat <<'EOF'
Usage:
  STACK_TGZ_URL=<published-stack-url> ./tests/test-stack-artifact-in-vm.sh

Environment:
  STACK_TGZ_URL            Required URL for the published stack tgz
  STACK_EXPECTED_NAME      Expected stack name for logs and basic checks (default: base)
  STACK_TEST_VM_NAME       Optional explicit Multipass VM name
  STACK_TEST_PLATFORM      Optional platform passed to tests/test-in-vm.sh (default: ubuntu)
  STACK_TEST_IMAGE         Optional image passed to tests/test-in-vm.sh (default: 24.04)
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
  multipass exec "${VM_NAME}" -- bash -lc "$1"
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

main() {
  [[ -n "${STACK_TGZ_URL}" ]] || {
    usage >&2
    fail "STACK_TGZ_URL is required"
  }

  need_cmd multipass
  need_cmd curl
  trap cleanup EXIT

  log "Running core bootstrap profile in VM '${VM_NAME}'"
  TEST_ARTIFACTS_DIR="${INNER_ARTIFACTS_DIR}" PRODUCTIVE_K3S_DISTRO="${DISTRO}" \
    "${REPO_DIR}/tests/test-in-vm.sh" \
      --platform "${PLATFORM}" \
      --image "${IMAGE}" \
      --profile "${PROFILE}" \
      --name "${VM_NAME}" \
      --keep-vm
  VM_CREATED="y"

  log "Removing staged addons checkout from the VM to prevent source-based fallback"
  run_in_vm "rm -rf '${REMOTE_ADDONS_DIR}'"
  assert_in_vm "test ! -d '${REMOTE_ADDONS_DIR}'" "remote addons checkout was not removed"

  log "Downloading published stack artifact from ${STACK_TGZ_URL}"
  run_in_vm "curl -fsSL '${STACK_TGZ_URL}' -o '${STACK_TGZ_REMOTE_PATH}'"
  assert_in_vm "test -f '${STACK_TGZ_REMOTE_PATH}'" "published stack tgz was not downloaded into the VM"

  log "Checking packaged stack contents"
  assert_in_vm "tar -tzf '${STACK_TGZ_REMOTE_PATH}' | grep -q '^./stack.yaml$'" "published stack tgz is missing stack.yaml"
  assert_in_vm "tar -tzf '${STACK_TGZ_REMOTE_PATH}' | grep -q '^./addons/'" "published stack tgz is missing bundled addon artifacts"
  assert_in_vm "tar -xOf '${STACK_TGZ_REMOTE_PATH}' ./stack.yaml | grep -q 'name: ${STACK_EXPECTED_NAME}'" "published stack manifest does not expose the expected stack name"

  log "Running packaged stack dry-run first"
  run_in_vm "cd '${REMOTE_DIR}' && unset PRODUCTIVE_K3S_ADDONS_REPO_DIR && export PRODUCTIVE_K3S_DISTRO='${DISTRO}' PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true && ./productive-k3s-core.sh stack install --tgz '${STACK_TGZ_REMOTE_PATH}' --dry-run >/tmp/pk3s-stack-dry-run.log 2>&1 </dev/null"

  log "Installing the packaged stack from TGZ"
  full_answers | multipass exec "${VM_NAME}" -- bash -lc "
    cd '${REMOTE_DIR}' &&
    unset PRODUCTIVE_K3S_ADDONS_REPO_DIR &&
    export PRODUCTIVE_K3S_DISTRO='${DISTRO}' &&
    export PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true &&
    ./productive-k3s-core.sh stack install --tgz '${STACK_TGZ_REMOTE_PATH}'
  "

  log "Validating installed stack resources"
  if [[ "${DISTRO}" == "rke2" ]]; then
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace cert-manager >/dev/null 2>&1" "cert-manager namespace was not created from the packaged stack"
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace longhorn-system >/dev/null 2>&1" "longhorn-system namespace was not created from the packaged stack"
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace cattle-system >/dev/null 2>&1" "cattle-system namespace was not created from the packaged stack"
    assert_in_vm "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace registry >/dev/null 2>&1" "registry namespace was not created from the packaged stack"
  else
    assert_in_vm "sudo k3s kubectl get namespace cert-manager >/dev/null 2>&1" "cert-manager namespace was not created from the packaged stack"
    assert_in_vm "sudo k3s kubectl get namespace longhorn-system >/dev/null 2>&1" "longhorn-system namespace was not created from the packaged stack"
    assert_in_vm "sudo k3s kubectl get namespace cattle-system >/dev/null 2>&1" "cattle-system namespace was not created from the packaged stack"
    assert_in_vm "sudo k3s kubectl get namespace registry >/dev/null 2>&1" "registry namespace was not created from the packaged stack"
  fi

  log "Published stack artifact flow succeeded"
}

main "$@"
