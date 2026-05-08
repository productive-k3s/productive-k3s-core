#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"
RUNS_DIR="${TEST_RUNS_DIR:-${REPO_DIR}/runs}"

rm -rf "${ARTIFACTS_DIR}"
rm -f "${RUNS_DIR}"/bootstrap-*.json
rm -f "${RUNS_DIR}"/telemetry-outbox/bootstrap-*.json
rm -f "${RUNS_DIR}"/telemetry-outbox/bootstrap-*.status

printf '[INFO] Cleared local test state from %s and %s\n' "${ARTIFACTS_DIR}" "${RUNS_DIR}"
