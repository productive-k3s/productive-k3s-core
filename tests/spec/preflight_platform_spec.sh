# shellcheck shell=bash disable=SC2016
Describe 'preflight platform detection'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/preflight-host.sh"

  setup_env() {
    export PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE="$1"
    export PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE="$2"
    export PRODUCTIVE_K3S_PREFLIGHT_ARCH="$3"
    export PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT='8'
    export PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB='16777216'
    export PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES='214748364800'
  }

  cleanup_env() {
    unset PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE
    unset PRODUCTIVE_K3S_PREFLIGHT_ARCH PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT
    unset PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES
  }

  It 'accepts Ubuntu 24.04 amd64'
    os_release="$(mktemp)"
    pid1="$(mktemp)"
    cat >"${os_release}" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
    printf 'systemd\n' >"${pid1}"
    setup_env "${os_release}" "${pid1}" 'x86_64'

    When run /usr/bin/bash "$SCRIPT" --json-output
    The status should equal 0
    The output should include '"support":"supported"'
    The output should include '"architecture_support":"supported"'

    rm -f "${os_release}" "${pid1}"
    cleanup_env
  End

  It 'rejects unsupported distributions'
    os_release="$(mktemp)"
    pid1="$(mktemp)"
    cat >"${os_release}" <<'EOF'
ID=fedora
VERSION_ID="40"
PRETTY_NAME="Fedora 40"
EOF
    printf 'systemd\n' >"${pid1}"
    setup_env "${os_release}" "${pid1}" 'x86_64'

    When run /usr/bin/bash "$SCRIPT" --json-output
    The status should equal 1
    The output should include '"support":"unsupported"'

    rm -f "${os_release}" "${pid1}"
    cleanup_env
  End
End
