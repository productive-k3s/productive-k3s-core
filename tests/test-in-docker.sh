#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="productive-k3s:test"
BASE_IMAGE="ubuntu:24.04"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOU'
Usage:
  ./tests/test-in-docker.sh [--image-tag <tag>] [--base-image <image>]

What it does:
  - build the test image
  - run bootstrap in --dry-run mode inside the container

Notes:
  - This is a containerized smoke harness, not a Docker build-time install.
  - It validates the bootstrap flow, prompts, dry-run behavior, and run manifest generation.
  - It does not perform a real k3s installation inside the container.
EOU
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --image-tag)
        IMAGE_TAG="${2:-}"
        shift
        ;;
      --base-image)
        BASE_IMAGE="${2:-}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

resolve_addons_repo_dir() {
  if [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" && -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/addons" ]]; then
    printf '%s\n' "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}"
    return 0
  fi

  local sibling_dir
  sibling_dir="$(cd "${REPO_DIR}/.." && pwd)/productive-k3s-addons"
  if [[ -d "${sibling_dir}/addons" ]]; then
    printf '%s\n' "${sibling_dir}"
    return 0
  fi

  return 1
}

prepare_addons_repo_dir() {
  local resolved_dir
  if resolved_dir="$(resolve_addons_repo_dir)"; then
    ADDONS_REPO_DIR_IS_TEMP=0
    printf '%s\n' "${resolved_dir}"
    return 0
  fi

  local repo_url repo_ref temp_dir
  repo_url="${PRODUCTIVE_K3S_ADDONS_REPO_URL:-https://github.com/productive-k3s/productive-k3s-addons.git}"
  repo_ref="${PRODUCTIVE_K3S_ADDONS_REPO_REF:-development}"
  temp_dir="$(mktemp -d)"
  git clone --depth 1 --branch "${repo_ref}" "${repo_url}" "${temp_dir}" >/dev/null 2>&1
  ADDONS_REPO_DIR_IS_TEMP=1
  printf '%s\n' "${temp_dir}"
}

run_smoke() {
  local answers
  local addons_repo_dir
  answers=$'y\ny\nn\nn\nn\nn\ny\nn\ny\n'
  addons_repo_dir="$(prepare_addons_repo_dir)"
  trap 'if [[ "${ADDONS_REPO_DIR_IS_TEMP:-0}" == "1" ]]; then rm -rf "${addons_repo_dir}"; fi' RETURN
  printf '%s' "$answers" | docker run --rm -i \
    -e PRODUCTIVE_K3S_ADDONS_REPO_DIR=/tmp/productive-k3s-addons \
    -v "${addons_repo_dir}:/tmp/productive-k3s-addons:ro" \
    "$IMAGE_TAG" bash -lc 'cd /workspace && ./scripts/apply.sh --dry-run --mode single-node'
}

main() {
  parse_args "$@"

  need_cmd docker || { echo "docker is required" >&2; exit 1; }
  need_cmd git || { echo "git is required" >&2; exit 1; }

  echo "[INFO] Building test image: $IMAGE_TAG"
  echo "[INFO] Base image: $BASE_IMAGE"
  cd "$REPO_DIR"
  docker build --build-arg BASE_IMAGE="$BASE_IMAGE" -f tests/Dockerfile.test -t "$IMAGE_TAG" .

  echo "[INFO] Running smoke test"
  run_smoke

  echo "[INFO] Container test completed successfully"
}

main "$@"
