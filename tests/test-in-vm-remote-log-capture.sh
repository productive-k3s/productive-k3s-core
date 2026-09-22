#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

export PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck source=tests/test-in-vm.sh
source "${REPO_DIR}/tests/test-in-vm.sh"

ARTIFACTS_DIR="${TMP_DIR}"
ARTIFACT_BASENAME="test-in-vm-fixture-core-remote-log"
VM_NAME="productive-k3s-core-test-fixture"
REMOTE_COMMAND_LOG_REMOTE="/tmp/pk3s-remote-cmd-fixture.log"
REMOTE_COMMAND_LOG_LOCAL=""

multipass() {
  case "$1" in
    transfer)
      return 1
      ;;
    exec)
      printf '%s\n' "remote command failed"
      printf '%s\n' "stderr detail"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

capture_remote_command_log

[[ -n "$REMOTE_COMMAND_LOG_LOCAL" ]] || fail "remote command log local path was not recorded"
[[ -f "$REMOTE_COMMAND_LOG_LOCAL" ]] || fail "remote command log was not written"
grep -q "remote command failed" "$REMOTE_COMMAND_LOG_LOCAL" || fail "remote command output was not copied"
grep -q "stderr detail" "$REMOTE_COMMAND_LOG_LOCAL" || fail "remote command stderr detail was not copied"

pass "remote command log falls back to exec cat when transfer fails"
