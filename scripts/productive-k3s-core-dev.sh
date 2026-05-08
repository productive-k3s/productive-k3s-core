#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
  test-bootstrap-modes
  test-artifact-tools
  test-productive-k3s-core-cli
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
EOF
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
    test-bootstrap-modes)
      shift
      exec bash "${REPO_DIR}/tests/test-bootstrap-modes.sh" "$@"
      ;;
    test-artifact-tools)
      shift
      exec bash "${REPO_DIR}/tests/test-artifact-tools.sh" "$@"
      ;;
    test-productive-k3s-core-cli)
      shift
      exec bash "${REPO_DIR}/tests/test-productive-k3s-core-cli.sh" "$@"
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
      exec "${REPO_DIR}/tests/test-in-vm.sh" --platform ubuntu --image 24.04 --profile core "$@"
      ;;
    test-core-debian12)
      shift
      exec "${REPO_DIR}/tests/test-in-vm.sh" --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile core "$@"
      ;;
    test-core-debian13)
      shift
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
      run_tests_make run-full-tests "$@"
      ;;
    test-matrix-full-rollback)
      shift
      run_tests_make run-full-rollback-tests "$@"
      ;;
    test-matrix-full-clean)
      shift
      run_tests_make run-full-clean-tests "$@"
      ;;
    test-matrix-all)
      shift
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
