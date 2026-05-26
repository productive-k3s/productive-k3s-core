#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq "${needle}" "${path}" || fail "expected ${path} to contain: ${needle}"
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${path}"; then
    fail "did not expect ${path} to contain: ${needle}"
  fi
}

assert_contains "${ROOT_DIR}/docs/src/en/product/supported-platforms.md" "Ubuntu \`24.04\` LTS on \`arm64\`"
assert_contains "${ROOT_DIR}/docs/src/es/product/supported-platforms.md" "Ubuntu \`24.04\` LTS sobre \`arm64\`"
assert_contains "${ROOT_DIR}/docs/src/en/user-docs/arm-support.md" "Raspberry Pi 5 Model B Rev \`1.1\`"
assert_contains "${ROOT_DIR}/docs/src/es/user-docs/arm-support.md" "Raspberry Pi 5 Model B Rev \`1.1\`"
assert_contains "${ROOT_DIR}/docs/src/en/user-docs/index.md" "[ARM Support](arm-support.md)"
assert_contains "${ROOT_DIR}/docs/src/es/user-docs/index.md" "[ARM Support](arm-support.md)"
assert_contains "${ROOT_DIR}/docs/mkdocs.yml" "ARM Support: en/user-docs/arm-support.md"
assert_contains "${ROOT_DIR}/docs/mkdocs.yml" "ARM Support: es/user-docs/arm-support.md"
assert_contains "${ROOT_DIR}/docs/src/en/developer-docs/ubuntu-24-04-supported.md" "Ubuntu \`24.04\` Desktop on \`arm64\`"
assert_contains "${ROOT_DIR}/docs/src/es/developer-docs/ubuntu-24-04-supported.md" "Ubuntu \`24.04\` Desktop sobre \`arm64\`"
assert_not_contains "${ROOT_DIR}/docs/src/en/user-docs/host-preflight.md" "unsupported on purpose"
assert_not_contains "${ROOT_DIR}/docs/src/es/user-docs/host-preflight.md" "intencionalmente no soportado"

printf '[PASS] ARM support documentation is published in docs and nav\n'
