#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_IMAGES_ENV="${SCRIPT_DIR}/vm-images.env"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck disable=SC1090
source "${VM_IMAGES_ENV}"

ARTIFACTS_DIR="${TMP_DIR}/test-artifacts"
mkdir -p "${ARTIFACTS_DIR}"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -F "$needle" >/dev/null || fail "expected output to contain: $needle"
}

cat > "${ARTIFACTS_DIR}/test-in-vm-20260812-000001-smoke-ubuntu.json" <<EOF
{
  "test_type": "vm",
  "profile": "smoke",
  "platform": "ubuntu",
  "image": "${UBUNTU_24_04_IMAGE}",
  "status": "success",
  "bootstrap_manifest_local": ""
}
EOF

cat > "${ARTIFACTS_DIR}/test-in-vm-20260812-000001-core-ubuntu.json" <<EOF
{
  "test_type": "vm",
  "profile": "core",
  "platform": "ubuntu",
  "image": "${UBUNTU_24_04_IMAGE}",
  "status": "success",
  "bootstrap_manifest_local": "/tmp/test-in-vm-20260812-000001-core-ubuntu-apply-manifest.json"
}
EOF

set +e
smoke_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  bash "${REPO_DIR}/tests/check-test-artifacts.sh" --profile smoke --expect "ubuntu|${UBUNTU_24_04_IMAGE}" 2>&1
)"
smoke_rc=$?
set -e
[[ "${smoke_rc}" -eq 0 ]] || fail "smoke artifacts without bootstrap manifest should be accepted"
assert_contains "${smoke_output}" "Artifact and bootstrap manifest validation passed for profile 'smoke'"

set +e
core_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  bash "${REPO_DIR}/tests/check-test-artifacts.sh" --profile core --expect "ubuntu|${UBUNTU_24_04_IMAGE}" 2>&1
)"
core_rc=$?
set -e
[[ "${core_rc}" -ne 0 ]] || fail "core artifacts without bootstrap manifest should fail"
assert_contains "${core_output}" "Missing bootstrap manifest paired with artifact"

printf '[PASS] check-test-artifacts handles smoke dry-run artifacts without requiring bootstrap manifests\n'
