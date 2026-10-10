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
  local output
  if output="$(pk3s_validate_core_compatibility "${MANIFEST}" addon 0.1.0 "$1" 2>&1)"; then
    echo "[FAIL] compatibility case unexpectedly succeeded: $2" >&2
    exit 1
  fi
  printf '%s\n' "${output}" | grep -Fq "$3" || {
    printf '[FAIL] compatibility case returned the wrong diagnosis: %s\n%s\n' "$2" "${output}" >&2
    exit 1
  }
}

write_manifest artifact/v1 0.9.6 0.10.0
pk3s_validate_core_compatibility "${MANIFEST}" addon 0.1.0 0.9.6
expect_rejected 0.9.5 too-old 'requires Core >=0.9.6 and <0.10.0'
expect_rejected 0.10.0 too-new 'requires Core >=0.9.6 and <0.10.0'

write_manifest artifact/v2 0.9.6 0.10.0
expect_rejected 0.9.6 unknown-contract 'requires supported Core contract artifact/v1'
write_manifest artifact/v1 0.9 0.10.0
expect_rejected 0.9.6 malformed-version 'invalid Core version window'
write_manifest artifact/v1 0.10.0 0.9.6
expect_rejected 0.9.6 empty-window 'invalid Core version window'
write_manifest artifact/v1 '' 0.10.0
expect_rejected 0.9.6 missing-field 'invalid Core version window'
write_manifest artifact/v1 0.9.6 0.10.0
expect_rejected development invalid-running-version 'running Core version is not comparable'
write_manifest_without_distros
expect_rejected 0.9.6 missing-distros 'spec.compatibility.requires.kubernetes.distros is required'
write_manifest_with_distro unsupported
expect_rejected 0.9.6 unsupported-distro 'unsupported Kubernetes distro declaration unsupported'
write_manifest_with_distro rke2
PRODUCTIVE_K3S_DISTRO=k3s expect_rejected 0.9.6 disallowed-distro 'Kubernetes distro k3s is not in the declared compatibility set'

printf '[PASS] Core runtime compatibility rejects invalid and unsupported contracts\n'
