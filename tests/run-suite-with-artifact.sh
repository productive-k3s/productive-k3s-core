#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"

usage() {
  cat <<'EOF'
Usage: ./tests/run-suite-with-artifact.sh <local|external> <suite-name> <command> [args...]
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[ERROR] Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

write_artifact() {
  local suite_category="$1"
  local suite_name="$2"
  local status="$3"
  local started_at="$4"
  local finished_at="$5"
  local duration_seconds="$6"
  local command_json="$7"
  local artifact_path="$8"

  cat > "${artifact_path}" <<EOF
{
  "test_type": "${suite_category}-suite",
  "artifact_scope": "private",
  "suite_category": "${suite_category}",
  "suite": "${suite_name}",
  "status": "${status}",
  "started_at": "${started_at}",
  "finished_at": "${finished_at}",
  "duration_seconds": ${duration_seconds},
  "command": ${command_json}
}
EOF
}

main() {
  [[ $# -ge 3 ]] || {
    usage >&2
    exit 2
  }

  local suite_category="$1"
  local suite_name="$2"
  shift 2

  case "${suite_category}" in
    local|external)
      ;;
    *)
      printf '[ERROR] Unsupported suite category: %s\n' "${suite_category}" >&2
      usage >&2
      exit 2
      ;;
  esac

  need_cmd jq
  mkdir -p "${ARTIFACTS_DIR}"

  local timestamp started_at finished_at started_epoch finished_epoch duration_seconds status command_json artifact_path
  timestamp="$(date -u '+%Y%m%d-%H%M%S')"
  artifact_path="${ARTIFACTS_DIR}/test-${suite_category}-${timestamp}-${suite_name}.json"
  started_epoch="$(date +%s)"
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  command_json="$(printf '%s\n' "$@" | jq -Rsc 'split("\n")[:-1]')"
  status="success"

  if ! "$@"; then
    status="failed"
  fi

  finished_epoch="$(date +%s)"
  finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  duration_seconds="$((finished_epoch - started_epoch))"

  write_artifact \
    "${suite_category}" \
    "${suite_name}" \
    "${status}" \
    "${started_at}" \
    "${finished_at}" \
    "${duration_seconds}" \
    "${command_json}" \
    "${artifact_path}"

  if [[ "${status}" != "success" ]]; then
    exit 1
  fi
}

main "$@"
