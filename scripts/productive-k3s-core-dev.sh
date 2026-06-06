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
  test-checkstatus
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
      run_tests_make clean-test-state "$@"
      ;;
    test-checkstatus)
      shift
      run_tests_make check-test-status "$@"
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
      bash "${REPO_DIR}/tests/test-telemetry-consent.sh" "$@"
      bash "${REPO_DIR}/tests/test-telemetry-delivery.sh" "$@"
      bash "${REPO_DIR}/tests/test-telemetry-default-endpoint.sh" "$@"
      exec bash "${REPO_DIR}/tests/test-bootstrap-telemetry-events.sh" "$@"
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
