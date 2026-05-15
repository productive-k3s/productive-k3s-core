#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"
PID_FILE="${ROOT_DIR}/.mkdocs.pid"
LOG_FILE="${ROOT_DIR}/.mkdocs.log"

bash "${ROOT_DIR}/sync-shared-theme.sh"

python3 -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
python -m pip install --upgrade pip
python -m pip install -r "${ROOT_DIR}/requirements.txt"

if [[ "${1:-}" == "--background" ]]; then
  if [[ -f "${PID_FILE}" ]]; then
    existing_pid="$(cat "${PID_FILE}")"
    if kill -0 "${existing_pid}" >/dev/null 2>&1; then
      printf '[INFO] MkDocs is already running on http://127.0.0.1:8000 (pid %s)\n' "${existing_pid}"
      exit 0
    fi
    rm -f "${PID_FILE}"
  fi

  nohup mkdocs serve --config-file "${ROOT_DIR}/mkdocs.yml" --dev-addr 127.0.0.1:8000 >"${LOG_FILE}" 2>&1 &
  server_pid="$!"
  printf '%s\n' "${server_pid}" > "${PID_FILE}"
  printf '[INFO] MkDocs started on http://127.0.0.1:8000 (pid %s)\n' "${server_pid}"
  printf '[INFO] Log file: %s\n' "${LOG_FILE}"
  exit 0
fi

mkdocs serve --config-file "${ROOT_DIR}/mkdocs.yml" --dev-addr 127.0.0.1:8000
