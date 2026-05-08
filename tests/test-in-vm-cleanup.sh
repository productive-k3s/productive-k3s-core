#!/usr/bin/env bash
set -euo pipefail

PREFIX="productive-k3s-core-test-"
PURGE="n"
TARGET=""
ALL="n"

usage() {
  cat <<'EOU'
Usage:
  ./tests/test-in-vm-cleanup.sh --name <vm-name> [--purge]
  ./tests/test-in-vm-cleanup.sh --all [--purge]

Notes:
  - Requires Multipass on the host.
  - --all deletes only VMs whose name starts with productive-k3s-core-test-
EOU
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '[INFO] %s\n' "$1"
}

err() {
  printf '[ERROR] %s\n' "$1" >&2
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
  multipass delete "$name"
}

main() {
  parse_args "$@"
  need_cmd multipass || { err "multipass is required"; exit 1; }

  if [[ "$ALL" == "y" ]]; then
    mapfile -t targets < <(multipass list --format csv | awk -F, -v p="$PREFIX" 'NR>1 && index($1,p)==1 {print $1}')
    if [[ ${#targets[@]} -eq 0 ]]; then
      log "No test VMs found with prefix $PREFIX"
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
    multipass purge
  fi
}

main "$@"
