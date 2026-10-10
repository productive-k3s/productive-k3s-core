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

ADDONS_REPO="${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}"
[[ -n "$ADDONS_REPO" && -d "$ADDONS_REPO/.git" ]] || fail "PRODUCTIVE_K3S_ADDONS_REPO_DIR must reference an isolated Git checkout"
[[ -z "$(git -C "$ADDONS_REPO" status --porcelain --untracked-files=normal)" ]] || fail "Addons checkout must be clean"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
STACK_TGZ="${TMP_DIR}/base.tgz"
EXPORT_DIR="${TMP_DIR}/exported-base"
APPLY_CAPTURE="${TMP_DIR}/apply-capture.txt"

bash "${ADDONS_REPO}/scripts/package-stack.sh" --stack base --output "$STACK_TGZ"
expected_revision="$(git -C "$ADDONS_REPO" rev-parse HEAD)"
stack_manifest="$(tar -xOzf "$STACK_TGZ" ./stack.yaml)"
[[ "$stack_manifest" == *"sourceRevision: ${expected_revision}"* ]] || fail "stack sourceRevision does not match the Addons checkout"
[[ "$stack_manifest" == *"contract: artifact/v1"* ]] || fail "stack does not declare Core artifact/v1"
[[ "$stack_manifest" == *"minVersion: 0.9.6"* ]] || fail "stack does not declare the expected Core compatibility floor"

env -u PRODUCTIVE_K3S_ADDONS_REPO_DIR TELEMETRY_ENABLED=false \
  "${REPO_DIR}/productive-k3s-core.sh" stack export --tgz "$STACK_TGZ" --output "$EXPORT_DIR" >/dev/null

cat >"${EXPORT_DIR}/scripts/apply.sh" <<EOF
#!/usr/bin/env bash
printf 'repo=%s\nbundled=%s\nargs=%s\n' \
  "\${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" \
  "\${PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR:-}" \
  "\$*" > "${APPLY_CAPTURE}"
EOF
chmod +x "${EXPORT_DIR}/scripts/apply.sh"

(
  cd "$EXPORT_DIR"
  env -u PRODUCTIVE_K3S_ADDONS_REPO_DIR TELEMETRY_ENABLED=false \
    ./install.sh --skip-preflight --dry-run >/dev/null
)

overlay_repo="$(sed -n 's/^repo=//p' "$APPLY_CAPTURE")"
[[ -n "$overlay_repo" ]] || fail "Core did not synthesize an artifact overlay"
grep -q '^bundled=.*bundled-addons' "$APPLY_CAPTURE" || fail "Core did not expose bundled add-on artifacts"
grep -q '^args=--mode stack --dry-run' "$APPLY_CAPTURE" || fail "dry-run was not delegated through the packaged stack runtime"
if grep -Fq "$ADDONS_REPO" "$APPLY_CAPTURE"; then
  fail "packaged stack execution fell back to the Addons source checkout"
fi

pass "real base artifact satisfies Core metadata, digest, compatibility, and source-independence contracts"
