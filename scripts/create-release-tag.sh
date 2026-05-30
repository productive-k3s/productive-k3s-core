#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/create-release-tag.sh <core-version>

Example:
  ./scripts/create-release-tag.sh 0.9.1
EOF
}

err() {
  printf '%s\n' "$*" >&2
}

git_config_or_empty() {
  local key="$1"
  git -C "${REPO_ROOT}" config --get "${key}" 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${PRODUCTIVE_K3S_CORE_REPO_DIR:-}"
if [[ -z "${REPO_ROOT}" ]]; then
  if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  fi
fi

VERSION="${1:-${VERSION:-}}"
if [[ -z "${VERSION}" || $# -gt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  err "invalid productive-k3s-core version: ${VERSION}"
  err "expected X.Y.Z"
  exit 1
fi

tag="${VERSION}"
if git -C "${REPO_ROOT}" rev-parse --verify "refs/tags/${tag}" >/dev/null 2>&1; then
  err "tag already exists locally: ${tag}"
  exit 1
fi

git_user_name="$(git_config_or_empty user.name)"
git_user_email="$(git_config_or_empty user.email)"

if [[ -z "${git_user_name}" ]]; then
  git_user_name="${PRODUCTIVE_K3S_RELEASE_GIT_NAME:-productive-k3s-core release automation}"
fi

if [[ -z "${git_user_email}" ]]; then
  git_user_email="${PRODUCTIVE_K3S_RELEASE_GIT_EMAIL:-productive-k3s-core@local.invalid}"
fi

git -C "${REPO_ROOT}" \
  -c user.name="${git_user_name}" \
  -c user.email="${git_user_email}" \
  tag -a "${tag}" -m "Release ${tag}" HEAD
printf 'Created tag %s\n' "${tag}"
printf 'Next: git push origin %s\n' "${tag}"
