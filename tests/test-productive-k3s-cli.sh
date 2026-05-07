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

cli_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s.sh help)"
printf '%s\n' "$cli_help" | grep -q "bootstrap" || fail "public CLI help does not list bootstrap"
printf '%s\n' "$cli_help" | grep -q "preflight" || fail "public CLI help does not list preflight"
printf '%s\n' "$cli_help" | grep -q "validate" || fail "public CLI help does not list validate"
pass "public CLI help lists operational commands"

bootstrap_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s.sh bootstrap --help)"
printf '%s\n' "$bootstrap_help" | grep -q -- '--dry-run' || fail "bootstrap help was not forwarded"
pass "bootstrap subcommand forwards CLI help"

preflight_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s.sh preflight --help)"
printf '%s\n' "$preflight_help" | grep -q -- '--mode <single-node|server|agent|stack>' || fail "preflight help was not forwarded"
pass "preflight subcommand forwards CLI help"

validate_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s.sh validate --help)"
printf '%s\n' "$validate_help" | grep -q -- '--strict' || fail "validate help was not forwarded"
pass "validate subcommand forwards CLI help"

if (cd "$REPO_DIR" && ./scripts/productive-k3s.sh unsupported >/tmp/productive-k3s-cli-unsupported.out 2>&1); then
  fail "unsupported public CLI command unexpectedly succeeded"
fi
grep -q "Unsupported command" /tmp/productive-k3s-cli-unsupported.out || fail "unsupported public CLI command message missing"
pass "unsupported public CLI command is rejected"

preflight_recipe="$(cd "$REPO_DIR" && make -n preflight)"
printf '%s\n' "$preflight_recipe" | grep -q './scripts/productive-k3s.sh preflight' || fail "make preflight does not target public CLI"
pass "make preflight targets public CLI"

preflight_strict_recipe="$(cd "$REPO_DIR" && make -n preflight-strict)"
printf '%s\n' "$preflight_strict_recipe" | grep -q './scripts/productive-k3s.sh preflight --strict' || fail "make preflight-strict does not map to base command plus flag"
pass "make preflight-strict maps to preflight --strict"

dry_run_recipe="$(cd "$REPO_DIR" && make -n dry-run)"
printf '%s\n' "$dry_run_recipe" | grep -q './scripts/productive-k3s.sh bootstrap --dry-run' || fail "make dry-run does not map to bootstrap --dry-run"
pass "make dry-run maps to bootstrap --dry-run"

validate_strict_recipe="$(cd "$REPO_DIR" && make -n validate-strict)"
printf '%s\n' "$validate_strict_recipe" | grep -q './scripts/productive-k3s.sh validate --strict' || fail "make validate-strict does not map to validate --strict"
pass "make validate-strict maps to validate --strict"
