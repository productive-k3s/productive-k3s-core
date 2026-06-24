#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${REPO_DIR}/test-artifacts"
SUMMARY_JSON="${ARTIFACTS_DIR}/hosted-validation-summary.json"
HOST_FULL_LOG="${ARTIFACTS_DIR}/hosted-bootstrap-full.log"
HOST_VALIDATE_LOG="${ARTIFACTS_DIR}/hosted-validate-strict.log"
HOST_CLEAN_LOG="${ARTIFACTS_DIR}/hosted-clean.log"
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOST_BOOTSTRAP_STATUS="not-run"
HOST_VALIDATE_STATUS="not-run"
HOST_CLEAN_STATUS="not-run"
OVERALL_STATUS="failed"
HOST_MANIFEST_PATH=""
ADDONS_REPO_DIR_IS_TEMP=0

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1" >&2
    exit 1
  }
}

resolve_addons_repo_dir() {
  if [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" && -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/addons" ]]; then
    printf '%s\n' "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}"
    return 0
  fi

  local sibling_dir
  sibling_dir="$(cd "${REPO_DIR}/.." && pwd)/productive-k3s-addons"
  if [[ -d "${sibling_dir}/addons" ]]; then
    printf '%s\n' "${sibling_dir}"
    return 0
  fi

  return 1
}

prepare_addons_repo_dir() {
  local resolved_dir
  if resolved_dir="$(resolve_addons_repo_dir)"; then
    ADDONS_REPO_DIR_IS_TEMP=0
    printf '%s\n' "${resolved_dir}"
    return 0
  fi

  local repo_url repo_ref temp_dir
  repo_url="${PRODUCTIVE_K3S_ADDONS_REPO_URL:-https://github.com/productive-k3s/productive-k3s-addons.git}"
  repo_ref="${PRODUCTIVE_K3S_ADDONS_REPO_REF:-development}"
  temp_dir="$(mktemp -d)"
  git clone --depth 1 --branch "${repo_ref}" "${repo_url}" "${temp_dir}" >/dev/null 2>&1
  ADDONS_REPO_DIR_IS_TEMP=1
  printf '%s\n' "${temp_dir}"
}

json_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

latest_run_manifest() {
  find "${REPO_DIR}/runs" -maxdepth 1 -type f -name 'bootstrap-*.json' 2>/dev/null | sort | tail -n 1
}

copy_latest_manifest() {
  HOST_MANIFEST_PATH="$(latest_run_manifest || true)"
  if [[ -n "$HOST_MANIFEST_PATH" ]]; then
    cp "$HOST_MANIFEST_PATH" "${ARTIFACTS_DIR}/$(basename "$HOST_MANIFEST_PATH")"
  fi
}

write_summary() {
  cat > "$SUMMARY_JSON" <<EOF
{
  "test_type": "github-hosted",
  "runner_os": "ubuntu-24.04",
  "timestamp": "${RUN_TIMESTAMP}",
  "status": "$(json_escape "$OVERALL_STATUS")",
  "checks": {
    "shell_syntax": "success",
    "host_bootstrap_full": "$(json_escape "$HOST_BOOTSTRAP_STATUS")",
    "host_validate_strict": "$(json_escape "$HOST_VALIDATE_STATUS")",
    "host_clean": "$(json_escape "$HOST_CLEAN_STATUS")"
  },
  "artifacts": {
    "host_bootstrap_full_log": "$(json_escape "$HOST_FULL_LOG")",
    "host_validate_strict_log": "$(json_escape "$HOST_VALIDATE_LOG")",
    "host_clean_log": "$(json_escape "$HOST_CLEAN_LOG")",
    "host_manifest": "$(json_escape "$HOST_MANIFEST_PATH")"
  }
}
EOF
}

cleanup_and_write_summary() {
  local exit_code="${1:-0}"
  copy_latest_manifest
  if [[ "$HOST_BOOTSTRAP_STATUS" == "success" && "$HOST_CLEAN_STATUS" == "not-run" ]]; then
    echo "[INFO] Running best-effort cleanup after partial hosted validation"
    local confirm=$'y\nCLEAN\n'
    if printf '%s' "$confirm" | ./scripts/cleanup.sh --apply >"$HOST_CLEAN_LOG" 2>&1; then
      HOST_CLEAN_STATUS="success"
    else
      HOST_CLEAN_STATUS="failed"
    fi
  fi
  write_summary
  exit "$exit_code"
}

run_validate_with_retries() {
  local timeout_secs="${1:-900}"
  local sleep_secs="${2:-15}"
  local start_ts now_ts
  start_ts=$(date +%s)

  : > "$HOST_VALIDATE_LOG"

  while true; do
    set +e
    bash ./scripts/validate.sh --strict > >(tee -a "$HOST_VALIDATE_LOG") 2>&1
    local rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi

    now_ts=$(date +%s)
    if (( now_ts - start_ts >= timeout_secs )); then
      echo "[ERROR] Hosted validation did not converge within ${timeout_secs}s" | tee -a "$HOST_VALIDATE_LOG"
      return 1
    fi

    echo "[INFO] Hosted validation is not clean yet; waiting ${sleep_secs}s before retrying" | tee -a "$HOST_VALIDATE_LOG"
    sleep "$sleep_secs"
  done
}

main() {
  mkdir -p "$ARTIFACTS_DIR"
  trap 'cleanup_and_write_summary $?' EXIT

  need_cmd bash
  need_cmd jq
  need_cmd git

  cd "$REPO_DIR"
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="$(prepare_addons_repo_dir)"
  export PRODUCTIVE_K3S_ADDONS_REPO_DIR
  if [[ "${ADDONS_REPO_DIR_IS_TEMP:-0}" == "1" ]]; then
    trap 'rm -rf "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}"; cleanup_and_write_summary $?' EXIT
  fi

  echo "[INFO] Checking shell syntax"
  bash -n scripts/apply.sh
  bash -n scripts/send-telemetry.sh
  bash -n tests/test-in-vm.sh
  bash -n scripts/rollback.sh
  bash -n scripts/cleanup.sh
  bash ./tests/test-telemetry-consent.sh

  echo "[INFO] Running hosted full bootstrap on ubuntu-24.04"
  local answers
  answers=$'y
y
y
y
y
y
y


y
home.arpa





n
2



y
y
y
y
y
y
y
'
  if ! printf '%s' "$answers" | ./scripts/apply.sh | tee "$HOST_FULL_LOG"; then
    HOST_BOOTSTRAP_STATUS="failed"
    return 1
  fi
  HOST_BOOTSTRAP_STATUS="success"

  copy_latest_manifest

  echo "[INFO] Running strict validation on hosted ubuntu-24.04"
  if ! run_validate_with_retries 900 15; then
    HOST_VALIDATE_STATUS="failed"
    return 1
  fi
  HOST_VALIDATE_STATUS="success"

  echo "[INFO] Running destructive cleanup on hosted ubuntu-24.04"
  local confirm=$'y\nCLEAN\n'
  if ! printf '%s' "$confirm" | ./scripts/cleanup.sh --apply | tee "$HOST_CLEAN_LOG"; then
    HOST_CLEAN_STATUS="failed"
    return 1
  fi
  HOST_CLEAN_STATUS="success"

  OVERALL_STATUS="success"
  echo "[INFO] Hosted validation completed successfully"
  echo "[INFO] Summary written to: $SUMMARY_JSON"
}

main "$@"
