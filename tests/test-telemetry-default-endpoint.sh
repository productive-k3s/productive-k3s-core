#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/bootstrap-k3s-stack.sh"
TELEMETRY_SCRIPT="${ROOT_DIR}/scripts/send-telemetry.sh"
EVENT_SCRIPT="${ROOT_DIR}/scripts/send-telemetry-event.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

CANONICAL_ENDPOINT="https://telemetry.productive-k3s.io/telemetry"
DEFAULT_MARKER="pk3s-public-v1"

assert_equals() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '[FAIL] %s\nexpected: %s\nactual:   %s\n' "${label}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! rg -q "${pattern}" "${file}"; then
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
url=""
marker=""
authz=""
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "--data-binary" ]]; then
    payload="${arg#@}"
  elif [[ "${prev}" == "--header" && "${arg}" == X-Productive-K3S-Telemetry:* ]]; then
    marker="${arg#X-Productive-K3S-Telemetry: }"
  elif [[ "${prev}" == "--header" && "${arg}" == Authorization:\ Bearer* ]]; then
    authz="${arg#Authorization: }"
  fi
  prev="${arg}"
  url="${arg}"
done

printf '%s' "${url}" > "${REQUESTS_DIR}/url-${count}.txt"
printf '%s' "${marker}" > "${REQUESTS_DIR}/marker-${count}.txt"
printf '%s' "${authz}" > "${REQUESTS_DIR}/authz-${count}.txt"
cp "${payload}" "${REQUESTS_DIR}/request-${count}.json"
EOF
chmod +x "${TMP_DIR}/bin/curl"

export PATH="${TMP_DIR}/bin:${PATH}"
export FAKE_CURL_COUNT_FILE="${TMP_DIR}/curl-count"
export FAKE_CURL_REQUESTS_DIR="${TMP_DIR}/requests"
printf '0' > "${FAKE_CURL_COUNT_FILE}"

cat > "${TMP_DIR}/manifest.json" <<'EOF'
{
  "schema_version": "1",
  "status": "success"
}
EOF

cat > "${TMP_DIR}/event.json" <<'EOF'
{
  "schema_version": "1",
  "event_family": "usage",
  "event_name": "core.command.completed"
}
EOF

unset TELEMETRY_ENDPOINT
export TELEMETRY_MAX_RETRIES="1"
export TELEMETRY_CONNECT_TIMEOUT_SECONDS="1"
export TELEMETRY_REQUEST_TIMEOUT_SECONDS="1"
export TELEMETRY_OUTBOX_DIR="${TMP_DIR}/outbox"
export TELEMETRY_RUN_ID="core-run-default-endpoint"
export TELEMETRY_BEARER_TOKEN="pk3s_live_core_default_test"

bash "${TELEMETRY_SCRIPT}" "${TMP_DIR}/manifest.json"
assert_equals "$(cat "${TMP_DIR}/requests/url-1.txt")" "${CANONICAL_ENDPOINT}" "send-telemetry.sh should use the canonical telemetry endpoint by default"
assert_equals "$(cat "${TMP_DIR}/requests/marker-1.txt")" "${DEFAULT_MARKER}" "send-telemetry.sh should send the default telemetry marker"
assert_equals "$(cat "${TMP_DIR}/requests/authz-1.txt")" "Bearer pk3s_live_core_default_test" "send-telemetry.sh should send the observability bearer token when configured"

bash "${EVENT_SCRIPT}" "${TMP_DIR}/event.json"
assert_equals "$(cat "${TMP_DIR}/requests/url-2.txt")" "${CANONICAL_ENDPOINT}" "send-telemetry-event.sh should use the canonical telemetry endpoint by default"
assert_equals "$(cat "${TMP_DIR}/requests/marker-2.txt")" "${DEFAULT_MARKER}" "send-telemetry-event.sh should send the default telemetry marker"
assert_equals "$(cat "${TMP_DIR}/requests/authz-2.txt")" "Bearer pk3s_live_core_default_test" "send-telemetry-event.sh should send the observability bearer token when configured"

PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck disable=SC1090
source "${BOOTSTRAP_SCRIPT}"
assert_equals "${TELEMETRY_ENDPOINT}" "${CANONICAL_ENDPOINT}" "bootstrap-k3s-stack.sh should expose the canonical telemetry endpoint by default"

RUN_ID="bootstrap-default-endpoint"
MODE="server"
TELEMETRY_ENABLED="true"
TELEMETRY_MAX_RETRIES="1"
emit_bootstrap_lifecycle_event "started" "started"

assert_equals "$(cat "${TMP_DIR}/requests/url-3.txt")" "${CANONICAL_ENDPOINT}" "bootstrap lifecycle events should be delivered to the canonical telemetry endpoint by default"
assert_equals "$(cat "${TMP_DIR}/requests/marker-3.txt")" "${DEFAULT_MARKER}" "bootstrap lifecycle events should send the default telemetry marker"
assert_equals "$(cat "${TMP_DIR}/requests/authz-3.txt")" "Bearer pk3s_live_core_default_test" "bootstrap lifecycle events should send the observability bearer token when configured"
assert_file_contains "${TMP_DIR}/requests/request-3.json" '"event_name": "core.bootstrap.server.started"'

printf '[PASS] telemetry defaults use the canonical endpoint\n'
