#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build-release-bundle.sh <tag> <output-dir>

Example:
  ./scripts/build-release-bundle.sh 1.2.3 dist
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

TAG="$1"
OUTPUT_DIR="$2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_NAME="productive-k3s-${TAG}.tar.gz"
PREFIX="productive-k3s-${TAG}/"
TMP_DIR="$(mktemp -d)"
STAGE_DIR="${TMP_DIR}/productive-k3s-${TAG}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$STAGE_DIR"

git -C "$REPO_ROOT" rev-parse --verify "${TAG}^{tag}" >/dev/null 2>&1 || \
git -C "$REPO_ROOT" rev-parse --verify "${TAG}^{commit}" >/dev/null 2>&1 || {
  echo "Tag or ref not found: $TAG" >&2
  exit 1
}

if [[ "$TAG" == "HEAD" ]]; then
  (
    cd "$REPO_ROOT"
    tar \
      --exclude=.git \
      --exclude=.codex \
      --exclude=dist \
      --exclude=runs \
      --exclude=test-artifacts \
      --exclude=docs/.venv \
      --exclude=docs/site \
      -cf - .
  ) | (
    cd "$STAGE_DIR"
    tar -xf -
  )
else
  git -C "$REPO_ROOT" archive --format=tar "$TAG" | (
    cd "$STAGE_DIR"
    tar -xf -
  )
fi

cat > "${STAGE_DIR}/bundle-info.json" <<EOF
{
  "schema_version": "1",
  "bundle_name": "productive-k3s",
  "bundle_type": "productive-k3s",
  "bundle_version": "${TAG}",
  "cli_entrypoint": "productive-k3s.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF

tar -C "$TMP_DIR" -czf "${OUTPUT_DIR}/${ARCHIVE_NAME}" "productive-k3s-${TAG}"

printf '%s\n' "${OUTPUT_DIR}/${ARCHIVE_NAME}"
