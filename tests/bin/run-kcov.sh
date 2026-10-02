#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers/test-common.sh"

need_cmd shellspec
need_cmd jq
if ! command -v kcov >/dev/null 2>&1; then
  printf 'Missing required command: kcov\n' >&2
  printf 'On Ubuntu, install it with: sudo apt-get install -y kcov libelf-dev libdw-dev\n' >&2
  exit 127
fi

cd "${REPO_DIR}"
rm -rf "${COVERAGE_DIR}/shellspec"
mkdir -p "${COVERAGE_DIR}/shellspec/raw"

run_kcov() {
  local output_dir="$1"
  local include_path="$2"
  shift 2
  kcov \
    --include-path="${include_path}" \
    "${COVERAGE_DIR}/shellspec/raw/${output_dir}" \
    "$@"
}

run_kcov_scripts() {
  local output_dir="$1"
  shift
  run_kcov "${output_dir}" "${REPO_DIR}/scripts" "$@"
}

run_kcov_core_cli() {
  local output_dir="$1"
  shift
  kcov \
    --include-pattern="${REPO_DIR}/scripts/productive-k3s-core.sh" \
    "${COVERAGE_DIR}/shellspec/raw/${output_dir}" \
    "$@"
}

run_kcov_core_cli_expect() {
  local output_dir="$1"
  local expected_rc="$2"
  shift 2
  run_kcov_core_cli "${output_dir}" "$@"
  local actual_rc=$?
  if [[ "${actual_rc}" -ne "${expected_rc}" ]]; then
    printf 'coverage command %s returned %s, expected %s\n' "${output_dir}" "${actual_rc}" "${expected_rc}" >&2
    return 1
  fi
}

tmp_dir="$(mktemp -d)"
repo_bundle_info="${REPO_DIR}/bundle-info.json"
created_repo_bundle_info=0
# shellcheck disable=SC2329
cleanup() {
  if [[ "${created_repo_bundle_info}" == "1" ]]; then
    rm -f "${repo_bundle_info}"
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

inject_compatibility_contract() {
  local manifest="$1"
  local distro="${2:-k3s}"
  awk -v distro="${distro}" '
    /^  sourceRevision:/ { has_revision=1 }
    /^  compatibility:/ { has_compatibility=1 }
    /^spec:/ {
      if (!has_revision) {
        print "  sourceRevision: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      }
      print
      if (!has_compatibility) {
        print "  compatibility:"
        print "    requires:"
        print "      core:"
        print "        contract: artifact/v1"
        print "        minVersion: 0.9.6"
        print "        maxVersionExclusive: 0.10.0"
        print "      kubernetes:"
        print "        distros:"
        print "          - " distro
      }
      next
    }
    { print }
  ' "${manifest}" >"${manifest}.tmp"
  mv "${manifest}.tmp" "${manifest}"
}

addon_pkg_dir="${tmp_dir}/addon/pkg"
addon_tgz="${tmp_dir}/demo-addon.tgz"
missing_revision_addon_tgz="${tmp_dir}/missing-revision-addon.tgz"
mutable_revision_addon_tgz="${tmp_dir}/mutable-revision-addon.tgz"
addon_install_marker="${tmp_dir}/addon-installed.txt"
private_addon_pkg_dir="${tmp_dir}/private-addon/pkg"
private_addon_tgz="${tmp_dir}/private-addon.tgz"
missing_installer_addon_pkg_dir="${tmp_dir}/missing-installer-addon/pkg"
missing_installer_addon_tgz="${tmp_dir}/missing-installer-addon.tgz"
failing_installer_addon_pkg_dir="${tmp_dir}/failing-installer-addon/pkg"
failing_installer_addon_tgz="${tmp_dir}/failing-installer-addon.tgz"
fake_home="${tmp_dir}/home"
fake_bin="${tmp_dir}/bin"
fake_kubeconfig="${tmp_dir}/kubeconfig.yaml"
mkdir -p "${addon_pkg_dir}/scripts"
mkdir -p "${fake_home}" "${fake_bin}"
printf 'apiVersion: v1\nkind: Config\ncurrent-context: test\n' >"${fake_kubeconfig}"
cat >"${addon_pkg_dir}/addon.yaml" <<'EOF'
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
        namespace: demo
        service:
          name: demo-addon
          port: 80
EOF
cat >"${addon_pkg_dir}/scripts/install.sh" <<EOF
#!/usr/bin/env bash
printf 'installed\n' >"${addon_install_marker}"
EOF
cat >"${addon_pkg_dir}/scripts/validate.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${addon_pkg_dir}/scripts/clean.sh" <<'EOF'
#!/usr/bin/env bash
pk3s_addon_clean() { :; }
EOF
cat >"${addon_pkg_dir}/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
pk3s_addon_backup() { mkdir -p "$1/demo-addon"; }
EOF
chmod +x "${addon_pkg_dir}/scripts/install.sh" "${addon_pkg_dir}/scripts/validate.sh" "${addon_pkg_dir}/scripts/clean.sh" "${addon_pkg_dir}/scripts/backup.sh"
inject_compatibility_contract "${addon_pkg_dir}/addon.yaml"
tar -czf "${addon_tgz}" -C "${addon_pkg_dir}" .
addon_tgz_digest="$(sha256sum "${addon_tgz}" | awk '{print $1}')"
cp -R "${addon_pkg_dir}" "${tmp_dir}/missing-revision-addon"
sed -i '/^  sourceRevision:/d' "${tmp_dir}/missing-revision-addon/addon.yaml"
tar -czf "${missing_revision_addon_tgz}" -C "${tmp_dir}/missing-revision-addon" .
cp -R "${addon_pkg_dir}" "${tmp_dir}/mutable-revision-addon"
sed -i 's/^  sourceRevision:.*/  sourceRevision: development/' "${tmp_dir}/mutable-revision-addon/addon.yaml"
tar -czf "${mutable_revision_addon_tgz}" -C "${tmp_dir}/mutable-revision-addon" .

mkdir -p "${private_addon_pkg_dir}/scripts"
cat >"${private_addon_pkg_dir}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: private-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
cat >"${private_addon_pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${private_addon_pkg_dir}/scripts/install.sh"
inject_compatibility_contract "${private_addon_pkg_dir}/addon.yaml"
tar -czf "${private_addon_tgz}" -C "${private_addon_pkg_dir}" .

mkdir -p "${missing_installer_addon_pkg_dir}" "${failing_installer_addon_pkg_dir}/scripts"
cat >"${missing_installer_addon_pkg_dir}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: missing-installer-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
inject_compatibility_contract "${missing_installer_addon_pkg_dir}/addon.yaml"
tar -czf "${missing_installer_addon_tgz}" -C "${missing_installer_addon_pkg_dir}" .
cat >"${failing_installer_addon_pkg_dir}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: failing-installer-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
cat >"${failing_installer_addon_pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "${failing_installer_addon_pkg_dir}/scripts/install.sh"
inject_compatibility_contract "${failing_installer_addon_pkg_dir}/addon.yaml"
tar -czf "${failing_installer_addon_tgz}" -C "${failing_installer_addon_pkg_dir}" .

stack_pkg_dir="${tmp_dir}/stack/pkg"
stack_tgz="${tmp_dir}/demo-stack.tgz"
bad_addon_pkg_dir="${tmp_dir}/bad-addon/pkg"
bad_addon_tgz="${tmp_dir}/bad-addon.tgz"
bad_stack_dir="${tmp_dir}/bad-stack"
bad_stack_tgz="${tmp_dir}/bad-stack.tgz"
empty_stack_dir="${tmp_dir}/empty-stack"
bad_mode_stack_dir="${tmp_dir}/bad-mode-stack"
duplicate_stack_dir="${tmp_dir}/duplicate-stack"
missing_bundle_stack_dir="${tmp_dir}/missing-bundle-stack"
missing_bundle_stack_tgz="${tmp_dir}/missing-bundle-stack.tgz"
missing_stack_manifest_dir="${tmp_dir}/missing-stack-manifest"
missing_stack_name_dir="${tmp_dir}/missing-stack-name"
missing_stack_version_dir="${tmp_dir}/missing-stack-version"
missing_addon_name_stack_dir="${tmp_dir}/missing-addon-name-stack"
bundled_without_sources_dir="${tmp_dir}/bundled-without-sources"
unsupported_distro_stack_dir="${tmp_dir}/unsupported-distro-stack"
duplicate_distro_stack_dir="${tmp_dir}/duplicate-distro-stack"
corrupt_tgz="${tmp_dir}/corrupt.tgz"
missing_addon_manifest_tgz="${tmp_dir}/missing-addon-manifest.tgz"
rollback_manifest="${tmp_dir}/rollback-manifest.json"
backup_output="${tmp_dir}/backup-output"
addons_repo="${tmp_dir}/addons-repo"
mkdir -p "${stack_pkg_dir}/addons" "${addons_repo}/addons/demo-addon" "${addons_repo}/stacks/base"
cp "${addon_tgz}" "${stack_pkg_dir}/addons/demo-addon.tgz"
cat >"${stack_pkg_dir}/stack.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
  version: 0.1.0
spec:
  resolution:
    mode: bundled
  runtime:
    compatibility:
      core:
        minVersion: v0.0.1
      kubernetes:
        distros:
          - k3s
  addons:
    - name: demo-addon
      version: 0.1.0
      source: addons/demo-addon.tgz
      digest: sha256:${addon_tgz_digest}
EOF
inject_compatibility_contract "${stack_pkg_dir}/stack.yaml" k3s
cp "${stack_pkg_dir}/stack.yaml" "${addons_repo}/stacks/base/stack.yaml"
tar -czf "${stack_tgz}" -C "${stack_pkg_dir}" .
for variant in mutable-revision missing-digest bad-digest mismatched-name mismatched-version; do
  cp -R "${stack_pkg_dir}" "${tmp_dir}/stack-${variant}"
done
sed -i 's/^  sourceRevision:.*/  sourceRevision: development/' "${tmp_dir}/stack-mutable-revision/stack.yaml"
sed -i '/^      digest:/d' "${tmp_dir}/stack-missing-digest/stack.yaml"
sed -i 's/^      digest:.*/      digest: sha256:0000000000000000000000000000000000000000000000000000000000000000/' "${tmp_dir}/stack-bad-digest/stack.yaml"
sed -i 's/^    - name: demo-addon/    - name: other-addon/' "${tmp_dir}/stack-mismatched-name/stack.yaml"
sed -i 's/^      version: 0.1.0/      version: 0.2.0/' "${tmp_dir}/stack-mismatched-version/stack.yaml"
for variant in mutable-revision missing-digest bad-digest mismatched-name mismatched-version; do
  tar -czf "${tmp_dir}/stack-${variant}.tgz" -C "${tmp_dir}/stack-${variant}" .
done
if [[ ! -e "${repo_bundle_info}" ]]; then
  cat >"${repo_bundle_info}" <<'EOF'
{
  "schema_version": "1",
  "bundle_name": "productive-k3s-core",
  "bundle_type": "productive-k3s-core",
  "bundle_version": "v0.1.0",
  "cli_entrypoint": "productive-k3s-core.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF
  created_repo_bundle_info=1
fi

mkdir -p "${bad_addon_pkg_dir}"
cat >"${bad_addon_pkg_dir}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: broken-addon
spec:
  type: shell
EOF
inject_compatibility_contract "${bad_addon_pkg_dir}/addon.yaml"
tar -czf "${bad_addon_tgz}" -C "${bad_addon_pkg_dir}" .

mkdir -p "${bad_stack_dir}"
cat >"${bad_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: broken-stack
  version: 0.1.0
spec:
  resolution:
    mode: bundled
  runtime:
    compatibility:
      kubernetes:
        distros:
          - unsupported
  addons:
    - name: demo-addon
      source: ../outside.tgz
EOF
inject_compatibility_contract "${bad_stack_dir}/stack.yaml"
tar -czf "${bad_stack_tgz}" -C "${bad_stack_dir}" .

mkdir -p \
  "${empty_stack_dir}" \
  "${bad_mode_stack_dir}" \
  "${duplicate_stack_dir}" \
  "${missing_bundle_stack_dir}" \
  "${missing_stack_manifest_dir}" \
  "${missing_stack_name_dir}" \
  "${missing_stack_version_dir}" \
  "${missing_addon_name_stack_dir}" \
  "${bundled_without_sources_dir}" \
  "${unsupported_distro_stack_dir}" \
  "${duplicate_distro_stack_dir}"
cat >"${empty_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: empty
  version: 0.1.0
spec:
  addons: []
EOF
cat >"${bad_mode_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: bad-mode
  version: 0.1.0
spec:
  resolution:
    mode: remote
  addons:
    - demo-addon
EOF
cat >"${duplicate_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: duplicate
  version: 0.1.0
spec:
  addons:
    - demo-addon
    - name: demo-addon
      version: 0.1.0
EOF
cat >"${missing_bundle_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: missing-bundle
  version: 0.1.0
spec:
  resolution:
    mode: bundled
  addons:
    - name: demo-addon
      source: addons/missing.tgz
EOF
tar -czf "${missing_bundle_stack_tgz}" -C "${missing_bundle_stack_dir}" .
cat >"${missing_stack_name_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  version: 0.1.0
spec:
  addons:
    - demo-addon
EOF
cat >"${missing_stack_version_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: missing-version
spec:
  addons:
    - demo-addon
EOF
cat >"${missing_addon_name_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: missing-addon-name
  version: 0.1.0
spec:
  addons:
    - version: 0.1.0
EOF
cat >"${bundled_without_sources_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: bundled-without-sources
  version: 0.1.0
spec:
  resolution:
    mode: bundled
  addons:
    - demo-addon
EOF
cat >"${unsupported_distro_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: unsupported-distro
  version: 0.1.0
spec:
  runtime:
    compatibility:
      kubernetes:
        distros:
          - unsupported
  addons:
    - demo-addon
EOF
cat >"${duplicate_distro_stack_dir}/stack.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: duplicate-distro
  version: 0.1.0
spec:
  runtime:
    compatibility:
      kubernetes:
        distros:
          - k3s
          - k3s
  addons:
    - demo-addon
EOF
for manifest in \
  "${empty_stack_dir}/stack.yaml" \
  "${bad_mode_stack_dir}/stack.yaml" \
  "${duplicate_stack_dir}/stack.yaml" \
  "${missing_bundle_stack_dir}/stack.yaml" \
  "${missing_stack_name_dir}/stack.yaml" \
  "${missing_stack_version_dir}/stack.yaml" \
  "${missing_addon_name_stack_dir}/stack.yaml" \
  "${bundled_without_sources_dir}/stack.yaml"; do
  inject_compatibility_contract "${manifest}"
done
inject_compatibility_contract "${unsupported_distro_stack_dir}/stack.yaml" unsupported
inject_compatibility_contract "${duplicate_distro_stack_dir}/stack.yaml" unsupported
tar -czf "${missing_addon_manifest_tgz}" -C "${missing_stack_manifest_dir}" .
printf 'not a tgz\n' >"${corrupt_tgz}"
cat >"${rollback_manifest}" <<'EOF'
{
  "run_id": "coverage-stack-run",
  "status": "success",
  "settings": {"cluster_distro": "k3s", "stack_name": "base"},
  "components": {"stack_addons": {"planned_action": "install", "result": "installed"}}
}
EOF

cat >"${fake_bin}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"get ingress -A -o jsonpath="* ]]; then
  exit 0
fi
if [[ "$*" == *"apply -f -"* ]]; then
  cat >/dev/null
  exit 0
fi
printf 'unexpected kubectl invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "${fake_bin}/kubectl"
cat >"${fake_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-n" && "${2:-}" == "true" ]]; then
  exit 0
fi
if [[ "${1:-}" == "cp" && "${2:-}" == "/etc/rancher/k3s/k3s.yaml" ]]; then
  printf 'apiVersion: v1\nkind: Config\n' >"${3}"
  exit 0
fi
case "${1:-}" in
  chown|exportfs|rm|systemctl|umount|*/k3s-killall.sh|*/k3s-uninstall.sh|*/rke2-killall.sh|*/rke2-uninstall.sh)
    exit 0
    ;;
esac
exec "$@"
EOF
cat >"${fake_bin}/k3s" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "kubectl" ]] && shift
if [[ "$*" == "get nodes --no-headers" ]]; then
  printf 'coverage-node Ready control-plane 1m v1.35.5+k3s1\n'
  exit 0
fi
if [[ "$*" == "get nodes" ]]; then
  printf 'coverage-node Ready\n'
  exit 0
fi
exit 0
EOF
chmod +x "${fake_bin}/systemctl" "${fake_bin}/sudo" "${fake_bin}/k3s"

set +e
run_kcov_scripts shellspec shellspec tests/spec
rc=$?
if [[ ${rc} -eq 0 || (${rc} -eq 101 && -f "${COVERAGE_DIR}/shellspec/raw/shellspec/index.html") ]]; then
  rc=0
  run_kcov_core_cli cli-help ./productive-k3s-core.sh help || rc=$?
  run_kcov_core_cli cli-bundle-info ./productive-k3s-core.sh bundle info --json || rc=$?
  run_kcov_core_cli cli-bom ./productive-k3s-core.sh bom --json || rc=$?
  run_kcov_core_cli cli-apply-help ./productive-k3s-core.sh apply --help || rc=$?
  TELEMETRY_ENABLED=true TELEMETRY_ENDPOINT='' run_kcov_core_cli cli-apply-help-telemetry ./productive-k3s-core.sh apply --help || rc=$?
  TELEMETRY_ENABLED=false run_kcov_core_cli cli-legacy-apply-option ./productive-k3s-core.sh --dry-run || rc=$?
  run_kcov_core_cli cli-preflight-help ./productive-k3s-core.sh preflight --help || rc=$?
  PRODUCTIVE_K3S_DISTRO=unsupported run_kcov_core_cli cli-preflight-invalid-runtime ./productive-k3s-core.sh preflight || rc=$?
  run_kcov_core_cli cli-validate-help ./productive-k3s-core.sh validate --help || rc=$?
  PRODUCTIVE_K3S_DISTRO=unsupported run_kcov_core_cli_expect cli-validate-json-output-invalid-runtime 1 ./productive-k3s-core.sh validate --json-output || rc=$?
  run_kcov_core_cli cli-addon-validate ./productive-k3s-core.sh addon validate --tgz "${addon_tgz}" || rc=$?
  KUBECONFIG="${fake_kubeconfig}" HOME="${fake_home}" run_kcov_core_cli cli-addon-install ./productive-k3s-core.sh addon install --tgz "${addon_tgz}" || rc=$?
  KUBECONFIG="${fake_kubeconfig}" HOME="${fake_home}" PATH="${fake_bin}:${PATH}" run_kcov_core_cli cli-addon-install-public ./productive-k3s-core.sh addon install --tgz "${addon_tgz}" --public-host demo.k3s.lab.internal || rc=$?
  KUBECONFIG="${fake_kubeconfig}" HOME="${fake_home}" PATH="${fake_bin}:${PATH}" run_kcov_core_cli_expect cli-addon-install-public-invalid-host 4 ./productive-k3s-core.sh addon install --tgz "${addon_tgz}" --public-host "bad host" || rc=$?
  KUBECONFIG="${fake_kubeconfig}" HOME="${fake_home}" PATH="${fake_bin}:${PATH}" run_kcov_core_cli_expect cli-addon-install-public-unsupported 4 ./productive-k3s-core.sh addon install --tgz "${private_addon_tgz}" --public-host demo.k3s.lab.internal || rc=$?
  KUBECONFIG="${fake_kubeconfig}" HOME="${fake_home}" run_kcov_core_cli_expect cli-addon-install-missing-script 4 ./productive-k3s-core.sh addon install --tgz "${missing_installer_addon_tgz}" || rc=$?
  KUBECONFIG="${fake_kubeconfig}" HOME="${fake_home}" run_kcov_core_cli_expect cli-addon-install-failing-script 7 ./productive-k3s-core.sh addon install --tgz "${failing_installer_addon_tgz}" || rc=$?
  HOME="${tmp_dir}/no-kube-home" run_kcov_core_cli_expect cli-addon-install-no-kubeconfig 4 ./productive-k3s-core.sh addon install --tgz "${addon_tgz}" || rc=$?
  TELEMETRY_ENABLED=true TELEMETRY_ENDPOINT='' HOME="${tmp_dir}/no-kube-home" run_kcov_core_cli_expect cli-addon-install-no-kubeconfig-telemetry 4 ./productive-k3s-core.sh addon install --tgz "${addon_tgz}" || rc=$?
  run_kcov_core_cli cli-dev-stack-validate ./productive-k3s-core.sh dev stack validate --source "${stack_pkg_dir}" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli cli-stack-export-dir ./productive-k3s-core.sh stack export --tgz "${stack_tgz}" --output "${tmp_dir}/stack-export-dir" --dry-run || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli cli-stack-export-tgz ./productive-k3s-core.sh stack export --tgz "${stack_tgz}" --output "${tmp_dir}/stack-export.tgz" --dry-run || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli cli-stack-install-dry-run ./productive-k3s-core.sh stack install --tgz "${stack_tgz}" --dry-run || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli cli-stack-install-dry-run-semver ./productive-k3s-core.sh stack install --tgz "${stack_tgz}" --dry-run || rc=$?
  PATH="${fake_bin}:${PATH}" PRODUCTIVE_K3S_DISTRO=k3s TELEMETRY_ENABLED=false run_kcov_scripts cli-stack-validate-artifact ./productive-k3s-core.sh stack validate --tgz "${stack_tgz}" --json || rc=$?
  PATH="${fake_bin}:${PATH}" PRODUCTIVE_K3S_DISTRO=k3s TELEMETRY_ENABLED=false run_kcov_scripts cli-stack-cleanup-plan-artifact ./productive-k3s-core.sh stack cleanup --tgz "${stack_tgz}" --plan || rc=$?
  PATH="${fake_bin}:${PATH}" PRODUCTIVE_K3S_DISTRO=k3s TELEMETRY_ENABLED=false run_kcov_scripts cli-stack-cleanup-apply-artifact ./productive-k3s-core.sh stack cleanup --tgz "${stack_tgz}" --apply --yes --confirm-clean || rc=$?
  PATH="${fake_bin}:${PATH}" PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_SYSTEM_KUBECONFIG_PATH="${tmp_dir}/missing-system-kubeconfig" TELEMETRY_ENABLED=false run_kcov_scripts cli-stack-backup-artifact ./productive-k3s-core.sh stack backup --tgz "${stack_tgz}" "${backup_output}" || rc=$?
  PATH="${fake_bin}:${PATH}" PRODUCTIVE_K3S_DISTRO=k3s TELEMETRY_ENABLED=false run_kcov_scripts cli-stack-rollback-plan-artifact ./productive-k3s-core.sh stack rollback --tgz "${stack_tgz}" --to "${rollback_manifest}" --plan || rc=$?
  PATH="${fake_bin}:${PATH}" PRODUCTIVE_K3S_DISTRO=k3s TELEMETRY_ENABLED=false run_kcov_scripts cli-stack-rollback-apply-artifact ./productive-k3s-core.sh stack rollback --tgz "${stack_tgz}" --to "${rollback_manifest}" --apply --yes || rc=$?
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}" TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-install-source-rejected 2 ./productive-k3s-core.sh stack install base --dry-run || rc=$?
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}" run_kcov_core_cli_expect cli-stack-cleanup-source-rejected 2 ./productive-k3s-core.sh stack cleanup base --plan || rc=$?
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}" run_kcov_core_cli_expect cli-stack-validate-source-rejected 2 ./productive-k3s-core.sh stack validate base --json || rc=$?
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}" run_kcov_core_cli_expect cli-stack-backup-source-rejected 2 ./productive-k3s-core.sh stack backup base "${tmp_dir}/backup-out" || rc=$?
  PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}" run_kcov_core_cli_expect cli-stack-rollback-source-rejected 2 ./productive-k3s-core.sh stack rollback base --to "${tmp_dir}/missing-manifest.json" || rc=$?
  run_kcov_core_cli_expect cli-events-missing-value 2 ./productive-k3s-core.sh --events || rc=$?
  run_kcov_core_cli_expect cli-events-unsupported-format 2 ./productive-k3s-core.sh --events json help || rc=$?
  run_kcov_core_cli_expect cli-unsupported-command 2 ./productive-k3s-core.sh unsupported || rc=$?
  run_kcov_core_cli_expect cli-bundle-usage 2 ./productive-k3s-core.sh bundle || rc=$?
  run_kcov_core_cli_expect cli-bom-usage 2 ./productive-k3s-core.sh bom || rc=$?
  run_kcov_core_cli_expect cli-addon-usage 2 ./productive-k3s-core.sh addon || rc=$?
  run_kcov_core_cli_expect cli-addon-install-usage 2 ./productive-k3s-core.sh addon install || rc=$?
  run_kcov_core_cli_expect cli-addon-install-source-rejected 2 ./productive-k3s-core.sh addon install demo-addon || rc=$?
  run_kcov_core_cli_expect cli-addon-validate-bad 4 ./productive-k3s-core.sh addon validate --tgz "${bad_addon_tgz}" || rc=$?
  run_kcov_core_cli_expect cli-addon-validate-missing-revision 4 ./productive-k3s-core.sh addon validate --tgz "${missing_revision_addon_tgz}" || rc=$?
  run_kcov_core_cli_expect cli-addon-validate-mutable-revision 4 ./productive-k3s-core.sh addon validate --tgz "${mutable_revision_addon_tgz}" || rc=$?
  run_kcov_core_cli_expect cli-addon-validate-missing-manifest 4 ./productive-k3s-core.sh addon validate --tgz "${missing_addon_manifest_tgz}" || rc=$?
  run_kcov_core_cli_expect cli-addon-validate-corrupt 4 ./productive-k3s-core.sh addon validate --tgz "${corrupt_tgz}" || rc=$?
  run_kcov_core_cli_expect cli-dev-addon-missing 4 ./productive-k3s-core.sh dev addon validate --source "${tmp_dir}/missing-addon-source" || rc=$?
  run_kcov_core_cli_expect cli-dev-usage 2 ./productive-k3s-core.sh dev wrong validate || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-bad 4 ./productive-k3s-core.sh dev stack validate --source "${bad_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-empty 4 ./productive-k3s-core.sh dev stack validate --source "${empty_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-bad-mode 4 ./productive-k3s-core.sh dev stack validate --source "${bad_mode_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-duplicate 4 ./productive-k3s-core.sh dev stack validate --source "${duplicate_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-missing-manifest 4 ./productive-k3s-core.sh dev stack validate --source "${missing_stack_manifest_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-missing-name 4 ./productive-k3s-core.sh dev stack validate --source "${missing_stack_name_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-missing-version 4 ./productive-k3s-core.sh dev stack validate --source "${missing_stack_version_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-missing-addon-name 4 ./productive-k3s-core.sh dev stack validate --source "${missing_addon_name_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-bundled-without-sources 4 ./productive-k3s-core.sh dev stack validate --source "${bundled_without_sources_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-unsupported-distro 4 ./productive-k3s-core.sh dev stack validate --source "${unsupported_distro_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-dev-stack-duplicate-distro 4 ./productive-k3s-core.sh dev stack validate --source "${duplicate_distro_stack_dir}" || rc=$?
  run_kcov_core_cli_expect cli-stack-usage 2 ./productive-k3s-core.sh stack || rc=$?
  run_kcov_core_cli_expect cli-stack-install-usage 2 ./productive-k3s-core.sh stack install || rc=$?
  run_kcov_core_cli_expect cli-stack-export-usage 2 ./productive-k3s-core.sh stack export --tgz "${stack_tgz}" || rc=$?
  run_kcov_core_cli_expect cli-stack-validate-usage 2 ./productive-k3s-core.sh stack validate || rc=$?
  run_kcov_core_cli_expect cli-stack-backup-usage 2 ./productive-k3s-core.sh stack backup || rc=$?
  run_kcov_core_cli_expect cli-stack-cleanup-usage 2 ./productive-k3s-core.sh stack cleanup || rc=$?
  run_kcov_core_cli_expect cli-stack-rollback-usage 2 ./productive-k3s-core.sh stack rollback || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-bad 4 ./productive-k3s-core.sh stack export --tgz "${bad_stack_tgz}" --output "${tmp_dir}/bad-stack-export" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-missing-bundle 4 ./productive-k3s-core.sh stack export --tgz "${missing_bundle_stack_tgz}" --output "${tmp_dir}/missing-bundle-export" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-existing-output 2 ./productive-k3s-core.sh stack export --tgz "${stack_tgz}" --output "${tmp_dir}/stack-export-dir" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-missing-tgz 3 ./productive-k3s-core.sh stack export --tgz "${tmp_dir}/missing.tgz" --output "${tmp_dir}/missing-export" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-corrupt-tgz 4 ./productive-k3s-core.sh stack export --tgz "${corrupt_tgz}" --output "${tmp_dir}/corrupt-export" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-mutable-revision 4 ./productive-k3s-core.sh stack export --tgz "${tmp_dir}/stack-mutable-revision.tgz" --output "${tmp_dir}/mutable-revision-export" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-export-missing-digest 4 ./productive-k3s-core.sh stack export --tgz "${tmp_dir}/stack-missing-digest.tgz" --output "${tmp_dir}/missing-digest-export" || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-install-bad-digest 4 ./productive-k3s-core.sh stack install --tgz "${tmp_dir}/stack-bad-digest.tgz" --dry-run || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-install-mismatched-name 4 ./productive-k3s-core.sh stack install --tgz "${tmp_dir}/stack-mismatched-name.tgz" --dry-run || rc=$?
  PRODUCTIVE_K3S_DISTRO=k3s PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-install-mismatched-version 4 ./productive-k3s-core.sh stack install --tgz "${tmp_dir}/stack-mismatched-version.tgz" --dry-run || rc=$?
  PRODUCTIVE_K3S_DISTRO=rke2 PRODUCTIVE_K3S_ENGINE=native TELEMETRY_ENABLED=false run_kcov_core_cli_expect cli-stack-install-incompatible-distro 4 ./productive-k3s-core.sh stack install --tgz "${stack_tgz}" --dry-run || rc=$?
  run_kcov_scripts runtime-compatibility ./tests/test-runtime-compatibility.sh || rc=$?
  run_kcov_scripts core-cli-contract ./tests/test-productive-k3s-core-cli.sh || rc=$?
fi
set -e

if [[ ${rc} -eq 0 ]]; then
  kcov --merge "${COVERAGE_DIR}/shellspec" "${COVERAGE_DIR}/shellspec/raw"/* >/dev/null
  runtime_coverage="$({
    jq -r '
      [.files[]
        | select((.file | endswith("productive-k3s-core-dev.sh")
          or endswith("create-release-tag.sh")
          or endswith("build-release-bundle.sh")
          or endswith("install-release-template.sh")) | not)
        | {covered: (.covered_lines | tonumber), total: (.total_lines | tonumber)}]
      | (map(.covered) | add) as $covered
      | (map(.total) | add) as $total
      | "\($covered) \($total) \(($covered * 10000 / $total | floor) / 100)"
    ' "${COVERAGE_DIR}/shellspec/kcov-merged/coverage.json"
  })"
  read -r runtime_covered runtime_total runtime_percent <<<"${runtime_coverage}"
  printf 'Runtime shell coverage: %s%% (%s/%s lines)\n' "${runtime_percent}" "${runtime_covered}" "${runtime_total}"
  if ((runtime_covered * 100 < runtime_total * 85)); then
    printf 'Runtime shell coverage is below the required 85%% floor.\n' >&2
    exit 1
  fi
  exit 0
fi

if [[ ${rc} -eq 101 && -d "${COVERAGE_DIR}/shellspec/raw" ]]; then
  kcov --merge "${COVERAGE_DIR}/shellspec" "${COVERAGE_DIR}/shellspec/raw"/* >/dev/null || true
  printf 'kcov returned 101 but coverage artifacts were generated successfully.\n' >&2
  exit 0
fi

exit "${rc}"
