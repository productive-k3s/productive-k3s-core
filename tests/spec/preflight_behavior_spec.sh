# shellcheck shell=bash disable=SC2016
Describe 'preflight behavior'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/preflight-host.sh"

  setup_supported_host() {
    os_release="$(mktemp)"
    pid1="$(mktemp)"
    cat >"${os_release}" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
    printf '%s\n' "$1" >"${pid1}"
    export PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE="${os_release}"
    export PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE="${pid1}"
    export PRODUCTIVE_K3S_PREFLIGHT_ARCH="${2:-x86_64}"
    export PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT='8'
    export PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB='16777216'
    export PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES='214748364800'
  }

  cleanup_host() {
    rm -f "${os_release:-}" "${pid1:-}"
    unset PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE
    unset PRODUCTIVE_K3S_PREFLIGHT_ARCH PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT
    unset PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES
  }

  AfterEach 'cleanup_host >/dev/null 2>&1 || true'

  It 'fails when PID 1 is not systemd'
    setup_supported_host 'init' 'x86_64'

    When run /usr/bin/bash "$SCRIPT" --json-output
    The status should equal 1
    The output should include 'systemd is required as PID 1, detected init'
  End

  It 'fails unsupported architectures even on a supported distribution'
    setup_supported_host 'systemd' 'ppc64le'

    When run /usr/bin/bash "$SCRIPT" --json-output
    The status should equal 1
    The output should include '"architecture":"ppc64le"'
    The output should include '"architecture_support":"unsupported"'
  End

  It 'rejects unsupported mode values'
    setup_supported_host 'systemd' 'x86_64'

    When run /usr/bin/bash "$SCRIPT" --mode weird-mode
    The status should equal 1
    The error should include 'Unsupported mode: weird-mode'
  End

  It 'treats sudo prompts as warnings and fails in strict mode'
    setup_supported_host 'systemd' 'x86_64'

    When run bash -lc '
      script="$1"
      mockdir="$(mktemp -d)"
      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 1
EOF
      chmod +x "${mockdir}/sudo"
      export PATH="${mockdir}:$PATH"
      /usr/bin/bash "${script}" --strict --json-output
    ' bash "$SCRIPT"
    The status should equal 1
    The output should include 'sudo will likely require interactive authentication during bootstrap'
    The output should include '"warn_count":1'
  End
End
