#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/apply.sh"
TELEMETRY_SCRIPT="${ROOT_DIR}/scripts/send-telemetry.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

search_file() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q -- "${pattern}" "${file}"
  else
    grep -Eq -- "${pattern}" "${file}"
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! search_file "${pattern}" "${file}"; then
    printf '[FAIL] expected %s to contain %s\n' "${file}" "${pattern}" >&2
    exit 1
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    printf '[FAIL] expected %s to be absent\n' "${path}" >&2
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    printf '[FAIL] expected %s to exist\n' "${path}" >&2
    exit 1
  fi
}

fake_curl_script() {
  local behavior="$1"
  cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

COUNT_FILE="${FAKE_CURL_COUNT_FILE:?}"
REQUESTS_DIR="${FAKE_CURL_REQUESTS_DIR:?}"
BEHAVIOR="${FAKE_CURL_BEHAVIOR:?}"

count=0
if [[ -f "${COUNT_FILE}" ]]; then
  count="$(cat "${COUNT_FILE}")"
fi
count=$((count + 1))
printf '%s' "${count}" > "${COUNT_FILE}"

payload=""
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "--data-binary" ]]; then
    payload="${arg#@}"
    break
  fi
  prev="${arg}"
done

cp "${payload}" "${REQUESTS_DIR}/request-${count}.json"

case "${BEHAVIOR}" in
  fail-twice-then-pass)
    if (( count < 3 )); then
      exit 22
    fi
    ;;
  always-fail)
    exit 22
    ;;
  always-pass)
    ;;
  *)
    exit 99
    ;;
esac
EOF
  chmod +x "${TMP_DIR}/bin/curl"
  export FAKE_CURL_BEHAVIOR="${behavior}"
}

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/requests"
export FAKE_CURL_COUNT_FILE="${TMP_DIR}/curl-count"
export FAKE_CURL_REQUESTS_DIR="${TMP_DIR}/requests"

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${BOOTSTRAP_SCRIPT}"

RUNS_DIR="${TMP_DIR}/runs"
TELEMETRY_OUTBOX_DIR="${TMP_DIR}/outbox"
RUN_STATUS="success"
CURRENT_STEP="completed"
manifest_set_setting "bootstrap_mode" "single-node"
manifest_set_setting "host_os_id" "ubuntu"
manifest_set_setting "host_os_version_id" "24.04"
manifest_set_setting "telemetry_enabled" "y"
manifest_record_component "k3s" "missing" "install"
manifest_complete_component "k3s" "installed"
init_run_manifest
write_run_manifest 0

export PATH="${TMP_DIR}/bin:${PATH}"
export TELEMETRY_ENDPOINT="https://telemetry.example.invalid/ingest"
export TELEMETRY_USER_AGENT="productive-k3s/test"
export TELEMETRY_OUTBOX_DIR
export TELEMETRY_RUN_ID="${RUN_ID}"
export TELEMETRY_SOURCE_REPOSITORY="productive-k3s"
export TELEMETRY_SOURCE_SCRIPT="scripts/apply.sh"
export TELEMETRY_EXIT_CODE="0"
export TELEMETRY_ENABLED="true"
export TELEMETRY_SESSION_ID="session-123"
export TELEMETRY_PARENT_RUN_ID="parent-456"
export TELEMETRY_COMPONENT="infra"
export TELEMETRY_CONNECT_TIMEOUT_SECONDS="1"
export TELEMETRY_REQUEST_TIMEOUT_SECONDS="1"

printf '0' > "${FAKE_CURL_COUNT_FILE}"
fake_curl_script "fail-twice-then-pass"
export TELEMETRY_MAX_RETRIES="3"
bash "${TELEMETRY_SCRIPT}" "${RUN_MANIFEST}"

assert_file_contains "${TMP_DIR}/requests/request-1.json" '"delivery_attempt": 1'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"retry_attempt": 0'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"is_retry": false'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"delivery_attempt": 2'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"retry_attempt": 1'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"is_retry": true'
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"delivery_attempt": 3'
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"retry_attempt": 2'
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"event_name": "apply.completed"'
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"session_id": "session-123"'
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"parent_run_id": "parent-456"'
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"component": "infra"'
assert_file_not_exists "${TELEMETRY_OUTBOX_DIR}/bootstrap-${RUN_ID}-attempt-1.json"

printf '0' > "${FAKE_CURL_COUNT_FILE}"
rm -f "${TMP_DIR}/requests"/request-*.json
fake_curl_script "always-fail"
if bash "${TELEMETRY_SCRIPT}" "${RUN_MANIFEST}"; then
  printf '[FAIL] telemetry sender unexpectedly succeeded during permanent failure\n' >&2
  exit 1
fi
assert_file_exists "${TELEMETRY_OUTBOX_DIR}/bootstrap-${RUN_ID}-attempt-1.json"
assert_file_exists "${TELEMETRY_OUTBOX_DIR}/bootstrap-${RUN_ID}-attempt-2.json"
assert_file_exists "${TELEMETRY_OUTBOX_DIR}/bootstrap-${RUN_ID}-attempt-3.json"

printf '%s\n' '#!/usr/bin/env bash' 'touch "'"${TMP_DIR}/unexpected-send"'"' > "${TMP_DIR}/send-telemetry.sh"
chmod +x "${TMP_DIR}/send-telemetry.sh"

TELEMETRY_ENABLED="false"
if ! maybe_send_telemetry 0; then
  printf '[FAIL] disabled telemetry should be a no-op\n' >&2
  exit 1
fi
assert_file_not_exists "${TMP_DIR}/unexpected-send"

TELEMETRY_ENABLED="true"
TELEMETRY_ENDPOINT=""
if ! maybe_send_telemetry 0; then
  printf '[FAIL] missing endpoint should not fail bootstrap telemetry wrapper\n' >&2
  exit 1
fi
assert_file_not_exists "${TMP_DIR}/unexpected-send"

TELEMETRY_ENDPOINT="https://telemetry.example.invalid/ingest"
TELEMETRY_COMPONENT="infra"
printf '0' > "${FAKE_CURL_COUNT_FILE}"
rm -f "${TMP_DIR}/requests"/request-*.json
fake_curl_script "always-pass"
if ! maybe_send_telemetry 0; then
  printf '[FAIL] bootstrap telemetry wrapper should succeed when sender succeeds\n' >&2
  exit 1
fi
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"component": "core"'

printf '[PASS] telemetry delivery retries and bootstrap wrapper behavior are correct\n'
