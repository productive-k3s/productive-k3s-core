#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/productive-k3s.sh <command> [args...]
  ./scripts/productive-k3s.sh [bootstrap args...]

Operational commands:
  preflight   Run host compatibility checks before bootstrap
  bootstrap   Run the interactive bootstrap flow
  backup      Capture a host and cluster backup snapshot
  validate    Run the post-bootstrap validator
  help        Show this help

Examples:
  ./scripts/productive-k3s.sh preflight
  ./scripts/productive-k3s.sh preflight --strict
  ./scripts/productive-k3s.sh bootstrap --dry-run
  ./scripts/productive-k3s.sh validate --strict

If no command is provided, or the first argument is an option, the wrapper
defaults to `bootstrap` for release-installer compatibility.
EOF
}

run_preflight() {
  exec "${SCRIPT_DIR}/preflight-host.sh" "$@"
}

run_bootstrap() {
  exec "${SCRIPT_DIR}/bootstrap-k3s-stack.sh" "$@"
}

run_backup() {
  exec "${SCRIPT_DIR}/backup-k3s-stack.sh" "$@"
}

run_validate() {
  local translated_args=()
  while (($# > 0)); do
    case "$1" in
      --json-output)
        translated_args+=(--json)
        ;;
      *)
        translated_args+=("$1")
        ;;
    esac
    shift
  done

  exec "${SCRIPT_DIR}/validate-k3s-stack.sh" "${translated_args[@]}"
}

main() {
  local command="${1:-bootstrap}"

  if (($# == 0)); then
    run_bootstrap
  fi

  case "$command" in
    -h|--help|help)
      usage
      ;;
    preflight)
      shift
      run_preflight "$@"
      ;;
    bootstrap)
      shift
      run_bootstrap "$@"
      ;;
    backup)
      shift
      run_backup "$@"
      ;;
    validate)
      shift
      run_validate "$@"
      ;;
    -*)
      run_bootstrap "$@"
      ;;
    *)
      printf 'Unsupported command: %s\n\n' "$command" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
