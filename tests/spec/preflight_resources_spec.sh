# shellcheck shell=bash disable=SC2016
Describe 'preflight resource guidance'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/preflight-host.sh"

  setup_env() {
    export PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE="$1"
    export PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE="$2"
    export PRODUCTIVE_K3S_PREFLIGHT_ARCH='x86_64'
    export PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT="$3"
    export PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB="$4"
    export PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES="$5"
  }

  cleanup_env() {
    unset PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE
    unset PRODUCTIVE_K3S_PREFLIGHT_ARCH PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT
    unset PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES
  }

  It 'warns in strict mode when full-stack guidance is low'
    os_release="$(mktemp)"
    pid1="$(mktemp)"
    cat >"${os_release}" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
    printf 'systemd\n' >"${pid1}"
    setup_env "${os_release}" "${pid1}" '2' '4194304' '21474836480'

    When run /usr/bin/bash "$SCRIPT" --strict --json-output
    The status should equal 1
    The output should include '"warn_count":4'

    rm -f "${os_release}" "${pid1}"
    cleanup_env
  End

  It 'keeps agent mode as a base-host summary'
    os_release="$(mktemp)"
    pid1="$(mktemp)"
    cat >"${os_release}" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
    printf 'systemd\n' >"${pid1}"
    setup_env "${os_release}" "${pid1}" '1' '1048576' '1073741824'

    When run /usr/bin/bash "$SCRIPT" --mode agent --json-output
    The status should equal 0
    The output should include 'base host checks collected for agent mode'

    rm -f "${os_release}" "${pid1}"
    cleanup_env
  End
End
