#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

need_cmd shellspec

cd "${REPO_DIR}"
mapfile -t spec_files < <(find tests/spec -maxdepth 1 -type f -name '*_spec.sh' | sort)
exec shellspec --chdir "${REPO_DIR}" -s bash "${spec_files[@]}"
