#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/compatibility-runtime.sh"

trim_yaml_value() {
  local value="$1"
  value="${value#*:}"
  printf '%s' "${value# }"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
MANIFEST="${TMP_DIR}/addon.yaml"

write_manifest() {
  local contract="$1" minimum="$2" maximum="$3"
  cat >"${MANIFEST}" <<EOF
spec:
  compatibility:
    requires:
      core:
        contract: ${contract}
        minVersion: ${minimum}
        maxVersionExclusive: ${maximum}
      kubernetes:
        distros:
          - k3s
          - rke2
EOF
}

write_manifest_without_distros() {
  cat >"${MANIFEST}" <<'EOF'
spec:
  compatibility:
    requires:
      core:
        contract: artifact/v1
        minVersion: 0.9.6
        maxVersionExclusive: 0.10.0
EOF
}

write_manifest_with_distro() {
  local distro="$1"
  write_manifest artifact/v1 0.9.6 0.10.0
  sed -i '/          - rke2/d' "${MANIFEST}"
  sed -i "s/          - k3s/          - ${distro}/" "${MANIFEST}"
}

expect_rejected() {
  if pk3s_validate_core_compatibility "${MANIFEST}" addon 0.1.0 "$1"; then
    echo "[FAIL] compatibility case unexpectedly succeeded: $2" >&2
    exit 1
  fi
}

write_manifest artifact/v1 0.9.6 0.10.0
pk3s_validate_core_compatibility "${MANIFEST}" addon 0.1.0 0.9.6
expect_rejected 0.9.5 too-old
expect_rejected 0.10.0 too-new

write_manifest artifact/v2 0.9.6 0.10.0
expect_rejected 0.9.6 unknown-contract
write_manifest artifact/v1 0.9 0.10.0
expect_rejected 0.9.6 malformed-version
write_manifest artifact/v1 0.10.0 0.9.6
expect_rejected 0.9.6 empty-window
write_manifest artifact/v1 '' 0.10.0
expect_rejected 0.9.6 missing-field
write_manifest artifact/v1 0.9.6 0.10.0
expect_rejected development invalid-running-version
write_manifest_without_distros
expect_rejected 0.9.6 missing-distros
write_manifest_with_distro unsupported
expect_rejected 0.9.6 unsupported-distro
write_manifest_with_distro rke2
PRODUCTIVE_K3S_DISTRO=k3s expect_rejected 0.9.6 disallowed-distro

printf '[PASS] Core runtime compatibility rejects invalid and unsupported contracts\n'
