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

cli_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s-core.sh help)"
root_cli_help="$(cd "$REPO_DIR" && ./productive-k3s-core.sh help)"
printf '%s\n' "$cli_help" | grep -q "bootstrap" || fail "public CLI help does not list bootstrap"
printf '%s\n' "$cli_help" | grep -q "preflight" || fail "public CLI help does not list preflight"
printf '%s\n' "$cli_help" | grep -q "validate" || fail "public CLI help does not list validate"
printf '%s\n' "$cli_help" | grep -q "bundle" || fail "public CLI help does not list bundle"
printf '%s\n' "$root_cli_help" | grep -q "bootstrap" || fail "root public CLI help does not list bootstrap"
pass "public CLI help lists operational commands"

bootstrap_help="$(cd "$REPO_DIR" && ./scripts/productive-k3s-core.sh bootstrap --help)"
printf '%s\n' "$bootstrap_help" | grep -q -- '--dry-run' || fail "bootstrap help was not forwarded"
pass "bootstrap subcommand forwards CLI help"

preflight_help="$(cd "$REPO_DIR" && ./productive-k3s-core.sh preflight --help)"
printf '%s\n' "$preflight_help" | grep -q -- '--mode <single-node|server|agent|stack>' || fail "preflight help was not forwarded"
pass "preflight subcommand forwards CLI help"

validate_help="$(cd "$REPO_DIR" && ./productive-k3s-core.sh validate --help)"
printf '%s\n' "$validate_help" | grep -q -- '--strict' || fail "validate help was not forwarded"
pass "validate subcommand forwards CLI help"

printf '%s\n' "$cli_help" | grep -q "addon" || fail "public CLI help does not list addon"
pass "public CLI help lists addon commands"

local_bundle_info="$(cd "$REPO_DIR" && ./productive-k3s-core.sh bundle info --json)"
printf '%s\n' "$local_bundle_info" | jq -e '
  .schema_version == "1" and
  .bundle_name == "productive-k3s-core" and
  .bundle_type == "productive-k3s-core" and
  (.bundle_version | type) == "string" and
  (.bundle_version | length) > 0 and
  .cli_entrypoint == "productive-k3s-core.sh" and
  .platform == "any" and
  .api_compatibility.contract == "productive-k3s-cli-bundle-info/v1"
' >/dev/null || fail "local bundle info JSON contract did not match expected values"
pass "local bundle info JSON contract is exposed"

local_bom="$(cd "$REPO_DIR" && ./productive-k3s-core.sh bom --json)"
printf '%s\n' "$local_bom" | jq -e '
  .schema_version == "1" and
  .bom_type == "productive-k3s-cli-bom/v1" and
  .cli.name == "productive-k3s-core" and
  (.cli.version | type) == "string" and
  (.cli.version | length) > 0 and
  .cli.entrypoint == "productive-k3s-core.sh" and
  .implementation.language == "bash" and
  .bundle.bundle_name == "productive-k3s-core" and
  .bundle.api_compatibility.contract == "productive-k3s-cli-bundle-info/v1" and
  (.platform_support.supported_matrix | any(.os == "ubuntu-24.04" and (.architectures | index("arm64") != null))) and
  (.platform_support.retained_validation_evidence.arm64 | index("ubuntu-24.04")) != null and
  (.requirements.required_commands | any(.name == "bash" and .min_version == "5.1")) and
  (.requirements.required_commands | any(.name == "curl" and .min_version == "7.81")) and
  (.requirements.required_commands | any(.name == "tar" and .min_version == "1.34")) and
  (.requirements.required_commands | any(.name == "sha256sum" and .min_version == "8.32")) and
  (.requirements.optional_commands | any(.name == "helm" and .min_version == "3.21.0")) and
  .components.versions.k3s == "v1.35.5+k3s1" and
  .components.versions.helm == "v3.21.0" and
  .components.versions["cert-manager"] == "v1.19.4" and
  .components.versions.longhorn == "v1.11.1" and
  .components.versions.rancher == "v2.14.2" and
  .components.versions.registry_image == "registry:2.8.3" and
  (.components.managed | index("k3s")) != null and
  (.components.managed | index("helm")) != null and
  (.components.managed | index("cert-manager")) != null and
  (.components.managed | index("longhorn")) != null and
  (.components.managed | index("rancher")) != null and
  (.components.managed | index("registry")) != null and
  (.components.managed | index("nfs")) != null
' >/dev/null || fail "local bom JSON contract did not match expected values"
pass "local bom JSON contract is exposed"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

archive_path="$(cd "$REPO_DIR" && ./scripts/build-release-bundle.sh HEAD "$TMP_DIR")"
extract_dir="${TMP_DIR}/bundle"
mkdir -p "$extract_dir"
tar -xzf "$archive_path" -C "$extract_dir"
bundle_listing="$(tar -tzf "$archive_path")"

bundle_root="${extract_dir}/productive-k3s-core-HEAD"
[[ -x "${bundle_root}/productive-k3s-core.sh" ]] || fail "bundle root entrypoint is missing"
for required_path in \
  "productive-k3s-core-HEAD/bundle-info.json" \
  "productive-k3s-core-HEAD/README.md" \
  "productive-k3s-core-HEAD/LICENSE" \
  "productive-k3s-core-HEAD/scripts/productive-k3s-core.sh" \
  "productive-k3s-core-HEAD/scripts/component-versions.sh" \
  "productive-k3s-core-HEAD/scripts/preflight-host.sh" \
  "productive-k3s-core-HEAD/scripts/bootstrap-k3s-stack.sh" \
  "productive-k3s-core-HEAD/scripts/backup-k3s-stack.sh" \
  "productive-k3s-core-HEAD/scripts/validate-k3s-stack.sh" \
  "productive-k3s-core-HEAD/scripts/send-telemetry.sh" \
  "productive-k3s-core-HEAD/scripts/send-telemetry-event.sh"
do
  printf '%s\n' "$bundle_listing" | grep -q "^${required_path}$" || fail "bundle release is missing required runtime file: ${required_path}"
done
pass "release bundle includes required runtime files"

for omitted_path in \
  "productive-k3s-core-HEAD/docs/" \
  "productive-k3s-core-HEAD/tests/" \
  "productive-k3s-core-HEAD/scripts/productive-k3s-core-dev.sh" \
  "productive-k3s-core-HEAD/scripts/build-release-bundle.sh" \
  "productive-k3s-core-HEAD/CHANGELOG.md"
do
  printf '%s\n' "$bundle_listing" | grep -q "^${omitted_path}" && fail "bundle release should omit non-runtime path: ${omitted_path}"
done
pass "release bundle omits docs, tests, and dev-only files"

bundle_info="$(cd "$bundle_root" && ./productive-k3s-core.sh bundle info --json)"
printf '%s\n' "$bundle_info" | jq -e '
  .schema_version == "1" and
  .bundle_name == "productive-k3s-core" and
  .bundle_type == "productive-k3s-core" and
  .bundle_version == "HEAD" and
  .cli_entrypoint == "productive-k3s-core.sh" and
  .platform == "any" and
  .api_compatibility.contract == "productive-k3s-cli-bundle-info/v1"
' >/dev/null || fail "bundle info JSON contract did not match expected values"
pass "bundle info JSON contract is exposed from the built artifact"

bundle_bom="$(cd "$bundle_root" && ./productive-k3s-core.sh bom --json)"
printf '%s\n' "$bundle_bom" | jq -e '
  .cli.name == "productive-k3s-core" and
  .bundle.bundle_version == "HEAD"
' >/dev/null || fail "bundle bom JSON contract did not match expected values"
pass "bom JSON contract is exposed from the built artifact"

ADDON_TMP_DIR="$(mktemp -d)"
ADDON_PKG_DIR="${ADDON_TMP_DIR}/pkg"
ADDON_ARCHIVE="${ADDON_TMP_DIR}/demo-addon.tgz"
ADDON_MARKER="${ADDON_TMP_DIR}/installed.txt"
ADDON_KUBECONFIG="${ADDON_TMP_DIR}/kubeconfig"
ADDON_INGRESS_CAPTURE="${ADDON_TMP_DIR}/ingress.yaml"
ADDON_BIN_DIR="${ADDON_TMP_DIR}/bin"
mkdir -p "${ADDON_PKG_DIR}/scripts"
mkdir -p "${ADDON_BIN_DIR}"
printf 'apiVersion: v1\nkind: Config\ncurrent-context: default\n' > "${ADDON_KUBECONFIG}"
cat >"${ADDON_PKG_DIR}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: demo-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
  productiveK3s:
    exposure:
      public:
        mode: ingress
        namespace: demo-addon
        service:
          name: demo-addon
          port: 80
EOF
cat >"${ADDON_PKG_DIR}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf 'installed\n' >"${ADDON_MARKER}"
EOF
chmod +x "${ADDON_PKG_DIR}/scripts/install.sh"
cat >"${ADDON_BIN_DIR}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *"get ingress -A -o jsonpath="* ]]; then
  exit 0
fi
if [[ "\$*" == *"apply -f -"* ]]; then
  cat >"${ADDON_INGRESS_CAPTURE}"
  exit 0
fi
printf 'unexpected kubectl invocation: %s\n' "\$*" >&2
exit 1
EOF
chmod +x "${ADDON_BIN_DIR}/kubectl"
tar -czf "${ADDON_ARCHIVE}" -C "${ADDON_PKG_DIR}" .

addon_validate_output="$(cd "$REPO_DIR" && ./productive-k3s-core.sh addon validate --tgz "${ADDON_ARCHIVE}")"
printf '%s\n' "$addon_validate_output" | grep -q "Addon package validation passed" || fail "addon package validation did not pass"
printf '%s\n' "$addon_validate_output" | grep -q "demo-addon" || fail "addon validation did not report addon metadata"
pass "addon tgz validation works"

(cd "$REPO_DIR" && ./productive-k3s-core.sh addon install --tgz "${ADDON_ARCHIVE}" --kubeconfig "${ADDON_KUBECONFIG}")
[[ -f "${ADDON_MARKER}" ]] || fail "addon install did not execute the packaged installer"
pass "addon tgz install executes packaged installer"

(
  cd "$REPO_DIR"
  PATH="${ADDON_BIN_DIR}:$PATH" ./productive-k3s-core.sh addon install --tgz "${ADDON_ARCHIVE}" --kubeconfig "${ADDON_KUBECONFIG}" --public-host demo.k3s.lab.internal
)
[[ -f "${ADDON_INGRESS_CAPTURE}" ]] || fail "addon public install did not apply ingress manifest"
grep -q "host: demo.k3s.lab.internal" "${ADDON_INGRESS_CAPTURE}" || fail "public ingress host missing from applied manifest"
grep -q "name: demo-addon" "${ADDON_INGRESS_CAPTURE}" || fail "public ingress service name missing from applied manifest"
grep -q "number: 80" "${ADDON_INGRESS_CAPTURE}" || fail "public ingress service port missing from applied manifest"
pass "addon tgz install can publish a basic ingress"

ADDON_NO_PUBLIC_PKG_DIR="${ADDON_TMP_DIR}/pkg-no-public"
ADDON_NO_PUBLIC_ARCHIVE="${ADDON_TMP_DIR}/demo-addon-no-public.tgz"
mkdir -p "${ADDON_NO_PUBLIC_PKG_DIR}/scripts"
cat >"${ADDON_NO_PUBLIC_PKG_DIR}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: demo-addon-no-public
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
cat >"${ADDON_NO_PUBLIC_PKG_DIR}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${ADDON_NO_PUBLIC_PKG_DIR}/scripts/install.sh"
tar -czf "${ADDON_NO_PUBLIC_ARCHIVE}" -C "${ADDON_NO_PUBLIC_PKG_DIR}" .
if (
  cd "$REPO_DIR" &&
  PATH="${ADDON_BIN_DIR}:$PATH" ./productive-k3s-core.sh addon install --tgz "${ADDON_NO_PUBLIC_ARCHIVE}" --kubeconfig "${ADDON_KUBECONFIG}" --public-host demo-no-public.k3s.lab.internal >/tmp/productive-k3s-core-addon-public.out 2>&1
); then
  fail "addon install with public host unexpectedly succeeded for addon without public ingress metadata"
fi
grep -q "does not declare basic public ingress exposure support" /tmp/productive-k3s-core-addon-public.out || fail "missing public ingress validation message"
pass "addon tgz install rejects public host when addon lacks public ingress support"

if (cd "$REPO_DIR" && ./productive-k3s-core.sh addon install --tgz "${ADDON_ARCHIVE}" >/tmp/productive-k3s-core-addon-target.out 2>&1); then
  fail "addon install without explicit target unexpectedly succeeded"
fi
grep -q "explicit target" /tmp/productive-k3s-core-addon-target.out || fail "addon install target validation message missing"
pass "addon tgz install requires an explicit target"

if (cd "$REPO_DIR" && ./productive-k3s-core.sh unsupported >/tmp/productive-k3s-core-cli-unsupported.out 2>&1); then
  fail "unsupported public CLI command unexpectedly succeeded"
fi
grep -q "Unsupported command" /tmp/productive-k3s-core-cli-unsupported.out || fail "unsupported public CLI command message missing"
pass "unsupported public CLI command is rejected"

preflight_recipe="$(cd "$REPO_DIR" && make -n preflight)"
printf '%s\n' "$preflight_recipe" | grep -q './productive-k3s-core.sh preflight' || fail "make preflight does not target public CLI"
pass "make preflight targets public CLI"

preflight_strict_recipe="$(cd "$REPO_DIR" && make -n preflight-strict)"
printf '%s\n' "$preflight_strict_recipe" | grep -q './productive-k3s-core.sh preflight --strict' || fail "make preflight-strict does not map to base command plus flag"
pass "make preflight-strict maps to preflight --strict"

dry_run_recipe="$(cd "$REPO_DIR" && make -n dry-run)"
printf '%s\n' "$dry_run_recipe" | grep -q './productive-k3s-core.sh bootstrap --dry-run' || fail "make dry-run does not map to bootstrap --dry-run"
pass "make dry-run maps to bootstrap --dry-run"

validate_strict_recipe="$(cd "$REPO_DIR" && make -n validate-strict)"
printf '%s\n' "$validate_strict_recipe" | grep -q './productive-k3s-core.sh validate --strict' || fail "make validate-strict does not map to validate --strict"
pass "make validate-strict maps to validate --strict"
