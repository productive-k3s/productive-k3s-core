#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

REMOTE_DIR="/home/ubuntu/productive-k3s-core"
escaped_answers="'y\n'"

PRODUCTIVE_K3S_ENGINE="k3sup"
command_with_engine="$(core_cli_command_in_vm "apply" "--dry-run" "$escaped_answers")"
printf '%s\n' "$command_with_engine" | grep -q "PRODUCTIVE_K3S_ENGINE=k3sup" || fail "engine env was not propagated into VM bootstrap command"
pass "VM core CLI command includes PRODUCTIVE_K3S_ENGINE when configured"

unset PRODUCTIVE_K3S_ENGINE
command_without_engine="$(core_cli_command_in_vm "apply" "--dry-run" "$escaped_answers")"
printf '%s\n' "$command_without_engine" | grep -q "PRODUCTIVE_K3S_ENGINE=" && fail "engine env should not be injected when unset"
pass "VM core CLI command leaves engine unset by default"
