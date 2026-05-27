#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TESTS_DIR}/artifacts"
COVERAGE_DIR="${TESTS_DIR}/coverage"
# shellcheck disable=SC2034
SPELL_ALLOWLIST="${TESTS_DIR}/spell/allowlist.txt"

mkdir -p "${ARTIFACTS_DIR}" "${COVERAGE_DIR}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 127
  }
}

shell_files() {
  (
    cd "${REPO_DIR}"
    rg --files tests/bin tests/helpers -g '*.sh'
  )
}

spell_files() {
  (
    cd "${REPO_DIR}"
    rg --files README.md scripts tests docs/src/en -g '*.md' -g '*.sh' \
      -g '!tests/artifacts/**' \
      -g '!tests/coverage/**' \
      -g '!tests/bin/run-spellcheck.sh'
  )
}
