#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${REPO_DIR}/tests/test-in-vm.sh"

MOCK_BIN="${TMP_DIR}/bin"
MOCK_LOG="${TMP_DIR}/multipass.log"
STDOUT_LOG="${TMP_DIR}/stdout.log"
STDERR_LOG="${TMP_DIR}/stderr.log"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/multipass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${MOCK_MULTIPASS_LOG}"
sleep 10
EOF
chmod +x "${MOCK_BIN}/multipass"

write_artifacts() {
  :
}

VM_NAME="productive-k3s-core-timeout-fixture"
VM_CREATED="y"
KEEP_VM="n"
PURGE_ON_CLEANUP="y"
TRANSFER_STAGING_ROOT=""
TRANSFER_STAGED_REPO=""
VM_CLEANUP_TIMEOUT_SECONDS="1"

set +e
PATH="${MOCK_BIN}:$PATH" \
MOCK_MULTIPASS_LOG="${MOCK_LOG}" \
PRODUCTIVE_K3S_LIB_ONLY=1 \
timeout 5 bash -c '
  source "$1"
  write_artifacts(){ :; }
  VM_NAME="$2"
  VM_CREATED="$3"
  KEEP_VM="$4"
  PURGE_ON_CLEANUP="$5"
  VM_CLEANUP_TIMEOUT_SECONDS="$6"
  cleanup
' _ "${REPO_DIR}/tests/test-in-vm.sh" "${VM_NAME}" "${VM_CREATED}" "${KEEP_VM}" "${PURGE_ON_CLEANUP}" "${VM_CLEANUP_TIMEOUT_SECONDS}" >"${STDOUT_LOG}" 2>"${STDERR_LOG}"
rc=$?
set -e

if [[ "${rc}" -ne 0 ]]; then
  printf '[FAIL] cleanup did not finish successfully when multipass commands hung (rc=%s)\n' "${rc}" >&2
  cat "${STDERR_LOG}" >&2 || true
  exit 1
fi

grep -Fq 'delete productive-k3s-core-timeout-fixture' "${MOCK_LOG}" || {
  printf '[FAIL] cleanup did not attempt multipass delete\n' >&2
  exit 1
}

grep -Fq 'purge' "${MOCK_LOG}" || {
  printf '[FAIL] cleanup did not attempt multipass purge\n' >&2
  exit 1
}

grep -Fq 'multipass delete timed out after 1s; continuing' "${STDOUT_LOG}" || {
  printf '[FAIL] cleanup did not emit timeout warning for delete\n' >&2
  cat "${STDOUT_LOG}" >&2 || true
  exit 1
}

grep -Fq 'multipass purge timed out after 1s; continuing' "${STDOUT_LOG}" || {
  printf '[FAIL] cleanup did not emit timeout warning for purge\n' >&2
  cat "${STDOUT_LOG}" >&2 || true
  exit 1
}

printf '[PASS] in-vm cleanup survives hung multipass delete and purge\n'
