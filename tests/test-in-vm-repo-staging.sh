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
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_REPO="${TMP_DIR}/fixture-repo"
mkdir -p "${FIXTURE_REPO}/docs/.venv/bin" "${FIXTURE_REPO}/docs/site" "${FIXTURE_REPO}/runs" "${FIXTURE_REPO}/test-artifacts" "${FIXTURE_REPO}/scripts"
printf '#!/usr/bin/env bash\n' > "${FIXTURE_REPO}/scripts/example.sh"
printf 'hello\n' > "${FIXTURE_REPO}/README.md"
ln -s /usr/bin/python3 "${FIXTURE_REPO}/docs/.venv/bin/python3"
ln -s python3 "${FIXTURE_REPO}/docs/.venv/bin/python"
printf 'built docs\n' > "${FIXTURE_REPO}/docs/site/index.html"
printf '{}\n' > "${FIXTURE_REPO}/runs/bootstrap.json"
printf '{}\n' > "${FIXTURE_REPO}/test-artifacts/test.json"

FIXTURE_ADDONS_REPO="${TMP_DIR}/productive-k3s-addons"
mkdir -p "${FIXTURE_ADDONS_REPO}/scripts"
cat > "${FIXTURE_ADDONS_REPO}/scripts/package-stack.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output=""
while (($#)); do
  case "$1" in
    --stack) shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) exit 2 ;;
  esac
done
revision="$(git -C "$repo_dir" rev-parse HEAD)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
printf 'metadata:\n  sourceRevision: %s\n' "$revision" > "${stage}/stack.yaml"
tar -czf "$output" -C "$stage" stack.yaml
EOF
chmod +x "${FIXTURE_ADDONS_REPO}/scripts/package-stack.sh"
git -C "${FIXTURE_ADDONS_REPO}" init -q
git -C "${FIXTURE_ADDONS_REPO}" config user.name fixture
git -C "${FIXTURE_ADDONS_REPO}" config user.email fixture@example.invalid
git -C "${FIXTURE_ADDONS_REPO}" add scripts/package-stack.sh
git -C "${FIXTURE_ADDONS_REPO}" commit -qm fixture
fixture_revision="$(git -C "${FIXTURE_ADDONS_REPO}" rev-parse HEAD)"
export HOME="${TMP_DIR}/home"
mkdir -p "$HOME"

export PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck source=tests/test-in-vm.sh
source "${REPO_DIR}/tests/test-in-vm.sh"

REPO_DIR="$FIXTURE_REPO"
REPO_NAME="fixture-transfer"
REMOTE_DIR="/home/ubuntu/${REPO_NAME}"

prepare_repo_transfer_dir
staged_repo="$TRANSFER_STAGED_REPO"

[[ -f "${staged_repo}/README.md" ]] || fail "staged repo is missing tracked content"
[[ -f "${staged_repo}/scripts/example.sh" ]] || fail "staged repo is missing scripts content"
[[ ! -e "${staged_repo}/docs/.venv" ]] || fail "staged repo unexpectedly contains docs/.venv"
[[ ! -e "${staged_repo}/docs/site" ]] || fail "staged repo unexpectedly contains docs/site"
[[ ! -e "${staged_repo}/runs" ]] || fail "staged repo unexpectedly contains runs"
[[ ! -e "${staged_repo}/test-artifacts" ]] || fail "staged repo unexpectedly contains test-artifacts"
pass "repo staging excludes local-only directories before VM transfer"

ADDONS_REPO_DIR="$FIXTURE_ADDONS_REPO"
prepare_stack_artifact
[[ -s "$LOCAL_STACK_TGZ" ]] || fail "stack artifact was not created on the host"
stack_manifest="$(tar -xOzf "$LOCAL_STACK_TGZ" stack.yaml)"
[[ "$stack_manifest" == *"sourceRevision: ${fixture_revision}"* ]] || fail "stack artifact does not preserve the immutable Addons revision"
[[ -z "${TRANSFER_STAGED_ADDONS_REPO+x}" ]] || fail "Addons source staging remains part of the VM harness"
pass "VM harness packages the stack on the host with immutable provenance"

transfer_log="${TMP_DIR}/multipass.log"
multipass() {
  printf '%s\n' "$*" >> "$transfer_log"
}
VM_NAME="fixture-vm"
REMOTE_USER="ubuntu"
copy_repo
grep -Fq "transfer ${LOCAL_STACK_TGZ} ${VM_NAME}:${REMOTE_STACK_TGZ}" "$transfer_log" || fail "stack artifact was not transferred to the VM"
if grep -Fq "productive-k3s-addons" "$transfer_log"; then
  fail "Addons source was unexpectedly transferred to the VM"
fi
pass "VM transfer contains the packaged stack and no Addons source checkout"
