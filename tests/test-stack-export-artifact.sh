#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

STACK_PKG_DIR="${TMP_DIR}/stack-pkg"
STACK_ARCHIVE="${TMP_DIR}/observability-stack.tgz"
EXPORT_DIR="${TMP_DIR}/exported-stack"
APPLY_CAPTURE="${TMP_DIR}/apply-capture.txt"

mkdir -p "${STACK_PKG_DIR}/addons"
cat > "${STACK_PKG_DIR}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: observability
  version: 1.0.0
spec:
  resolution:
    mode: bundled
  addons:
    - name: prometheus
      source: addons/prometheus.tgz
EOF
printf 'placeholder' > "${STACK_PKG_DIR}/addons/prometheus.tgz"
tar -czf "${STACK_ARCHIVE}" -C "${STACK_PKG_DIR}" .

(
  cd "${REPO_DIR}" &&
  env -u PRODUCTIVE_K3S_ADDONS_REPO_DIR ./productive-k3s-core.sh stack export --tgz "${STACK_ARCHIVE}" --output "${EXPORT_DIR}"
)

cat > "${EXPORT_DIR}/scripts/apply.sh" <<EOF
#!/usr/bin/env bash
printf 'stack=%s repo=%s bundled=%s args=%s\n' "\${PRODUCTIVE_K3S_STACK_NAME:-}" "\${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" "\${PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR:-}" "\$*" > "${APPLY_CAPTURE}"
EOF
chmod +x "${EXPORT_DIR}/scripts/apply.sh"

(
  cd "${EXPORT_DIR}" &&
  [[ -f AGENTS.md ]] &&
  [[ -x preflight.sh ]] &&
  env -u PRODUCTIVE_K3S_ADDONS_REPO_DIR ./install.sh --skip-preflight --dry-run
)

[[ -f "${APPLY_CAPTURE}" ]] || fail "exported bundle did not invoke the bundled apply runtime"
grep -q 'stack=observability' "${APPLY_CAPTURE}" || fail "exported bundle did not preserve the packaged stack name"
grep -q -- '--mode stack --dry-run' "${APPLY_CAPTURE}" || fail "exported bundle did not replay stack install through bundled apply"
grep -q 'bundled=.*bundled-addons' "${APPLY_CAPTURE}" || fail "exported bundle did not expose bundled addons during replay"
pass "exported stack bundle replays locally without a preinstalled Productive K3S CLI"
