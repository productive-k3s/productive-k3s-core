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

cli_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s-core.sh help)"
root_cli_help="$(cd "$REPO_DIR" && ./productive-k3s-core.sh help)"
printf '%s\n' "$cli_help" | grep -q "bootstrap" || fail "public CLI help does not list bootstrap"
printf '%s\n' "$cli_help" | grep -q "preflight" || fail "public CLI help does not list preflight"
printf '%s\n' "$cli_help" | grep -q "validate" || fail "public CLI help does not list validate"
printf '%s\n' "$cli_help" | grep -q "bundle" || fail "public CLI help does not list bundle"
printf '%s\n' "$root_cli_help" | grep -q "bootstrap" || fail "root public CLI help does not list bootstrap"
pass "public CLI help lists operational commands"

bootstrap_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s-core.sh bootstrap --help)"
printf '%s\n' "$bootstrap_help" | grep -q -- '--dry-run' || fail "bootstrap help was not forwarded"
pass "bootstrap subcommand forwards CLI help"

preflight_help="$(cd "$REPO_DIR" && ./productive-k3s-core.sh preflight --help)"
printf '%s\n' "$preflight_help" | grep -q -- '--mode <single-node|server|agent|stack>' || fail "preflight help was not forwarded"
pass "preflight subcommand forwards CLI help"

validate_help="$(cd "$REPO_DIR" && ./productive-k3s-core.sh validate --help)"
printf '%s\n' "$validate_help" | grep -q -- '--strict' || fail "validate help was not forwarded"
pass "validate subcommand forwards CLI help"

local_bundle_info="$(cd "$REPO_DIR" && ./productive-k3s-core.sh bundle info --json)"
printf '%s\n' "$local_bundle_info" | jq -e '
  .schema_version == "1" and
  .bundle_name == "productive-k3s-core" and
  .bundle_type == "productive-k3s-core" and
  (.bundle_version | type) == "string" and
  (.bundle_version | length) > 0 and
  .cli_entrypoint == "productive-k3s-core.sh" and
  .platform == "any" and
  .api_compatibility.contract == "productive-k3s-cli-bundle-info/v1"
' >/dev/null || fail "local bundle info JSON contract did not match expected values"
pass "local bundle info JSON contract is exposed"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

archive_path="$(cd "$REPO_DIR" && ./scripts/build-release-bundle.sh HEAD "$TMP_DIR")"
extract_dir="${TMP_DIR}/bundle"
mkdir -p "$extract_dir"
tar -xzf "$archive_path" -C "$extract_dir"
bundle_listing="$(tar -tzf "$archive_path")"

bundle_root="${extract_dir}/productive-k3s-core-HEAD"
[[ -x "${bundle_root}/productive-k3s-core.sh" ]] || fail "bundle root entrypoint is missing"
for required_path in \
  "productive-k3s-core-HEAD/bundle-info.json" \
  "productive-k3s-core-HEAD/scripts/productive-k3s-core.sh" \
  "productive-k3s-core-HEAD/scripts/preflight-host.sh" \
  "productive-k3s-core-HEAD/scripts/bootstrap-k3s-stack.sh" \
  "productive-k3s-core-HEAD/scripts/backup-k3s-stack.sh" \
  "productive-k3s-core-HEAD/scripts/validate-k3s-stack.sh" \
  "productive-k3s-core-HEAD/scripts/send-telemetry.sh"
do
  printf '%s\n' "$bundle_listing" | grep -q "^${required_path}$" || fail "bundle release is missing required runtime file: ${required_path}"
done
pass "release bundle includes required runtime files"

bundle_info="$(cd "$bundle_root" && ./productive-k3s-core.sh bundle info --json)"
printf '%s\n' "$bundle_info" | jq -e '
  .schema_version == "1" and
  .bundle_name == "productive-k3s-core" and
  .bundle_type == "productive-k3s-core" and
  .bundle_version == "HEAD" and
  .cli_entrypoint == "productive-k3s-core.sh" and
  .platform == "any" and
  .api_compatibility.contract == "productive-k3s-cli-bundle-info/v1"
' >/dev/null || fail "bundle info JSON contract did not match expected values"
pass "bundle info JSON contract is exposed from the built artifact"

if (cd "$REPO_DIR" && ./productive-k3s-core.sh unsupported >/tmp/productive-k3s-core-cli-unsupported.out 2>&1); then
  fail "unsupported public CLI command unexpectedly succeeded"
fi
grep -q "Unsupported command" /tmp/productive-k3s-core-cli-unsupported.out || fail "unsupported public CLI command message missing"
pass "unsupported public CLI command is rejected"

preflight_recipe="$(cd "$REPO_DIR" && make -n preflight)"
printf '%s\n' "$preflight_recipe" | grep -q './productive-k3s-core.sh preflight' || fail "make preflight does not target public CLI"
pass "make preflight targets public CLI"

preflight_strict_recipe="$(cd "$REPO_DIR" && make -n preflight-strict)"
printf '%s\n' "$preflight_strict_recipe" | grep -q './productive-k3s-core.sh preflight --strict' || fail "make preflight-strict does not map to base command plus flag"
pass "make preflight-strict maps to preflight --strict"

dry_run_recipe="$(cd "$REPO_DIR" && make -n dry-run)"
printf '%s\n' "$dry_run_recipe" | grep -q './productive-k3s-core.sh bootstrap --dry-run' || fail "make dry-run does not map to bootstrap --dry-run"
pass "make dry-run maps to bootstrap --dry-run"

validate_strict_recipe="$(cd "$REPO_DIR" && make -n validate-strict)"
printf '%s\n' "$validate_strict_recipe" | grep -q './productive-k3s-core.sh validate --strict' || fail "make validate-strict does not map to validate --strict"
pass "make validate-strict maps to validate --strict"
