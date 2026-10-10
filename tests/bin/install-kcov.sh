#!/usr/bin/env bash
set -euo pipefail

KCOV_VERSION="43"
KCOV_ARCHIVE="kcov-v${KCOV_VERSION}.tar.gz"
KCOV_URL="https://github.com/SimonKagstrom/kcov/archive/refs/tags/v${KCOV_VERSION}.tar.gz"
KCOV_SHA256="4cbba86af11f72de0c7514e09d59c7927ed25df7cebdad087f6d3623213b95bf"
KCOV_INSTALL_PREFIX="${KCOV_INSTALL_PREFIX:-${HOME}/.local}"
CI_PYTHON_VERSION="3.11.17"

for command_name in cmake curl python3 sha256sum sudo tar; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "${command_name}" >&2
    exit 127
  }
done

if [[ "${CI:-false}" == "true" ]]; then
  actual_python_version="$(python3 -c 'import platform; print(platform.python_version())')"
  if [[ "${actual_python_version}" != "${CI_PYTHON_VERSION}" ]]; then
    printf 'Expected CI Python %s, found %s\n' "${CI_PYTHON_VERSION}" "${actual_python_version}" >&2
    exit 1
  fi
fi

sudo apt-get update
sudo apt-get install -y \
  binutils-dev \
  build-essential \
  libcurl4-openssl-dev \
  libdw-dev \
  libelf-dev \
  libiberty-dev \
  libssl-dev \
  libstdc++-12-dev \
  zlib1g-dev

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 -fsSL "${KCOV_URL}" -o "${work_dir}/${KCOV_ARCHIVE}"
printf '%s  %s\n' "${KCOV_SHA256}" "${work_dir}/${KCOV_ARCHIVE}" | sha256sum -c -
tar -xzf "${work_dir}/${KCOV_ARCHIVE}" -C "${work_dir}"

cmake \
  -S "${work_dir}/kcov-${KCOV_VERSION}" \
  -B "${work_dir}/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${KCOV_INSTALL_PREFIX}"
cmake --build "${work_dir}/build" --parallel 2
cmake --install "${work_dir}/build"

"${KCOV_INSTALL_PREFIX}/bin/kcov" --version
