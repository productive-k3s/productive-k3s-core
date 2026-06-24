#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/apply.sh"

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${BOOTSTRAP_SCRIPT}"

TEST_PROMPT_CALLS=0
TEST_INTERACTIVE="n"
TEST_PROMPT_RESPONSE=""
TEST_LAST_PROMPT_DEFAULT=""
TEST_LAST_PROMPT_MESSAGE=""

can_use_tty() {
  [[ "${TEST_INTERACTIVE}" == "y" ]]
}

prompt_yesno() {
  local var="$1" default="$2" msg="$3"
  TEST_PROMPT_CALLS=$((TEST_PROMPT_CALLS + 1))
  TEST_LAST_PROMPT_DEFAULT="${default}"
  TEST_LAST_PROMPT_MESSAGE="${msg}"
  local answer="${TEST_PROMPT_RESPONSE:-$default}"
  printf -v "$var" '%s' "$answer"
}

reset_test_state() {
  TEST_PROMPT_CALLS=0
  TEST_INTERACTIVE="n"
  TEST_PROMPT_RESPONSE=""
  TEST_LAST_PROMPT_DEFAULT=""
  TEST_LAST_PROMPT_MESSAGE=""
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    printf '[FAIL] %s: expected %s, got %s\n' "${label}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf '[FAIL] %s: expected to find %s in %s\n' "${label}" "${needle}" "${haystack}" >&2
    exit 1
  fi
}

reset_test_state
TELEMETRY_ENABLED="true"
resolve_telemetry_enabled
assert_eq "true" "${TELEMETRY_ENABLED}" "explicit true stays enabled"
assert_eq "0" "${TEST_PROMPT_CALLS}" "explicit true does not prompt"

reset_test_state
TELEMETRY_ENABLED="false"
resolve_telemetry_enabled
assert_eq "false" "${TELEMETRY_ENABLED}" "explicit false stays disabled"
assert_eq "0" "${TEST_PROMPT_CALLS}" "explicit false does not prompt"

reset_test_state
unset TELEMETRY_ENABLED
TEST_INTERACTIVE="y"
resolve_telemetry_enabled
assert_eq "true" "${TELEMETRY_ENABLED}" "interactive unset defaults to enabled"
assert_eq "1" "${TEST_PROMPT_CALLS}" "interactive unset prompts once"
assert_eq "y" "${TEST_LAST_PROMPT_DEFAULT}" "interactive unset prompt default is yes"
assert_contains "${TEST_LAST_PROMPT_MESSAGE}" "anonymous telemetry" "prompt explains telemetry is anonymous"
assert_contains "${TEST_LAST_PROMPT_MESSAGE}" "sensitive information like hostnames or other environment-specific identifiers" "prompt explains privacy scope"

reset_test_state
unset TELEMETRY_ENABLED
TEST_INTERACTIVE="y"
TEST_PROMPT_RESPONSE="n"
resolve_telemetry_enabled
assert_eq "false" "${TELEMETRY_ENABLED}" "interactive opt-out disables telemetry"
assert_eq "1" "${TEST_PROMPT_CALLS}" "interactive opt-out still prompts once"

reset_test_state
unset TELEMETRY_ENABLED
resolve_telemetry_enabled
assert_eq "false" "${TELEMETRY_ENABLED}" "non-interactive unset stays disabled"
assert_eq "0" "${TEST_PROMPT_CALLS}" "non-interactive unset does not prompt"

printf '[PASS] telemetry consent resolution behaves as expected\n'
