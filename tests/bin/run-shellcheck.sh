#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

need_cmd shellcheck

cd "${REPO_DIR}"
mapfile -t files < <(shell_files)
if ((${#files[@]} == 0)); then
  echo "No shell files found."
  exit 0
fi

exec shellcheck -x -e SC1091 "${files[@]}"
