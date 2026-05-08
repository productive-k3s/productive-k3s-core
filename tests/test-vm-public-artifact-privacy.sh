#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! rg -q "${pattern}" "${file}"; then
    printf '[FAIL] expected %s to contain %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  if rg -q "${pattern}" "${file}"; then
    printf '[FAIL] expected %s to omit %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${REPO_DIR}/tests/test-in-vm.sh"

ARTIFACTS_DIR="${TMP_DIR}"
ARTIFACT_BASENAME="test-in-vm-fixture-full-productive-k3s-core-test-ubuntu-full-fixture"
ARTIFACT_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.json"
PUBLIC_ARTIFACT_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}-public.json"

PROFILE="full"
PLATFORM="ubuntu"
VM_NAME="productive-k3s-core-test-ubuntu-full-fixture"
VM_CREATED="y"
KEEP_VM="n"
PURGE_ON_CLEANUP="y"
VM_IMAGE="24.04"
REMOTE_USER="ubuntu"
REMOTE_DIR="/home/ubuntu/productive-k3s-core"
VM_CPUS="4"
VM_MEMORY="8G"
VM_DISK="40G"
REPO_DIR="/home/example/work/productive-k3s"
ARTIFACT_STATUS="success"
BOOTSTRAP_MANIFEST_REMOTE="/home/ubuntu/productive-k3s-core/runs/bootstrap-20260430-010203-1234.json"
BOOTSTRAP_MANIFEST_LOCAL="/home/example/work/productive-k3s/test-artifacts/test-in-vm-fixture-bootstrap-manifest.json"

write_artifacts

assert_file_contains "${ARTIFACT_PATH}" '"vm_name": "productive-k3s-core-test-ubuntu-full-fixture"'
assert_file_contains "${ARTIFACT_PATH}" '"remote_dir": "/home/ubuntu/productive-k3s-core"'
assert_file_contains "${ARTIFACT_PATH}" '"repo_dir": "/home/example/work/productive-k3s"'
assert_file_contains "${ARTIFACT_PATH}" '"bootstrap_manifest_local": "/home/example/work/productive-k3s/test-artifacts/test-in-vm-fixture-bootstrap-manifest.json"'

assert_file_contains "${PUBLIC_ARTIFACT_PATH}" '"artifact_scope": "public"'
assert_file_contains "${PUBLIC_ARTIFACT_PATH}" '"bootstrap_manifest_copied": "y"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '"vm_name"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '"remote_user"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '"remote_dir"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '"repo_dir"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '"bootstrap_manifest_remote"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '"bootstrap_manifest_local"'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" '/home/'
assert_file_not_contains "${PUBLIC_ARTIFACT_PATH}" 'productive-k3s-core-test-'

printf '[PASS] local and public VM artifacts were generated with the expected privacy split\n'
