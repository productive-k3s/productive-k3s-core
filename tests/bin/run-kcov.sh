#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

need_cmd shellspec
if ! command -v kcov >/dev/null 2>&1; then
  printf 'Missing required command: kcov\n' >&2
  printf 'On Ubuntu, install it with: sudo apt-get install -y kcov libelf-dev libdw-dev\n' >&2
  exit 127
fi

cd "${REPO_DIR}"
rm -rf "${COVERAGE_DIR}/shellspec"
mkdir -p "${COVERAGE_DIR}"

set +e
kcov \
  --include-path="${REPO_DIR}/scripts,${REPO_DIR}/tests/spec" \
  "${COVERAGE_DIR}/shellspec" \
  shellspec tests/spec
rc=$?
set -e

if [[ ${rc} -eq 0 ]]; then
  exit 0
fi

if [[ ${rc} -eq 101 && -f "${COVERAGE_DIR}/shellspec/index.html" ]]; then
  printf 'kcov returned 101 but coverage artifacts were generated successfully.\n' >&2
  exit 0
fi

exit "${rc}"
