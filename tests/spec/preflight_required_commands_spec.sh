# shellcheck shell=bash disable=SC2016
Describe 'preflight required command checks'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/preflight-host.sh"

  setup_fake_path() {
    MOCK_DIR="$(mktemp -d)"
    export PATH="${MOCK_DIR}"
    for cmd in sudo curl getent systemctl tar sha256sum mktemp; do
      /bin/cat >"${MOCK_DIR}/${cmd}" <<'EOF'
#!/bin/sh
exit 0
EOF
      /bin/chmod +x "${MOCK_DIR}/${cmd}"
    done
    /bin/ln -sf /usr/bin/bash "${MOCK_DIR}/bash"
    /bin/ln -sf /usr/bin/tr "${MOCK_DIR}/tr"
    /bin/ln -sf /usr/bin/awk "${MOCK_DIR}/awk"
  }

  cleanup_fake_path() {
    /bin/rm -rf "${MOCK_DIR}"
    unset MOCK_DIR
    PATH="${SHELLSPEC_ORIGINAL_PATH}"
    export PATH
  }

  BeforeEach 'SHELLSPEC_ORIGINAL_PATH=$PATH'
  AfterEach 'cleanup_fake_path >/dev/null 2>&1 || true; unset PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE PRODUCTIVE_K3S_PREFLIGHT_ARCH PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES'

  It 'fails when apt-get is missing'
    os_release="$(mktemp)"
    pid1="$(mktemp)"
    cat >"${os_release}" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
    printf 'systemd\n' >"${pid1}"
    export PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE="${os_release}"
    export PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE="${pid1}"
    export PRODUCTIVE_K3S_PREFLIGHT_ARCH='x86_64'
    export PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT='8'
    export PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB='16777216'
    export PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES='214748364800'
    setup_fake_path

    When run /usr/bin/bash "$SCRIPT" --json-output
    The status should equal 1
    The output should include 'missing required commands: apt-get'

    /bin/rm -f "${os_release}" "${pid1}"
  End
End
