#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMP_ADDONS_CLONE_DIR=""

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
  PRODUCTIVE_K3S_ADDONS_REPO_REF  Branch or tag to clone from PRODUCTIVE_K3S_ADDONS_REPO_URL (default: main)
EOF
}

cleanup_temp_addons_clone() {
  if [[ -n "${TEMP_ADDONS_CLONE_DIR}" && -d "${TEMP_ADDONS_CLONE_DIR}" ]]; then
    rm -rf "${TEMP_ADDONS_CLONE_DIR}"
  fi
}

prepare_addons_repo_checkout() {
  TEMP_ADDONS_CLONE_DIR="$(mktemp -d)"
  trap cleanup_temp_addons_clone EXIT

  if [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" ]]; then
    [[ -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/addons" && -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/stacks" ]] || {
      printf 'invalid PRODUCTIVE_K3S_ADDONS_REPO_DIR: %s\n' "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}" >&2
      exit 1
    }
    mkdir -p "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons"
    cp -a "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/." \
      "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons/"
  else
    if [[ -z "${PRODUCTIVE_K3S_ADDONS_REPO_URL:-}" ]]; then
      printf 'tests that use productive-k3s-addons require PRODUCTIVE_K3S_ADDONS_REPO_DIR or PRODUCTIVE_K3S_ADDONS_REPO_URL\n' >&2
      exit 1
    fi
    git clone --depth 1 --branch "${PRODUCTIVE_K3S_ADDONS_REPO_REF:-main}" \
      "${PRODUCTIVE_K3S_ADDONS_REPO_URL}" \
      "${TEMP_ADDONS_CLONE_DIR}/productive-k3s-addons" >/dev/null 2>&1
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

run_suite_with_artifact() {
  local suite_category="$1"
  local suite_name="$2"
  shift 2
  "${REPO_DIR}/tests/run-suite-with-artifact.sh" "${suite_category}" "${suite_name}" "$@"
}

main() {
  local command="${1:-help}"

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
      clean_suite_category_artifacts local
      run_suite_with_artifact local test-unit make -C "${REPO_DIR}" test-unit
      run_suite_with_artifact local test-lint make -C "${REPO_DIR}" test-lint
      run_suite_with_artifact local test-format make -C "${REPO_DIR}" test-format
      run_suite_with_artifact local test-spell make -C "${REPO_DIR}" test-spell
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
      run_suite_with_artifact external test-telemetry-consent bash "${REPO_DIR}/tests/test-telemetry-consent.sh"
      run_suite_with_artifact external test-telemetry-delivery bash "${REPO_DIR}/tests/test-telemetry-delivery.sh"
      run_suite_with_artifact external test-telemetry-default-endpoint bash "${REPO_DIR}/tests/test-telemetry-default-endpoint.sh"
      exec "${REPO_DIR}/tests/run-suite-with-artifact.sh" external test-bootstrap-telemetry-events bash "${REPO_DIR}/tests/test-bootstrap-telemetry-events.sh" "$@"
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
