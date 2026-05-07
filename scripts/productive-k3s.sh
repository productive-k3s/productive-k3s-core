#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/productive-k3s.sh <command> [args...]
  ./scripts/productive-k3s.sh [bootstrap args...]

Operational commands:
  bundle      Show bundle metadata for automation
  preflight   Run host compatibility checks before bootstrap
  bootstrap   Run the interactive bootstrap flow
  backup      Capture a host and cluster backup snapshot
  validate    Run the post-bootstrap validator
  help        Show this help

Examples:
  ./scripts/productive-k3s.sh bundle info --json
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

bundle_info_path() {
  local repo_root
  repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
  printf '%s\n' "${repo_root}/bundle-info.json"
}

resolve_bundle_version_fallback() {
  local repo_root version
  repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
  if version="$(git -C "$repo_root" describe --tags --exact-match 2>/dev/null)"; then
    printf '%s\n' "$version"
    return 0
  fi

  if version="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null)"; then
    printf '%s\n' "$version"
    return 0
  fi

  return 1
}

print_bundle_info_json() {
  local info_path version
  info_path="$(bundle_info_path)"
  if [[ -f "$info_path" ]]; then
    cat "$info_path"
    return 0
  fi

  if ! version="$(resolve_bundle_version_fallback)"; then
    printf 'Unable to resolve bundle metadata\n' >&2
    return 1
  fi

  cat <<EOF
{
  "schema_version": "1",
  "bundle_name": "productive-k3s",
  "bundle_type": "productive-k3s",
  "bundle_version": "${version}",
  "cli_entrypoint": "productive-k3s.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF
}

run_bundle() {
  if (($# != 2)) || [[ "$1" != "info" || "$2" != "--json" ]]; then
    printf 'Usage: ./scripts/productive-k3s.sh bundle info --json\n' >&2
    return 2
  fi
  print_bundle_info_json
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
    bundle)
      shift
      run_bundle "$@"
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
