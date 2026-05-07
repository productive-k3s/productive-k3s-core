#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR_FIXTURE="$(mktemp -d)"
ARTIFACTS_FIXTURE="$(mktemp -d)"

cleanup() {
  rm -rf "$REPO_DIR_FIXTURE" "$ARTIFACTS_FIXTURE"
}
trap cleanup EXIT

mkdir -p \
  "${REPO_DIR_FIXTURE}/fixture/docs/.venv/bin" \
  "${REPO_DIR_FIXTURE}/fixture/docs/site" \
  "${REPO_DIR_FIXTURE}/fixture/runs" \
  "${REPO_DIR_FIXTURE}/fixture/test-artifacts" \
  "${REPO_DIR_FIXTURE}/fixture/keep"

printf 'ok\n' > "${REPO_DIR_FIXTURE}/fixture/keep/file.txt"
ln -s /usr/bin/python3 "${REPO_DIR_FIXTURE}/fixture/docs/.venv/bin/python3"

PRODUCTIVE_K3S_LIB_ONLY=1 source "${SCRIPT_DIR}/test-in-vm.sh"

REPO_DIR="${REPO_DIR_FIXTURE}/fixture"
REPO_NAME="fixture"
ARTIFACTS_DIR="${ARTIFACTS_FIXTURE}"
ARTIFACT_BASENAME="repo-staging"

prepare_repo_transfer_dir

test -f "${TRANSFER_STAGED_REPO}/keep/file.txt"
test ! -e "${TRANSFER_STAGED_REPO}/docs/.venv"
test ! -e "${TRANSFER_STAGED_REPO}/docs/site"
test ! -e "${TRANSFER_STAGED_REPO}/runs"
test ! -e "${TRANSFER_STAGED_REPO}/test-artifacts"

printf '[PASS] repo transfer staging excludes local-only directories\n'
