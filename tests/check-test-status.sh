#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1" >&2
    exit 1
  }
}

collect_result_artifacts() {
  [[ -d "${ARTIFACTS_DIR}" ]] || return 0

  find "${ARTIFACTS_DIR}" -maxdepth 1 -type f -name '*.json' \
    ! -name '*-bootstrap-manifest.json' \
    ! -name '*-public.json' \
    -print0 | sort -z
}

format_result_line() {
  local artifact="$1"
  local test_type status
  test_type="$(jq -r '.test_type // empty' "$artifact")"
  status="$(jq -r '.status // empty' "$artifact")"

  [[ -n "$test_type" && -n "$status" ]] || return 0

  case "$test_type" in
    vm)
      local profile platform image
      profile="$(jq -r '.profile // "unknown"' "$artifact")"
      platform="$(jq -r '.platform // "unknown"' "$artifact")"
      image="$(jq -r '.image // "unknown"' "$artifact")"
      printf '%s\tvm profile=%s platform=%s image=%s\t%s\n' "$status" "$profile" "$platform" "$image" "$artifact"
      ;;
    github-hosted)
      local runner_os
      runner_os="$(jq -r '.runner_os // "unknown"' "$artifact")"
      printf '%s\tgithub-hosted runner_os=%s\t%s\n' "$status" "$runner_os" "$artifact"
      ;;
    *)
      printf '%s\t%s file=%s\t%s\n' "$status" "$test_type" "$(basename "$artifact")" "$artifact"
      ;;
  esac
}

main() {
  need_cmd jq

  local results=()
  local artifact line
  while IFS= read -r -d '' artifact; do
    line="$(format_result_line "$artifact")"
    if [[ -n "$line" ]]; then
      results+=("$line")
    fi
  done < <(collect_result_artifacts)

  if (( ${#results[@]} == 0 )); then
    echo "[WARN] No test result artifacts found in ${ARTIFACTS_DIR}" >&2
    exit 1
  fi

  local success_count=0
  local failed_count=0
  local unknown_count=0
  local result status description path prefix

  for result in "${results[@]}"; do
    IFS=$'\t' read -r status description path <<< "$result"
    case "$status" in
      success)
        prefix='[OK]'
        success_count=$((success_count + 1))
        ;;
      failed)
        prefix='[FAIL]'
        failed_count=$((failed_count + 1))
        ;;
      *)
        prefix='[WARN]'
        unknown_count=$((unknown_count + 1))
        ;;
    esac
    printf '%s %s\n' "$prefix" "$description"
  done

  printf 'Summary: %d success, %d failed, %d unknown\n' "$success_count" "$failed_count" "$unknown_count"

  if (( failed_count > 0 || unknown_count > 0 )); then
    exit 1
  fi
}

main "$@"
