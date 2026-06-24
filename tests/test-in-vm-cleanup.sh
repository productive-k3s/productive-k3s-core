#!/usr/bin/env bash
set -euo pipefail

PREFIXES=(
  "productive-k3s-core-test-"
  "pk3s-stack-"
)
PURGE="n"
TARGET=""
ALL="n"
VM_CLEANUP_TIMEOUT_SECONDS="${VM_CLEANUP_TIMEOUT_SECONDS:-120}"

usage() {
  cat <<'EOU'
Usage:
  ./tests/test-in-vm-cleanup.sh --name <vm-name> [--purge]
  ./tests/test-in-vm-cleanup.sh --all [--purge]

Notes:
  - Requires Multipass on the host.
  - --all deletes only VMs whose name starts with one of:
      - productive-k3s-core-test-
      - pk3s-stack-
EOU
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

err() {
  printf '[ERROR] %s\n' "$1" >&2
}

run_multipass_cleanup() {
  local subcommand="$1"
  shift || true

  if command -v timeout >/dev/null 2>&1; then
    if timeout --kill-after=5s "${VM_CLEANUP_TIMEOUT_SECONDS}s" multipass "${subcommand}" "$@" >/dev/null 2>&1; then
      return 0
    fi
    warn "multipass ${subcommand} timed out after ${VM_CLEANUP_TIMEOUT_SECONDS}s; continuing"
    return 0
  fi

  multipass "${subcommand}" "$@" >/dev/null 2>&1 || true
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --name)
        TARGET="${2:-}"
        shift
        ;;
      --all)
        ALL="y"
        ;;
      --purge)
        PURGE="y"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  if [[ "$ALL" != "y" && -z "$TARGET" ]]; then
    err "You must pass --name <vm-name> or --all"
    usage
    exit 1
  fi
}

cleanup_one() {
  local name="$1"
  log "Deleting VM: $name"
  run_multipass_cleanup delete "$name"
}

main() {
  parse_args "$@"
  need_cmd multipass || { err "multipass is required"; exit 1; }

  if [[ "$ALL" == "y" ]]; then
    mapfile -t targets < <(
      if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=5s "${VM_CLEANUP_TIMEOUT_SECONDS}s" multipass list --format csv 2>/dev/null || true
      else
        multipass list --format csv 2>/dev/null || true
      fi | awk -F, '
        NR == 1 { next }
        index($1, "productive-k3s-core-test-") == 1 || index($1, "pk3s-stack-") == 1 { print $1 }
      '
    )
    if [[ ${#targets[@]} -eq 0 ]]; then
      log "No test VMs found with the known test prefixes"
      exit 0
    fi
    for name in "${targets[@]}"; do
      cleanup_one "$name"
    done
  else
    cleanup_one "$TARGET"
  fi

  if [[ "$PURGE" == "y" ]]; then
    log "Purging deleted Multipass instances"
    run_multipass_cleanup purge
  fi
}

main "$@"
