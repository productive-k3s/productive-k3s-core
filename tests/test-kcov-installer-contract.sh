#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
INSTALLER="${TESTS_DIR}/bin/install-kcov.sh"
WORKFLOW="${REPO_DIR}/.github/workflows/hosted-validation.yml"
DOCS_WORKFLOW="${REPO_DIR}/.github/workflows/docs.yml"
MATERIALS_LOCK="${REPO_DIR}/materials.lock.yaml"

grep -Fq 'KCOV_VERSION="43"' "${INSTALLER}"
grep -Fq 'KCOV_SHA256="4cbba86af11f72de0c7514e09d59c7927ed25df7cebdad087f6d3623213b95bf"' "${INSTALLER}"
grep -Fq 'CI_PYTHON_VERSION="3.11.17"' "${INSTALLER}"
grep -Fq "bash tests/bin/install-kcov.sh" "${WORKFLOW}"
grep -Fq 'python-version: "3.11.17"' "${WORKFLOW}"
grep -Fq 'python-version: "3.11.17"' "${DOCS_WORKFLOW}"
grep -Fq '    - id: python-ci' "${MATERIALS_LOCK}"
grep -Fq '    - id: kcov' "${MATERIALS_LOCK}"
grep -Fq '        source-archive: sha256:4cbba86af11f72de0c7514e09d59c7927ed25df7cebdad087f6d3623213b95bf' "${MATERIALS_LOCK}"
[[ "$(grep -Fc '      distribution: excluded' "${MATERIALS_LOCK}")" -ge 2 ]]

if grep -Eq 'apt-get install[^[:cntrl:]]*kcov' "${WORKFLOW}"; then
  printf 'The workflow must install kcov through the pinned repository installer.\n' >&2
  exit 1
fi

printf 'kcov installer contract: ok\n'
