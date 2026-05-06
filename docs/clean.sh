#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${ROOT_DIR}/.mkdocs.pid"
LOG_FILE="${ROOT_DIR}/.mkdocs.log"

if [[ -f "${PID_FILE}" ]]; then
  existing_pid="$(cat "${PID_FILE}")"
  if kill -0 "${existing_pid}" >/dev/null 2>&1; then
    kill "${existing_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${PID_FILE}"
fi

rm -rf "${ROOT_DIR}/site" "${ROOT_DIR}/.venv"
rm -f "${LOG_FILE}"
