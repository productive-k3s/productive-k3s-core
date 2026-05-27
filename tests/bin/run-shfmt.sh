#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

need_cmd shfmt

cd "${REPO_DIR}"
mapfile -t files < <(shell_files)
if ((${#files[@]} == 0)); then
  echo "No shell files found."
  exit 0
fi

exec shfmt -d -i 2 -ci "${files[@]}"
