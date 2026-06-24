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
ARCHIVE_NAME="productive-k3s-core-${TAG}.tar.gz"
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"
TMP_DIR="$(mktemp -d)"
STAGE_DIR="${TMP_DIR}/productive-k3s-core-${TAG}"
INCLUDE_PATHS=(
  "LICENSE"
  "README.md"
  "productive-k3s-core.sh"
  "scripts/productive-k3s-core.sh"
  "scripts/addons-runtime.sh"
  "scripts/runtime-contract.sh"
  "scripts/component-versions.sh"
  "scripts/preflight-host.sh"
  "scripts/apply.sh"
  "scripts/backup.sh"
  "scripts/validate.sh"
  "scripts/cleanup.sh"
  "scripts/rollback.sh"
  "scripts/send-telemetry.sh"
  "scripts/send-telemetry-event.sh"
)

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
    tar -cf - "${INCLUDE_PATHS[@]}"
  ) | (
    cd "$STAGE_DIR"
    tar -xf -
  )
else
  git -C "$REPO_ROOT" archive --format=tar "$TAG" -- "${INCLUDE_PATHS[@]}" | (
    cd "$STAGE_DIR"
    tar -xf -
  )
fi

cat > "${STAGE_DIR}/bundle-info.json" <<EOF
{
  "schema_version": "1",
  "bundle_name": "productive-k3s-core",
  "bundle_type": "productive-k3s-core",
  "bundle_version": "${TAG}",
  "cli_entrypoint": "productive-k3s-core.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF

tar -czf "$ARCHIVE_PATH" -C "$TMP_DIR" "productive-k3s-core-${TAG}"

printf '%s\n' "$ARCHIVE_PATH"
