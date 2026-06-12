#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_PATH="${REPO_DIR}/scripts/addons-runtime.sh"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${WORK_DIR}/productive-k3s-addons/addons/registry/scripts"
mkdir -p "${WORK_DIR}/productive-k3s-addons/stacks/base"
cat >"${WORK_DIR}/productive-k3s-addons/addons/registry/scripts/validate.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${WORK_DIR}/productive-k3s-addons/addons/registry/scripts/validate.sh"
cat >"${WORK_DIR}/productive-k3s-addons/stacks/base/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
  version: 0.1.0
spec:
  addons:
    - cert-manager
    - registry
EOF

output="$(
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${WORK_DIR}/productive-k3s-addons" \
  bash -c 'source "'"${LIB_PATH}"'"; resolve_addons_repo_dir'
)"
[[ "${output}" == "${WORK_DIR}/productive-k3s-addons" ]] || fail "did not resolve addons repo from PRODUCTIVE_K3S_ADDONS_REPO_DIR"
pass "addons runtime resolves explicit addons repo"

mkdir -p "${WORK_DIR}/env/productive-k3s-core/scripts"
cp "${LIB_PATH}" "${WORK_DIR}/env/productive-k3s-core/scripts/addons-runtime.sh"
mkdir -p "${WORK_DIR}/env/productive-k3s-addons/addons/registry/scripts"
cp "${WORK_DIR}/productive-k3s-addons/addons/registry/scripts/validate.sh" "${WORK_DIR}/env/productive-k3s-addons/addons/registry/scripts/validate.sh"
output="$(
  bash -c 'SCRIPT_DIR="'"${WORK_DIR}"'/env/productive-k3s-core/scripts"; source "'"${WORK_DIR}"'/env/productive-k3s-core/scripts/addons-runtime.sh"; resolve_addons_repo_dir'
)"
[[ "${output}" == "${WORK_DIR}/env/productive-k3s-addons" ]] || fail "did not resolve addons repo from sibling checkout"
pass "addons runtime resolves sibling addons repo"

if ! PRODUCTIVE_K3S_ADDONS_REPO_DIR="${WORK_DIR}/productive-k3s-addons" \
  bash -c 'source "'"${LIB_PATH}"'"; addon_source_script_exists registry validate.sh'; then
  fail "registry validate script was not detected"
fi
pass "addons runtime detects addon scripts"

stack_addons="$(
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${WORK_DIR}/productive-k3s-addons" \
  bash -c 'source "'"${LIB_PATH}"'"; stack_source_addon_names base'
)"
[[ "${stack_addons}" == $'cert-manager\nregistry' ]] || fail "did not resolve stack addon order from stack.yaml"
pass "addons runtime resolves stack addon order"

mkdir -p "${WORK_DIR}/productive-k3s-addons/stacks/observability"
cat >"${WORK_DIR}/productive-k3s-addons/stacks/observability/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: observability
  version: 1.0.0
spec:
  addons:
    - name: prometheus
      version: 1.2.0
      source: addons/prometheus.tgz
    - name: grafana
      version: 2.1.0
EOF

stack_records="$(
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${WORK_DIR}/productive-k3s-addons" \
  bash -c 'source "'"${LIB_PATH}"'"; stack_source_addon_records observability'
)"
printf '%s\n' "${stack_records}" | grep -q 'name=prometheus' || fail "did not parse structured stack addon name"
printf '%s\n' "${stack_records}" | grep -q 'source=addons/prometheus.tgz' || fail "did not parse bundled stack addon source"
printf '%s\n' "${stack_records}" | grep -q 'name=grafana' || fail "did not parse second structured stack addon"
pass "addons runtime parses structured stack addon records"

structured_stack_addons="$(
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${WORK_DIR}/productive-k3s-addons" \
  bash -c 'source "'"${LIB_PATH}"'"; stack_source_addon_names observability'
)"
[[ "${structured_stack_addons}" == $'prometheus\ngrafana' ]] || fail "did not normalize structured stack addon names"
pass "addons runtime normalizes structured stack addon names"
