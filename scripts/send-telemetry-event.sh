#!/usr/bin/env bash
set -euo pipefail

EVENT_PATH="${1:-}"
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT-https://telemetry.productive-k3s.io/telemetry}"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"
TELEMETRY_BEARER_TOKEN="${TELEMETRY_BEARER_TOKEN:-}"
TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES:-3}"
TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-5}"
TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-10}"
TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR:-runs/telemetry-outbox}"
TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID:-unknown-run}"

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    warn "Missing required command for telemetry delivery: $1"
    exit 1
  }
}

record_failed_attempt() {
  local payload_path="$1"
  local delivery_attempt="$2"
  local curl_exit="$3"

  mkdir -p "${TELEMETRY_OUTBOX_DIR}"
  cp "${payload_path}" "${TELEMETRY_OUTBOX_DIR}/event-${TELEMETRY_RUN_ID}-attempt-${delivery_attempt}.json"
  {
    printf 'attempt=%s\n' "${delivery_attempt}"
    printf 'curl_exit=%s\n' "${curl_exit}"
    printf 'recorded_at=%s\n' "$(date -Iseconds)"
  } > "${TELEMETRY_OUTBOX_DIR}/event-${TELEMETRY_RUN_ID}-attempt-${delivery_attempt}.status"
}

cleanup_failed_attempts() {
  rm -f "${TELEMETRY_OUTBOX_DIR}/event-${TELEMETRY_RUN_ID}-attempt-"*.json \
    "${TELEMETRY_OUTBOX_DIR}/event-${TELEMETRY_RUN_ID}-attempt-"*.status 2>/dev/null || true
}

main() {
  if [[ -z "${EVENT_PATH}" || ! -f "${EVENT_PATH}" ]]; then
    warn "Telemetry event path is missing or invalid."
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

  local attempt curl_rc
  for (( attempt=1; attempt<=max_attempts; attempt++ )); do
    local curl_args=(
      --silent
      --show-error
      --fail
      --connect-timeout "${TELEMETRY_CONNECT_TIMEOUT_SECONDS}"
      --max-time "${TELEMETRY_REQUEST_TIMEOUT_SECONDS}"
      --retry 0
      --header 'Content-Type: application/json'
      --header "X-Productive-K3S-Telemetry: ${TELEMETRY_MARKER}"
      --data-binary "@${EVENT_PATH}"
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
      log "Telemetry event delivered successfully on attempt ${attempt}/${max_attempts}."
      exit 0
    fi

    record_failed_attempt "${EVENT_PATH}" "${attempt}" "${curl_rc}"
    warn "Telemetry event delivery attempt ${attempt}/${max_attempts} failed with curl exit code ${curl_rc}."
  done

  warn "Telemetry event delivery exhausted ${max_attempts} attempt(s)."
  exit 1
}

main "$@"
