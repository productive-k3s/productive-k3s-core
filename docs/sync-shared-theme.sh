#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_THEME_DIR="${SHARED_THEME_DIR:-${ROOT_DIR}/../.shared/productive-k3s-docs-theme/material-overrides}"

if [[ ! -d "${SHARED_THEME_DIR}" ]]; then
  printf '[ERROR] Shared theme directory not found: %s\n' "${SHARED_THEME_DIR}" >&2
  exit 1
fi

install -d \
  "${ROOT_DIR}/src/overrides/partials" \
  "${ROOT_DIR}/src/assets/stylesheets" \
  "${ROOT_DIR}/src/assets/images"

cp "${SHARED_THEME_DIR}/main.html" "${ROOT_DIR}/src/overrides/main.html"
cp "${SHARED_THEME_DIR}/partials/logo.html" "${ROOT_DIR}/src/overrides/partials/logo.html"
cp "${SHARED_THEME_DIR}/partials/header.html" "${ROOT_DIR}/src/overrides/partials/header.html"
cp "${SHARED_THEME_DIR}/partials/footer.html" "${ROOT_DIR}/src/overrides/partials/footer.html"
cp "${SHARED_THEME_DIR}/partials/toc.html" "${ROOT_DIR}/src/overrides/partials/toc.html"
cp "${SHARED_THEME_DIR}/assets/stylesheets/extra.css" "${ROOT_DIR}/src/assets/stylesheets/extra.css"
cp "${SHARED_THEME_DIR}/assets/images/argentina.png" "${ROOT_DIR}/src/assets/images/argentina.png"
cp "${SHARED_THEME_DIR}/assets/images/productive-k3s-icon-square-0.3x.png" "${ROOT_DIR}/src/assets/images/productive-k3s-icon-square-0.3x.png"
cp "${SHARED_THEME_DIR}/assets/images/favicon.ico" "${ROOT_DIR}/src/assets/images/favicon.ico"
rm -f "${ROOT_DIR}/src/assets/images/productive-k3s-logo-wordmark-horizontal.svg"
