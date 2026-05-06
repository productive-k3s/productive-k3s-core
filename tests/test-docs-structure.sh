#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="${ROOT_DIR}/docs"
SRC_DIR="${DOCS_DIR}/src"
EN_DIR="${SRC_DIR}/en"
ES_DIR="${SRC_DIR}/es"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

[[ -f "${DOCS_DIR}/mkdocs.yml" ]] || fail "missing docs/mkdocs.yml"
[[ -f "${DOCS_DIR}/requirements.txt" ]] || fail "missing docs/requirements.txt"
[[ -f "${SRC_DIR}/index.md" ]] || fail "missing docs/src/index.md"
[[ -d "${EN_DIR}" ]] || fail "missing docs/src/en"
[[ -d "${ES_DIR}" ]] || fail "missing docs/src/es"

tmp_en="$(mktemp)"
tmp_es="$(mktemp)"
trap 'rm -f "${tmp_en}" "${tmp_es}"' EXIT

(
  cd "${EN_DIR}"
  find . -type f -name '*.md' | sort
) > "${tmp_en}"

(
  cd "${ES_DIR}"
  find . -type f -name '*.md' | sort
) > "${tmp_es}"

if ! diff -u "${tmp_en}" "${tmp_es}" >/dev/null; then
  printf '[FAIL] English and Spanish documentation trees differ\n' >&2
  diff -u "${tmp_en}" "${tmp_es}" >&2 || true
  exit 1
fi

printf '[PASS] docs structure and bilingual trees are aligned\n'
