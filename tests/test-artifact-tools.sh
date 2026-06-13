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

cat > "${ARTIFACTS_DIR}/test-in-vm-20260508-000001-core-ubuntu-apply-manifest.json" <<'EOF'
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

cat > "${ARTIFACTS_DIR}/test-local-20260508-000001-test-unit.json" <<'EOF'
{
  "test_type": "local-suite",
  "suite_category": "local",
  "suite": "test-unit",
  "status": "success"
}
EOF

cat > "${ARTIFACTS_DIR}/test-external-20260508-000001-test-telemetry.json" <<'EOF'
{
  "test_type": "external-suite",
  "suite_category": "external",
  "suite": "test-telemetry",
  "status": "failed"
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
  bash "${REPO_DIR}/tests/check-test-status.sh" --category matrix 2>&1
)"
status_rc=$?
set -e

[[ "$status_rc" -ne 0 ]] || fail "check-test-status should fail when at least one test result is failed"
assert_contains "$status_output" "[OK] vm profile=core platform=ubuntu image=24.04"
assert_contains "$status_output" "[FAIL] vm profile=full platform=debian12"
assert_contains "$status_output" "[OK] github-hosted runner_os=ubuntu-24.04"
assert_contains "$status_output" "Summary: 2 success, 1 failed, 0 unknown"

local_status_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  bash "${REPO_DIR}/tests/check-test-status.sh" --category local 2>&1
)"
assert_contains "$local_status_output" "[OK] local suite=test-unit"
assert_contains "$local_status_output" "Summary: 1 success, 0 failed, 0 unknown"

set +e
external_status_output="$(
  TEST_ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
  bash "${REPO_DIR}/tests/check-test-status.sh" --category external 2>&1
)"
external_status_rc=$?
set -e
[[ "$external_status_rc" -ne 0 ]] || fail "external status should fail when one external suite failed"
assert_contains "$external_status_output" "[FAIL] external suite=test-telemetry"
assert_contains "$external_status_output" "Summary: 0 success, 1 failed, 0 unknown"

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

root_clean_artifacts_recipe="$(make -C "${REPO_DIR}" -n test-clean-artifacts)"
assert_contains "$root_clean_artifacts_recipe" "./scripts/productive-k3s-core-dev.sh test-clean-artifacts"

root_clean_vms_recipe="$(make -C "${REPO_DIR}" -n test-clean-vms)"
assert_contains "$root_clean_vms_recipe" "./scripts/productive-k3s-core-dev.sh test-clean-vms"

root_clean_all_recipe="$(make -C "${REPO_DIR}" -n test-clean-all)"
assert_contains "$root_clean_all_recipe" "./scripts/productive-k3s-core-dev.sh test-clean-all"

root_checkstatus_recipe="$(make -C "${REPO_DIR}" -n test-checkstatus)"
assert_contains "$root_checkstatus_recipe" "./scripts/productive-k3s-core-dev.sh test-checkstatus"

root_checkstatus_matrix_recipe="$(make -C "${REPO_DIR}" -n test-checkstatus-matrix)"
assert_contains "$root_checkstatus_matrix_recipe" "./scripts/productive-k3s-core-dev.sh test-checkstatus-matrix"

root_checkstatus_local_recipe="$(make -C "${REPO_DIR}" -n test-checkstatus-local)"
assert_contains "$root_checkstatus_local_recipe" "./scripts/productive-k3s-core-dev.sh test-checkstatus-local"

root_checkstatus_external_recipe="$(make -C "${REPO_DIR}" -n test-checkstatus-external)"
assert_contains "$root_checkstatus_external_recipe" "./scripts/productive-k3s-core-dev.sh test-checkstatus-external"

root_local_all_recipe="$(make -C "${REPO_DIR}" -n test-local-all)"
assert_contains "$root_local_all_recipe" "./scripts/productive-k3s-core-dev.sh test-local-all"

root_external_all_recipe="$(make -C "${REPO_DIR}" -n test-external-all)"
assert_contains "$root_external_all_recipe" "./scripts/productive-k3s-core-dev.sh test-external-all"
assert_contains "$(sed -n '1,260p' "${REPO_DIR}/scripts/productive-k3s-core-dev.sh")" "test-stacks-external"

root_stacks_recipe="$(make -C "${REPO_DIR}" -n test-stacks)"
assert_contains "$root_stacks_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks"

root_stacks_k3s_recipe="$(make -C "${REPO_DIR}" -n test-stacks-k3s)"
assert_contains "$root_stacks_k3s_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-k3s"

root_stacks_rke2_recipe="$(make -C "${REPO_DIR}" -n test-stacks-rke2)"
assert_contains "$root_stacks_rke2_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-rke2"

root_stacks_k3s_ubuntu24_recipe="$(make -C "${REPO_DIR}" -n test-stacks-k3s-ubuntu24)"
assert_contains "$root_stacks_k3s_ubuntu24_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-k3s-ubuntu24"

root_stacks_k3s_ubuntu22_recipe="$(make -C "${REPO_DIR}" -n test-stacks-k3s-ubuntu22)"
assert_contains "$root_stacks_k3s_ubuntu22_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-k3s-ubuntu22"

root_stacks_k3s_debian13_recipe="$(make -C "${REPO_DIR}" -n test-stacks-k3s-debian13)"
assert_contains "$root_stacks_k3s_debian13_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-k3s-debian13"

root_stacks_k3s_debian12_recipe="$(make -C "${REPO_DIR}" -n test-stacks-k3s-debian12)"
assert_contains "$root_stacks_k3s_debian12_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-k3s-debian12"

root_stacks_rke2_ubuntu24_recipe="$(make -C "${REPO_DIR}" -n test-stacks-rke2-ubuntu24)"
assert_contains "$root_stacks_rke2_ubuntu24_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-rke2-ubuntu24"

root_stacks_rke2_ubuntu22_recipe="$(make -C "${REPO_DIR}" -n test-stacks-rke2-ubuntu22)"
assert_contains "$root_stacks_rke2_ubuntu22_recipe" "./scripts/productive-k3s-core-dev.sh test-stacks-rke2-ubuntu22"

root_rke2_core_ubuntu22_recipe="$(make -C "${REPO_DIR}" -n test-rke2-core-ubuntu22)"
assert_contains "$root_rke2_core_ubuntu22_recipe" "./scripts/productive-k3s-core-dev.sh test-rke2-core-ubuntu22"

root_tag_release_recipe="$(make -C "${REPO_DIR}" -n tag-release VERSION=1.2.3)"
assert_contains "$root_tag_release_recipe" "./scripts/create-release-tag.sh 1.2.3"

matrix_all_recipe="$(make -C "${REPO_DIR}/tests" -n run-all-tests)"
assert_count "$matrix_all_recipe" "bash ./clean-test-state.sh" "1"

matrix_core_recipe="$(make -C "${REPO_DIR}/tests" -n run-core-tests)"
assert_count "$matrix_core_recipe" "bash ./clean-test-state.sh" "1"

printf '[PASS] test artifact tools summarize failures and clean local test state\n'
