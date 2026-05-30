#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT_DIR}/scripts/create-release-tag.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "${haystack}" | grep -F "${needle}" >/dev/null || fail "expected output to contain: ${needle}"
}

WORKTREE="${TMP_DIR}/repo"
git init -q "${WORKTREE}"
git -C "${WORKTREE}" config user.name "Test User"
git -C "${WORKTREE}" config user.email "test@example.invalid"
printf 'hello\n' > "${WORKTREE}/README.md"
git -C "${WORKTREE}" add README.md
git -C "${WORKTREE}" commit -q -m "initial"

set +e
invalid_output="$(PRODUCTIVE_K3S_CORE_REPO_DIR="${WORKTREE}" bash "${HELPER}" invalid 2>&1)"
invalid_rc=$?
set -e
[[ "${invalid_rc}" -ne 0 ]] || fail "invalid version unexpectedly succeeded"
assert_contains "${invalid_output}" "invalid productive-k3s-core version"

TAG_NAME="1.2.3"
output="$(PRODUCTIVE_K3S_CORE_REPO_DIR="${WORKTREE}" bash "${HELPER}" "${TAG_NAME}")"
assert_contains "${output}" "Created tag ${TAG_NAME}"
git -C "${WORKTREE}" rev-parse --verify "${TAG_NAME}^{tag}" >/dev/null 2>&1 || fail "expected local tag ${TAG_NAME}"

set +e
duplicate_output="$(PRODUCTIVE_K3S_CORE_REPO_DIR="${WORKTREE}" bash "${HELPER}" "${TAG_NAME}" 2>&1)"
duplicate_rc=$?
set -e
[[ "${duplicate_rc}" -ne 0 ]] || fail "duplicate local tag unexpectedly succeeded"
assert_contains "${duplicate_output}" "tag already exists locally: ${TAG_NAME}"

printf '[PASS] productive-k3s-core release tag helper validates version and creates annotated tags\n'
