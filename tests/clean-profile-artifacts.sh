#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"

PROFILE="${1:-}"

if [[ -z "${PROFILE}" ]]; then
  printf 'Usage: %s <profile>\n' "$0" >&2
  exit 1
fi

if [[ ! -d "${ARTIFACTS_DIR}" ]]; then
  printf '[INFO] No artifact directory found for profile cleanup: %s\n' "${ARTIFACTS_DIR}"
  exit 0
fi

find "${ARTIFACTS_DIR}" -maxdepth 1 -type f \
  \( -name "test-in-vm-*-${PROFILE}-*.json" -o -name "test-in-vm-*-${PROFILE}-*-public.json" -o -name "test-in-vm-*-${PROFILE}-*-apply-manifest.json" \) \
  -delete

printf '[INFO] Cleared local test artifacts for profile %s from %s\n' "${PROFILE}" "${ARTIFACTS_DIR}"
