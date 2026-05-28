#!/usr/bin/env bash
# shellcheck disable=SC1090
set -euo pipefail

SCRIPT_PATH="$1"
COMMAND="$2"

PRODUCTIVE_K3S_LIB_ONLY=1 . "${SCRIPT_PATH}"
eval "${COMMAND}"
