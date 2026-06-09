#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '[PASS] %s\n' "$1"
}

help_output="$(cd "$REPO_DIR" && ./scripts/apply.sh --help)"
printf '%s\n' "$help_output" | grep -q -- '--mode <single-node|server|agent|stack>' || fail "help does not describe --mode"
pass "help documents --mode"

if (cd "$REPO_DIR" && ./scripts/apply.sh --mode unsupported >/tmp/productive-k3s-invalid-mode.out 2>&1); then
  fail "unsupported mode unexpectedly succeeded"
fi
grep -q "Unsupported mode" /tmp/productive-k3s-invalid-mode.out || fail "unsupported mode error message missing"
pass "unsupported mode is rejected"

if (cd "$REPO_DIR" && PRODUCTIVE_K3S_ENGINE=unsupported ./scripts/apply.sh --dry-run >/tmp/productive-k3s-invalid-engine.out 2>&1); then
  fail "unsupported engine unexpectedly succeeded"
fi
grep -q "Unsupported k3s installation engine" /tmp/productive-k3s-invalid-engine.out || fail "unsupported engine error message missing"
pass "unsupported engine is rejected"

agent_answers=$'y\nhttps://server.example.local:6443\nchange-me-token\ny\n'
mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${TMP_DIR}/bin/sudo"
cat > "${TMP_DIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
chmod +x "${TMP_DIR}/bin/systemctl"
agent_output="$(cd "$REPO_DIR" && printf '%s' "$agent_answers" | PATH="${TMP_DIR}/bin:${PATH}" PRODUCTIVE_K3S_ENGINE=k3sup ./scripts/apply.sh --dry-run --mode agent 2>&1)" || {
  printf '%s\n' "$agent_output" >&2
  fail "k3sup dry-run agent bootstrap failed"
}
printf '%s\n' "$agent_output" | grep -q "k3s installation engine: k3sup" || fail "engine banner missing from dry-run output"
pass "k3sup engine banner is reported"
