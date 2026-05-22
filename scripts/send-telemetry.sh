#!/usr/bin/env bash
set -euo pipefail

MANIFEST_PATH="${1:-}"
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT-https://telemetry.productive-k3s.io/telemetry}"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"
TELEMETRY_BEARER_TOKEN="${TELEMETRY_BEARER_TOKEN:-}"
TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES:-3}"
TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-5}"
TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-10}"
TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR:-runs/telemetry-outbox}"
TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT:-productive-k3s/dev}"
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-false}"
TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID:-unknown-run}"
TELEMETRY_SOURCE_REPOSITORY="${TELEMETRY_SOURCE_REPOSITORY:-productive-k3s}"
TELEMETRY_SOURCE_SCRIPT="${TELEMETRY_SOURCE_SCRIPT:-scripts/bootstrap-k3s-stack.sh}"
TELEMETRY_EXIT_CODE="${TELEMETRY_EXIT_CODE:-0}"
TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-}"
TELEMETRY_PARENT_RUN_ID="${TELEMETRY_PARENT_RUN_ID:-}"
TELEMETRY_COMPONENT="${TELEMETRY_COMPONENT:-core}"

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1" >&2
}

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e ':a;N;$!ba;s/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    warn "Missing required command for telemetry delivery: $1"
    exit 1
  }
}

write_payload() {
  local payload_path="$1"
  local delivery_attempt="$2"
  local retry_attempt="$3"
  local is_retry="$4"

  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "event_family": "install",\n'
    printf '  "event_name": "bootstrap.completed",\n'
    printf '  "sent_at": "%s",\n' "$(json_escape "$(date -Iseconds)")"
    printf '  "delivery_attempt": %s,\n' "${delivery_attempt}"
    printf '  "retry_attempt": %s,\n' "${retry_attempt}"
    printf '  "is_retry": %s,\n' "${is_retry}"
    printf '  "retry_of_run_id": "%s",\n' "$(json_escape "${TELEMETRY_RUN_ID}")"
    printf '  "session_id": %s,\n' "$(jq -Rn --arg v "${TELEMETRY_SESSION_ID}" '$v')"
    printf '  "run_id": %s,\n' "$(jq -Rn --arg v "${TELEMETRY_RUN_ID}" '$v')"
    printf '  "parent_run_id": %s,\n' "$(jq -Rn --arg v "${TELEMETRY_PARENT_RUN_ID}" '$v')"
    printf '  "component": %s,\n' "$(jq -Rn --arg v "${TELEMETRY_COMPONENT}" '$v')"
    printf '  "client": {\n'
    printf '    "repository": "%s",\n' "$(json_escape "${TELEMETRY_SOURCE_REPOSITORY}")"
    printf '    "script": "%s",\n' "$(json_escape "${TELEMETRY_SOURCE_SCRIPT}")"
    printf '    "user_agent": "%s",\n' "$(json_escape "${TELEMETRY_USER_AGENT}")"
    printf '    "telemetry_enabled": "%s",\n' "$(json_escape "${TELEMETRY_ENABLED}")"
    printf '    "exit_code": %s\n' "${TELEMETRY_EXIT_CODE}"
    printf '  },\n'
    printf '  "manifest": '
    cat "${MANIFEST_PATH}"
    printf ',\n'
    printf '  "telemetry_meta": {\n'
    printf '    "delivery_mode": "best-effort",\n'
    printf '    "anonymous_by_contract": true\n'
    printf '  }\n'
    printf '}\n'
  } > "${payload_path}"
}

record_failed_attempt() {
  local payload_path="$1"
  local delivery_attempt="$2"
  local curl_exit="$3"

  mkdir -p "${TELEMETRY_OUTBOX_DIR}"
  cp "${payload_path}" "${TELEMETRY_OUTBOX_DIR}/bootstrap-${TELEMETRY_RUN_ID}-attempt-${delivery_attempt}.json"
  {
    printf 'attempt=%s\n' "${delivery_attempt}"
    printf 'curl_exit=%s\n' "${curl_exit}"
    printf 'recorded_at=%s\n' "$(date -Iseconds)"
  } > "${TELEMETRY_OUTBOX_DIR}/bootstrap-${TELEMETRY_RUN_ID}-attempt-${delivery_attempt}.status"
}

cleanup_failed_attempts() {
  rm -f "${TELEMETRY_OUTBOX_DIR}/bootstrap-${TELEMETRY_RUN_ID}-attempt-"*.json \
    "${TELEMETRY_OUTBOX_DIR}/bootstrap-${TELEMETRY_RUN_ID}-attempt-"*.status 2>/dev/null || true
}

main() {
  if [[ -z "${MANIFEST_PATH}" || ! -f "${MANIFEST_PATH}" ]]; then
    warn "Telemetry manifest path is missing or invalid."
    exit 1
  fi

  if [[ -z "${TELEMETRY_ENDPOINT}" ]]; then
    warn "Telemetry endpoint is not configured."
    exit 1
  fi

  need_cmd curl

  local max_attempts="${TELEMETRY_MAX_RETRIES}"
  if [[ ! "${max_attempts}" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
    warn "Invalid TELEMETRY_MAX_RETRIES value '${TELEMETRY_MAX_RETRIES}'. Falling back to 3 total attempts."
    max_attempts=3
  fi

  local attempt retry_attempt is_retry payload_file curl_rc
  for (( attempt=1; attempt<=max_attempts; attempt++ )); do
    retry_attempt=$((attempt - 1))
    if (( attempt == 1 )); then
      is_retry=false
    else
      is_retry=true
    fi

    payload_file="$(mktemp)"
    write_payload "${payload_file}" "${attempt}" "${retry_attempt}" "${is_retry}"

    local curl_args=(
      --silent
      --show-error
      --fail
      --connect-timeout "${TELEMETRY_CONNECT_TIMEOUT_SECONDS}"
      --max-time "${TELEMETRY_REQUEST_TIMEOUT_SECONDS}"
      --retry 0
      --header 'Content-Type: application/json'
      --header "User-Agent: ${TELEMETRY_USER_AGENT}"
      --header "X-Productive-K3S-Telemetry: ${TELEMETRY_MARKER}"
      --data-binary "@${payload_file}"
    )
    if [[ -n "${TELEMETRY_BEARER_TOKEN}" ]]; then
      curl_args+=(--header "Authorization: Bearer ${TELEMETRY_BEARER_TOKEN}")
    fi
    set +e
    curl "${curl_args[@]}" "${TELEMETRY_ENDPOINT}" >/dev/null
    curl_rc=$?
    set -e

    if [[ "${curl_rc}" == "0" ]]; then
      cleanup_failed_attempts
      rm -f "${payload_file}"
      log "Telemetry delivered successfully on attempt ${attempt}/${max_attempts}."
      exit 0
    fi

    record_failed_attempt "${payload_file}" "${attempt}" "${curl_rc}"
    rm -f "${payload_file}"
    warn "Telemetry delivery attempt ${attempt}/${max_attempts} failed with curl exit code ${curl_rc}."
  done

  warn "Telemetry delivery exhausted ${max_attempts} attempt(s)."
  exit 1
}

main "$@"
