#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PREFLIGHT_SCRIPT="${REPO_DIR}/scripts/preflight-host.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

make_fake_cmd() {
  local name="$1"
  cat > "${TMP_DIR}/bin/${name}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TMP_DIR}/bin/${name}"
}

run_preflight() {
  env \
    PATH="${TMP_DIR}/bin:${PATH}" \
    PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE="${TMP_DIR}/os-release" \
    PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE="${TMP_DIR}/pid1-comm" \
    PRODUCTIVE_K3S_PREFLIGHT_ARCH="${PRODUCTIVE_K3S_PREFLIGHT_ARCH}" \
    PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT="${PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT}" \
    PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB="${PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB}" \
    PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES="${PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES}" \
    "${PREFLIGHT_SCRIPT}" "$@"
}

mkdir -p "${TMP_DIR}/bin"

for cmd in sudo curl getent apt-get systemctl tar sha256sum mktemp; do
  make_fake_cmd "${cmd}"
done

cat > "${TMP_DIR}/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF

printf 'systemd\n' > "${TMP_DIR}/pid1-comm"

help_output="$("${PREFLIGHT_SCRIPT}" --help)"
printf '%s\n' "${help_output}" | grep -q -- '--mode <single-node|server|agent|stack>' || fail "help does not describe --mode"
printf '%s\n' "${help_output}" | grep -q -- '--strict' || fail "help does not describe --strict"
printf '%s\n' "${help_output}" | grep -q -- '--json-output' || fail "help does not describe --json-output"
pass "help documents the preflight CLI"

if "${PREFLIGHT_SCRIPT}" --mode unsupported >/tmp/productive-k3s-invalid-preflight-mode.out 2>&1; then
  fail "unsupported mode unexpectedly succeeded"
fi
grep -q "Unsupported mode" /tmp/productive-k3s-invalid-preflight-mode.out || fail "unsupported mode error message missing"
pass "unsupported preflight mode is rejected"

PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT=8
PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB=$((16 * 1024 * 1024))
PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES=$((120 * 1024 * 1024 * 1024))
PRODUCTIVE_K3S_PREFLIGHT_ARCH=x86_64
supported_json="$(run_preflight --json-output)"
python3 - "${supported_json}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["mode"] == "single-node"
assert payload["summary"]["fail_count"] == 0
assert payload["summary"]["warn_count"] == 0
assert payload["platform"]["support"] == "supported"
assert payload["platform"]["architecture"] == "x86_64"
PY
pass "supported host passes preflight with zero warnings"

PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT=2
PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB=$((8 * 1024 * 1024))
PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES=$((40 * 1024 * 1024 * 1024))
PRODUCTIVE_K3S_PREFLIGHT_ARCH=x86_64
warning_json="$(run_preflight --json-output)"
python3 - "${warning_json}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["summary"]["fail_count"] == 0
assert payload["summary"]["warn_count"] > 0
PY
pass "resource shortfalls are reported as warnings by default"

if run_preflight --strict >/tmp/productive-k3s-preflight-strict.out 2>&1; then
  fail "strict preflight unexpectedly succeeded with warning-level shortfalls"
fi
grep -q "warnings" /tmp/productive-k3s-preflight-strict.out || fail "strict mode summary did not mention warnings"
pass "strict mode promotes warnings to a failing exit code"

cat > "${TMP_DIR}/os-release" <<'EOF'
ID=fedora
VERSION_ID="41"
PRETTY_NAME="Fedora 41"
EOF
PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT=8
PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB=$((16 * 1024 * 1024))
PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES=$((120 * 1024 * 1024 * 1024))
PRODUCTIVE_K3S_PREFLIGHT_ARCH=x86_64
if run_preflight >/tmp/productive-k3s-preflight-unsupported.out 2>&1; then
  fail "unsupported platform unexpectedly passed preflight"
fi
grep -q "unsupported platform" /tmp/productive-k3s-preflight-unsupported.out || fail "unsupported platform message missing"
pass "unsupported platform is rejected"

cat > "${TMP_DIR}/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
PRODUCTIVE_K3S_PREFLIGHT_ARCH=aarch64
if run_preflight >/tmp/productive-k3s-preflight-unsupported-arch.out 2>&1; then
  fail "unsupported architecture unexpectedly passed preflight"
fi
grep -q "unsupported architecture" /tmp/productive-k3s-preflight-unsupported-arch.out || fail "unsupported architecture message missing"
pass "unsupported architecture is rejected"
