#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  printf '%s' "$haystack" | grep -F "$needle" >/dev/null || fail "expected output to contain: $needle"
}

assert_count() {
  local haystack="$1"
  local needle="$2"
  local expected_count="$3"
  local actual_count
  actual_count="$(printf '%s' "$haystack" | grep -F -c "$needle" || true)"
  [[ "$actual_count" == "$expected_count" ]] || fail "expected '$needle' to appear ${expected_count} time(s), got ${actual_count}"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "expected path to be removed: $path"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARTIFACTS_DIR="${TMP_DIR}/test-artifacts"
RUNS_DIR="${TMP_DIR}/runs"
FAKE_BIN_DIR="${TMP_DIR}/bin"
MULTIPASS_LOG="${TMP_DIR}/multipass.log"
mkdir -p "${ARTIFACTS_DIR}" "${RUNS_DIR}/telemetry-outbox" "${FAKE_BIN_DIR}"

cat > "${ARTIFACTS_DIR}/test-in-vm-20260508-000001-core-ubuntu.json" <<'EOF'
{
  "test_type": "vm",
  "profile": "core",
  "platform": "ubuntu",
  "image": "24.04",
  "vm_name": "pk3s-core-ubuntu",
  "status": "success"
}
EOF

cat > "${ARTIFACTS_DIR}/test-in-vm-20260508-000001-core-ubuntu-bootstrap-manifest.json" <<'EOF'
{
  "status": "success"
}
EOF

cat > "${ARTIFACTS_DIR}/test-in-vm-20260508-000001-core-ubuntu-public.json" <<'EOF'
{
  "test_type": "vm",
  "artifact_scope": "public",
  "status": "success"
}
EOF

cat > "${ARTIFACTS_DIR}/test-in-vm-20260508-000002-full-debian12.json" <<'EOF'
{
  "test_type": "vm",
  "profile": "full",
  "platform": "debian12",
  "image": "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2",
  "vm_name": "pk3s-full-debian12",
  "status": "failed"
}
EOF

cat > "${ARTIFACTS_DIR}/hosted-validation-summary.json" <<'EOF'
{
  "test_type": "github-hosted",
  "runner_os": "ubuntu-24.04",
  "status": "success"
}
EOF

printf '{}\n' > "${RUNS_DIR}/bootstrap-20260508-000001.json"
printf '{}\n' > "${RUNS_DIR}/telemetry-outbox/bootstrap-20260508-000001-attempt-1.json"
printf 'delivered\n' > "${RUNS_DIR}/telemetry-outbox/bootstrap-20260508-000001-attempt-1.status"

cat > "${FAKE_BIN_DIR}/multipass" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${MULTIPASS_LOG}"
case "\${1:-}" in
  list)
    cat <<'EOCSV'
Name,State,IPv4,Image
productive-k3s-core-test-smoke-1,Running,10.0.0.10,Ubuntu 24.04 LTS
unrelated-vm,Running,10.0.0.11,Ubuntu 24.04 LTS
EOCSV
    ;;
  delete|purge)
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "${FAKE_BIN_DIR}/multipass"

set +e
status_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  TEST_RUNS_DIR="${RUNS_DIR}" \
  bash "${REPO_DIR}/tests/check-test-status.sh" 2>&1
)"
status_rc=$?
set -e

[[ "$status_rc" -ne 0 ]] || fail "check-test-status should fail when at least one test result is failed"
assert_contains "$status_output" "[OK] vm profile=core platform=ubuntu image=24.04"
assert_contains "$status_output" "[FAIL] vm profile=full platform=debian12"
assert_contains "$status_output" "[OK] github-hosted runner_os=ubuntu-24.04"
assert_contains "$status_output" "Summary: 2 success, 1 failed, 0 unknown"

TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
TEST_RUNS_DIR="${RUNS_DIR}" \
PATH="${FAKE_BIN_DIR}:$PATH" \
bash "${REPO_DIR}/tests/clean-test-state.sh"

assert_not_exists "${ARTIFACTS_DIR}/test-in-vm-20260508-000001-core-ubuntu.json"
assert_not_exists "${ARTIFACTS_DIR}/hosted-validation-summary.json"
assert_not_exists "${RUNS_DIR}/bootstrap-20260508-000001.json"
assert_not_exists "${RUNS_DIR}/telemetry-outbox/bootstrap-20260508-000001-attempt-1.json"
assert_not_exists "${RUNS_DIR}/telemetry-outbox/bootstrap-20260508-000001-attempt-1.status"
assert_contains "$(cat "${MULTIPASS_LOG}")" "list --format csv"
assert_contains "$(cat "${MULTIPASS_LOG}")" "delete productive-k3s-core-test-smoke-1"
assert_contains "$(cat "${MULTIPASS_LOG}")" "purge"

root_clean_recipe="$(make -C "${REPO_DIR}" -n test-clean)"
assert_contains "$root_clean_recipe" "./scripts/productive-k3s-core-dev.sh test-clean"

root_checkstatus_recipe="$(make -C "${REPO_DIR}" -n test-checkstatus)"
assert_contains "$root_checkstatus_recipe" "./scripts/productive-k3s-core-dev.sh test-checkstatus"

matrix_all_recipe="$(make -C "${REPO_DIR}/tests" -n run-all-tests)"
assert_count "$matrix_all_recipe" "bash ./clean-test-state.sh" "1"

matrix_core_recipe="$(make -C "${REPO_DIR}/tests" -n run-core-tests)"
assert_count "$matrix_core_recipe" "bash ./clean-test-state.sh" "1"

printf '[PASS] test artifact tools summarize failures and clean local test state\n'
