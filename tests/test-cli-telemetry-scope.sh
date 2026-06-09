#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

WORK_DIR="${TMP_DIR}/core"
mkdir -p "${WORK_DIR}/scripts"
cp "${ROOT_DIR}/scripts/productive-k3s-core.sh" "${WORK_DIR}/scripts/"
cp "${ROOT_DIR}/scripts/component-versions.sh" "${WORK_DIR}/scripts/"
cp "${ROOT_DIR}/scripts/addons-runtime.sh" "${WORK_DIR}/scripts/"
cat > "${WORK_DIR}/bundle-info.json" <<'EOF'
{
  "schema_version": "1",
  "bundle_name": "productive-k3s-core",
  "bundle_type": "productive-k3s-core",
  "bundle_version": "test",
  "cli_entrypoint": "productive-k3s-core.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF

SENDER_MARKER="${TMP_DIR}/sender-called"
cat > "${WORK_DIR}/scripts/send-telemetry-event.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "${SENDER_MARKER}"
EOF
chmod +x "${WORK_DIR}/scripts/send-telemetry-event.sh"

ensure_not_called() {
  local command="$1"
  shift
  rm -f "${SENDER_MARKER}"
  TELEMETRY_ENABLED=true bash "${WORK_DIR}/scripts/productive-k3s-core.sh" "${command}" "$@" >/dev/null
  [[ ! -e "${SENDER_MARKER}" ]] || fail "telemetry sender unexpectedly called for: ${command} $*"
}

ensure_not_called help
ensure_not_called bundle info --json
ensure_not_called bom --json
pass "non-mutating core CLI commands do not emit telemetry"

ADDON_DIR="${TMP_DIR}/addon"
mkdir -p "${ADDON_DIR}/scripts"
cat > "${ADDON_DIR}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: telemetry-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
cat > "${ADDON_DIR}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${ADDON_DIR}/scripts/install.sh"
ADDON_TGZ="${TMP_DIR}/telemetry-addon.tgz"
tar -czf "${ADDON_TGZ}" -C "${ADDON_DIR}" .
HOME_DIR="${TMP_DIR}/home"
mkdir -p "${HOME_DIR}/.kube"
printf 'apiVersion: v1\nkind: Config\ncurrent-context: default\n' > "${HOME_DIR}/.kube/k3s.yaml"

rm -f "${SENDER_MARKER}"
HOME="${HOME_DIR}" TELEMETRY_ENABLED=true TELEMETRY_SESSION_ID=test-session TELEMETRY_RUN_ID=test-run bash "${WORK_DIR}/scripts/productive-k3s-core.sh" addon install --tgz "${ADDON_TGZ}" >/dev/null
[[ -e "${SENDER_MARKER}" ]] || fail "telemetry sender was not called for addon install"
pass "mutating core addon install emits telemetry"

rm -f "${SENDER_MARKER}"
HOME="${HOME_DIR}" TELEMETRY_ENABLED=true TELEMETRY_SESSION_ID=test-session bash "${WORK_DIR}/scripts/productive-k3s-core.sh" addon install --tgz "${ADDON_TGZ}" >/dev/null
[[ -e "${SENDER_MARKER}" ]] || fail "telemetry sender was not called for addon install without run id"
pass "mutating core addon install tolerates missing telemetry run id"
