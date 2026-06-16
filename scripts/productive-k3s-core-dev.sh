#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMP_ADDONS_CLONE_DIR=""
DEFAULT_GITHUB_OWNER="${PRODUCTIVE_K3S_GITHUB_OWNER:-jemacchi}"
DEFAULT_GITHUB_REPO_BASE_URL="${PRODUCTIVE_K3S_GITHUB_REPO_BASE_URL:-https://github.com/${DEFAULT_GITHUB_OWNER}}"

usage() {
  cat <<'EOF'
Usage: ./scripts/productive-k3s-core-dev.sh <command> [args...]

Development commands:
  docs-build
  docs-serve
  docs-up
  docs-down
  docs-clean
  test-clean
  test-clean-artifacts
  test-clean-vms
  test-clean-all
  test-checkstatus
  test-checkstatus-matrix
  test-checkstatus-local
  test-checkstatus-external
  test-local-all
  test-external-all
  test-stacks
  test-stacks-k3s
  test-stacks-rke2
  test-stacks-k3s-ubuntu24
  test-stacks-k3s-ubuntu22
  test-stacks-k3s-debian13
  test-stacks-k3s-debian12
  test-stacks-rke2-ubuntu24
  test-stacks-rke2-ubuntu22
  test-preflight-host
  test-arm-support-docs
  test-bootstrap-modes
  test-artifact-tools
  test-telemetry
  test-productive-k3s-core-cli
  test-in-vm-engine-propagation
  test-agent-smoke
  test-smoke
  test-core
  test-rke2-core
  test-rke2-core-ubuntu22
  test-rke2-full
  test-rke2-full-clean
  test-rke2-full-rollback
  test-rke2-ubuntu-all
  test-core-debian12
  test-core-debian13
  test-matrix-smoke
  test-matrix-core
  test-matrix-full
  test-matrix-full-rollback
  test-matrix-full-clean
  test-matrix-all
  help

Environment:
  PRODUCTIVE_K3S_ADDONS_REPO_DIR  Local productive-k3s-addons checkout to copy for full/core VM tests
  PRODUCTIVE_K3S_ADDONS_REPO_URL  Git URL to clone productive-k3s-addons when no local checkout is provided
  PRODUCTIVE_K3S_ADDONS_REPO_REF  Branch or tag to clone from PRODUCTIVE_K3S_ADDONS_REPO_URL (default: current branch or main)
  PRODUCTIVE_K3S_GITHUB_OWNER     Default GitHub owner used to resolve ecosystem repositories (default: ${DEFAULT_GITHUB_OWNER})
  PRODUCTIVE_K3S_GITHUB_REPO_BASE_URL
                                  Default GitHub repository base URL (default: ${DEFAULT_GITHUB_REPO_BASE_URL})
  STACK_TGZ_URL                   Published stack tgz URL used by test-stacks
EOF
}

cleanup_temp_addons_clone() {
  if [[ -n "${TEMP_ADDONS_CLONE_DIR}" && -d "${TEMP_ADDONS_CLONE_DIR}" ]]; then
    rm -rf "${TEMP_ADDONS_CLONE_DIR}"
  fi
}

default_addons_repo_url() {
  printf '%s\n' "${DEFAULT_GITHUB_REPO_BASE_URL}/productive-k3s-addons.git"
}

default_addons_repo_ref() {
  local branch_name=""
  branch_name="$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "${branch_name}" && "${branch_name}" != "HEAD" ]]; then
    printf '%s\n' "${branch_name}"
    return 0
  fi
  printf '%s\n' "main"
}

log_addons_repo_source() {
  local source_type="$1"
  local source_value="$2"
  local ref_value="${3:-}"

  case "${source_type}" in
    dir)
      printf '[INFO] Local tests using productive-k3s-addons from directory: %s\n' "${source_value}"
      ;;
    url)
      printf '[INFO] Local tests cloning productive-k3s-addons from URL: %s (ref: %s)\n' "${source_value}" "${ref_value}"
      ;;
  esac
}

prepare_addons_repo_checkout() {
  local source_dir=""
  local source_url=""
  local source_ref=""

  TEMP_ADDONS_CLONE_DIR="$(mktemp -d)"
  trap cleanup_temp_addons_clone EXIT

  if [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" ]]; then
    [[ -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/addons" && -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/stacks" ]] || {
      printf 'invalid PRODUCTIVE_K3S_ADDONS_REPO_DIR: %s\n' "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}" >&2
      exit 1
    }
    source_dir="${PRODUCTIVE_K3S_ADDONS_REPO_DIR}"
  fi

  if [[ -n "${source_dir}" ]]; then
    log_addons_repo_source dir "${source_dir}"
    mkdir -p "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons"
    cp -a "${source_dir}/." \
      "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons/"
  else
    source_url="${PRODUCTIVE_K3S_ADDONS_REPO_URL:-$(default_addons_repo_url)}"
    source_ref="${PRODUCTIVE_K3S_ADDONS_REPO_REF:-$(default_addons_repo_ref)}"
    log_addons_repo_source url "${source_url}" "${source_ref}"
    if ! git clone --depth 1 --branch "${source_ref}" \
      "${source_url}" \
      "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons"; then
      printf 'failed to clone productive-k3s-addons from %s (ref: %s)\n' "${source_url}" "${source_ref}" >&2
      exit 1
    fi
  fi

  cat >> "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons/.gitignore" <<'EOF'
test-artifacts/
.tmp/
.tmp-*/
.live-*/
runs/
EOF

  export PRODUCTIVE_K3S_ADDONS_REPO_DIR="${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons"
}

run_tests_make() {
  exec make -C "${REPO_DIR}/tests" "$@"
}

run_checkstatus() {
  local category="$1"
  shift
  exec bash "${REPO_DIR}/tests/check-test-status.sh" --category "${category}" "$@"
}

artifacts_dir() {
  printf '%s\n' "${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"
}

clean_suite_category_artifacts() {
  local suite_category="$1"
  rm -f "$(artifacts_dir)"/test-"${suite_category}"-*.json
}

clean_named_suite_artifacts() {
  local suite_category="$1"
  local suite_name="$2"
  rm -f "$(artifacts_dir)"/test-"${suite_category}"-*-"${suite_name}".json
}

run_suite_with_artifact() {
  local suite_category="$1"
  local suite_name="$2"
  shift 2
  "${REPO_DIR}/tests/run-suite-with-artifact.sh" "${suite_category}" "${suite_name}" "$@"
}

assert_rke2_ubuntu_only() {
  local platform="$1"
  if [[ "${platform}" != "ubuntu" ]]; then
    printf 'rke2 test targets currently support Ubuntu only (requested platform: %s)\n' "${platform}" >&2
    exit 1
  fi
}

run_stack_artifact_test() {
  local distro="$1"
  local platform="$2"
  local image="$3"
  shift 3
  if [[ "${distro}" == "rke2" ]]; then
    assert_rke2_ubuntu_only "${platform}"
  fi
  env \
    PRODUCTIVE_K3S_DISTRO="${distro}" \
    STACK_TEST_PLATFORM="${platform}" \
    STACK_TEST_IMAGE="${image}" \
    bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
}

run_stack_artifact_matrix_k3s() {
  run_stack_artifact_test k3s ubuntu 24.04 "$@" || return $?
  run_stack_artifact_test k3s ubuntu 22.04 "$@" || return $?
  run_stack_artifact_test k3s debian13 https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 "$@" || return $?
  run_stack_artifact_test k3s debian12 https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 "$@"
}

run_stack_artifact_matrix_rke2() {
  run_stack_artifact_test rke2 ubuntu 24.04 "$@" || return $?
  run_stack_artifact_test rke2 ubuntu 22.04 "$@"
}

main() {
  local command="${1:-help}"
  local local_suite_needs_addons="n"

  case "$command" in
    -h|--help|help)
      usage
      ;;
    docs-build)
      shift
      exec "${REPO_DIR}/docs/build.sh" "$@"
      ;;
    docs-serve)
      shift
      exec "${REPO_DIR}/docs/serve.sh" "$@"
      ;;
    docs-up)
      shift
      exec "${REPO_DIR}/docs/serve.sh" --background "$@"
      ;;
    docs-down|docs-clean)
      shift
      exec "${REPO_DIR}/docs/clean.sh" "$@"
      ;;
    test-clean)
      shift
      exec bash "${REPO_DIR}/tests/clean-test-artifacts.sh" "$@"
      ;;
    test-clean-artifacts)
      shift
      exec bash "${REPO_DIR}/tests/clean-test-artifacts.sh" "$@"
      ;;
    test-clean-vms)
      shift
      exec bash "${REPO_DIR}/tests/clean-test-vms.sh" "$@"
      ;;
    test-clean-all)
      shift
      run_tests_make clean-test-state "$@"
      ;;
    test-checkstatus)
      shift
      run_checkstatus matrix "$@"
      ;;
    test-checkstatus-matrix)
      shift
      run_checkstatus matrix "$@"
      ;;
    test-checkstatus-local)
      shift
      run_checkstatus local "$@"
      ;;
    test-checkstatus-external)
      shift
      run_checkstatus external "$@"
      ;;
    test-local-all)
      shift
      local_suite_needs_addons="y"
      if [[ "${local_suite_needs_addons}" == "y" ]]; then
        prepare_addons_repo_checkout
      fi
      clean_suite_category_artifacts local
      run_suite_with_artifact local test-unit make -C "${REPO_DIR}/tests" test-unit
      run_suite_with_artifact local test-lint make -C "${REPO_DIR}/tests" test-lint
      run_suite_with_artifact local test-format make -C "${REPO_DIR}/tests" test-format
      run_suite_with_artifact local test-spell make -C "${REPO_DIR}/tests" test-spell
      run_suite_with_artifact local test-preflight-host bash "${REPO_DIR}/tests/test-preflight-host.sh"
      run_suite_with_artifact local test-arm-support-docs bash "${REPO_DIR}/tests/test-arm-support-docs.sh"
      run_suite_with_artifact local test-bootstrap-modes bash "${REPO_DIR}/tests/test-bootstrap-modes.sh"
      run_suite_with_artifact local test-artifact-tools bash "${REPO_DIR}/tests/test-artifact-tools.sh"
      run_suite_with_artifact local test-in-vm-cleanup-timeout bash "${REPO_DIR}/tests/test-in-vm-cleanup-timeout.sh"
      run_suite_with_artifact local test-productive-k3s-core-cli bash "${REPO_DIR}/tests/test-productive-k3s-core-cli.sh"
      run_suite_with_artifact local test-in-vm-engine-propagation bash "${REPO_DIR}/tests/test-in-vm-engine-propagation.sh"
      exec "${REPO_DIR}/tests/run-suite-with-artifact.sh" local test-agent-smoke bash "${REPO_DIR}/tests/test-agent-in-docker.sh" "$@"
      ;;
    test-external-all)
      shift
      clean_suite_category_artifacts external
      run_suite_with_artifact external test-stacks bash "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-stacks-raw "$@"
      run_suite_with_artifact external test-telemetry-consent bash "${REPO_DIR}/tests/test-telemetry-consent.sh"
      run_suite_with_artifact external test-telemetry-delivery bash "${REPO_DIR}/tests/test-telemetry-delivery.sh"
      run_suite_with_artifact external test-telemetry-default-endpoint bash "${REPO_DIR}/tests/test-telemetry-default-endpoint.sh"
      exec "${REPO_DIR}/tests/run-suite-with-artifact.sh" external test-bootstrap-telemetry-events bash "${REPO_DIR}/tests/test-bootstrap-telemetry-events.sh" "$@"
      ;;
    test-stacks)
      shift
      clean_named_suite_artifacts external test-stacks
      run_suite_with_artifact external test-stacks bash "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-stacks-raw "$@"
      ;;
    test-stacks-raw)
      shift
      "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-stacks-k3s-raw "$@" || exit $?
      exec "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-stacks-rke2-raw "$@"
      ;;
    test-stacks-k3s)
      shift
      clean_named_suite_artifacts external test-stacks-k3s
      run_suite_with_artifact external test-stacks-k3s bash "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-stacks-k3s-raw "$@"
      ;;
    test-stacks-k3s-raw)
      shift
      run_stack_artifact_matrix_k3s "$@"
      ;;
    test-stacks-rke2)
      shift
      clean_named_suite_artifacts external test-stacks-rke2
      run_suite_with_artifact external test-stacks-rke2 bash "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-stacks-rke2-raw "$@"
      ;;
    test-stacks-rke2-raw)
      shift
      run_stack_artifact_matrix_rke2 "$@"
      ;;
    test-stacks-k3s-ubuntu24)
      shift
      exec env PRODUCTIVE_K3S_DISTRO=k3s STACK_TEST_PLATFORM=ubuntu STACK_TEST_IMAGE=24.04 bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
      ;;
    test-stacks-k3s-ubuntu22)
      shift
      exec env PRODUCTIVE_K3S_DISTRO=k3s STACK_TEST_PLATFORM=ubuntu STACK_TEST_IMAGE=22.04 bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
      ;;
    test-stacks-k3s-debian13)
      shift
      exec env PRODUCTIVE_K3S_DISTRO=k3s STACK_TEST_PLATFORM=debian13 STACK_TEST_IMAGE=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
      ;;
    test-stacks-k3s-debian12)
      shift
      exec env PRODUCTIVE_K3S_DISTRO=k3s STACK_TEST_PLATFORM=debian12 STACK_TEST_IMAGE=https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
      ;;
    test-stacks-rke2-ubuntu24)
      shift
      exec env PRODUCTIVE_K3S_DISTRO=rke2 STACK_TEST_PLATFORM=ubuntu STACK_TEST_IMAGE=24.04 bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
      ;;
    test-stacks-rke2-ubuntu22)
      shift
      exec env PRODUCTIVE_K3S_DISTRO=rke2 STACK_TEST_PLATFORM=ubuntu STACK_TEST_IMAGE=22.04 bash "${REPO_DIR}/tests/test-stack-artifact-in-vm.sh" "$@"
      ;;
    test-preflight-host)
      shift
      exec bash "${REPO_DIR}/tests/test-preflight-host.sh" "$@"
      ;;
    test-arm-support-docs)
      shift
      exec bash "${REPO_DIR}/tests/test-arm-support-docs.sh" "$@"
      ;;
    test-bootstrap-modes)
      shift
      exec bash "${REPO_DIR}/tests/test-bootstrap-modes.sh" "$@"
      ;;
    test-artifact-tools)
      shift
      bash "${REPO_DIR}/tests/test-artifact-tools.sh" "$@"
      exec bash "${REPO_DIR}/tests/test-in-vm-cleanup-timeout.sh" "$@"
      ;;
    test-telemetry)
      shift
      exec "${REPO_DIR}/scripts/productive-k3s-core-dev.sh" test-external-all "$@"
      ;;
    test-productive-k3s-core-cli)
      shift
      exec bash "${REPO_DIR}/tests/test-productive-k3s-core-cli.sh" "$@"
      ;;
    test-in-vm-engine-propagation)
      shift
      exec bash "${REPO_DIR}/tests/test-in-vm-engine-propagation.sh" "$@"
      ;;
    test-agent-smoke)
      shift
      exec bash "${REPO_DIR}/tests/test-agent-in-docker.sh" "$@"
      ;;
    test-smoke)
      shift
      exec "${REPO_DIR}/tests/test-in-docker.sh" "$@"
      ;;
    test-core)
      shift
      prepare_addons_repo_checkout
      exec "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile core "$@"
      ;;
    test-rke2-core)
      shift
      prepare_addons_repo_checkout
      exec env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile core "$@"
      ;;
    test-rke2-core-ubuntu22)
      shift
      prepare_addons_repo_checkout
      exec env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 22.04 --profile core "$@"
      ;;
    test-rke2-full)
      shift
      prepare_addons_repo_checkout
      exec env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile full "$@"
      ;;
    test-rke2-full-clean)
      shift
      prepare_addons_repo_checkout
      exec env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile full-clean "$@"
      ;;
    test-rke2-full-rollback)
      shift
      prepare_addons_repo_checkout
      exec env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile full-rollback "$@"
      ;;
    test-rke2-ubuntu-all)
      shift
      prepare_addons_repo_checkout
      env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile core "$@" || exit $?
      env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile full "$@" || exit $?
      env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile full-clean "$@" || exit $?
      exec env PRODUCTIVE_K3S_DISTRO=rke2 "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile full-rollback "$@"
      ;;
    test-core-debian12)
      shift
      prepare_addons_repo_checkout
      exec "${REPO_DIR}/tests/test-in-vm.sh" --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile core "$@"
      ;;
    test-core-debian13)
      shift
      prepare_addons_repo_checkout
      exec "${REPO_DIR}/tests/test-in-vm.sh" --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile core "$@"
      ;;
    test-matrix-smoke)
      shift
      run_tests_make run-smoke-tests "$@"
      ;;
    test-matrix-core)
      shift
      run_tests_make run-core-tests "$@"
      ;;
    test-matrix-full)
      shift
      prepare_addons_repo_checkout
      run_tests_make run-full-tests "$@"
      ;;
    test-matrix-full-rollback)
      shift
      prepare_addons_repo_checkout
      run_tests_make run-full-rollback-tests "$@"
      ;;
    test-matrix-full-clean)
      shift
      prepare_addons_repo_checkout
      run_tests_make run-full-clean-tests "$@"
      ;;
    test-matrix-all)
      shift
      prepare_addons_repo_checkout
      run_tests_make run-all-tests "$@"
      ;;
    *)
      printf 'Unsupported development command: %s\n\n' "$command" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
