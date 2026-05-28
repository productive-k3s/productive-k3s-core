#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/bootstrap-k3s-stack.sh"

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${BOOTSTRAP_SCRIPT}"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_mode_result() {
  local mode="$1" expected="$2"
  MODE="$mode"
  if mode_uses_single_node_defaults; then
    [[ "$expected" == "true" ]] || fail "mode ${mode} unexpectedly uses single-node defaults"
  else
    [[ "$expected" == "false" ]] || fail "mode ${mode} should use single-node defaults"
  fi
}

assert_mode_result single-node true
assert_mode_result stack true
assert_mode_result server false
assert_mode_result agent false

printf '[PASS] single-node default mode selection behaves as expected\n'
