#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/apply.sh"
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

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/requests"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
COUNT_FILE="${FAKE_CURL_COUNT_FILE:?}"
REQUESTS_DIR="${FAKE_CURL_REQUESTS_DIR:?}"
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
EOF
chmod +x "${TMP_DIR}/bin/curl"

export PATH="${TMP_DIR}/bin:${PATH}"
export FAKE_CURL_COUNT_FILE="${TMP_DIR}/curl-count"
export FAKE_CURL_REQUESTS_DIR="${TMP_DIR}/requests"
printf '0' > "${FAKE_CURL_COUNT_FILE}"

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${BOOTSTRAP_SCRIPT}"

MODE="server"
RUN_ID="core-run-123"
TELEMETRY_ENABLED="true"
TELEMETRY_ENDPOINT="https://telemetry.example.invalid/telemetry"
TELEMETRY_MAX_RETRIES="1"
TELEMETRY_SESSION_ID="session-abc"
TELEMETRY_PARENT_RUN_ID="infra-run-xyz"

emit_bootstrap_lifecycle_event "started" "started"
emit_bootstrap_lifecycle_event "completed" "success"

assert_file_contains "${TMP_DIR}/requests/request-1.json" '"event_name": "core.apply.server.started"'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"session_id": "session-abc"'
assert_file_contains "${TMP_DIR}/requests/request-1.json" '"parent_run_id": "infra-run-xyz"'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"event_name": "core.apply.server.completed"'
assert_file_contains "${TMP_DIR}/requests/request-2.json" '"result": "success"'

printf '[PASS] bootstrap telemetry helper emits correlated mode-specific events\n'
