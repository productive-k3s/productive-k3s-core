#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if command -v multipass >/dev/null 2>&1; then
  bash "${REPO_DIR}/tests/test-in-vm-cleanup.sh" --all --purge
else
  printf '[INFO] multipass not found; skipping VM cleanup\n'
fi
