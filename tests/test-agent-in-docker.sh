#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="productive-k3s:test"
BASE_IMAGE="ubuntu:24.04"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

main() {
  need_cmd docker || fail "docker is required"

  cd "$REPO_DIR"
  docker build --build-arg BASE_IMAGE="$BASE_IMAGE" -f tests/Dockerfile.test -t "$IMAGE_TAG" . >/dev/null

  local answers output
  answers=$'y\nhttps://server.example.local:6443\nsuper-secret-token\ny\n'
  output="$(printf '%s' "$answers" | docker run --rm -i "$IMAGE_TAG" bash -lc 'cd /workspace && ./scripts/apply.sh --dry-run --mode agent' 2>&1)" || {
    printf '%s\n' "$output"
    fail "agent dry-run command failed"
  }

  printf '%s\n' "$output" | grep -q "Mode: agent" || fail "agent mode banner missing"
  printf '%s\n' "$output" | grep -q "Agent server URL" || fail "agent server URL prompt missing"
  printf '%s\n' "$output" | grep -q "Agent cluster token" || fail "agent token prompt missing"
  printf '%s\n' "$output" | grep -q "k3s agent" || fail "agent install summary missing"
}

main "$@"
