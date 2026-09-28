# shellcheck shell=bash disable=SC2016
Describe 'bootstrap runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'keeps explicit telemetry settings untouched'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'TELEMETRY_ENABLED=true; resolve_telemetry_enabled; printf "%s" "$TELEMETRY_ENABLED"'
    The status should equal 0
    The output should equal 'true'
  End

  It 'disables telemetry automatically in non-interactive sessions'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'unset TELEMETRY_ENABLED; can_use_tty() { return 1; }; resolve_telemetry_enabled; printf "%s" "$TELEMETRY_ENABLED"'
    The status should equal 0
    The output should equal 'false'
  End

  It 'reads non-interactive prompt defaults and invalid yes/no defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      printf "\nmaybe\n" | {
        prompt chosen "default-value" "Value?"
        prompt_yesno answer "n" "Continue?"
        printf "chosen=%s answer=%s\n" "${chosen}" "${answer}"
      }'
    The status should equal 0
    The output should include 'Value? [default-value]: Continue? [n] (y/n):'
    The output should include 'chosen=default-value answer=n'
    The output should include 'Invalid input, using default: n'
  End

  It 'tracks and cleans up sudo keepalive processes'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      mockbin="${tmpdir}/bin"
      mkdir -p "${mockbin}"
      cat >"${mockbin}/sudo" <<EOF
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${mockbin}/sudo"
      PATH="${mockbin}:$PATH"
      sudo_keepalive
      [[ -n "${SUDO_KA_PID}" ]]
      cleanup_exit
      printf "pid=%s\n" "${SUDO_KA_PID}"'
    The status should equal 0
    The output should include 'pid='
  End

  It 'skips package installation when dependencies are already present'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pkg_installed() { return 0; }
      ensure_packages "demo" curl tar'
    The status should equal 0
    The output should include 'Required packages for demo are already installed.'
  End

  It 'fails package installation when missing dependencies are declined'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pkg_installed() { return 1; }
      prompt_yesno() { printf -v "$1" n; }
      ensure_packages "demo" curl tar'
    The status should equal 1
    The output should include 'Missing OS packages for demo: curl tar'
    The output should include 'Cannot continue with demo without those packages.'
  End

  It 'prints dry-run package installation commands when dependencies are accepted'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      pkg_installed() { return 1; }
      prompt_yesno() { printf -v "$1" y; }
      ensure_packages "demo" curl'
    The status should equal 0
    The output should include '[dry-run] Updating apt indexes for demo'
    The output should include 'sudo apt-get update -y'
    The output should include '[dry-run] Installing packages for demo'
    The output should include 'sudo apt-get install -y curl'
  End

  It 'reports dry-run results through result_for_mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'DRY_RUN=1; result_for_mode success'
    The status should equal 0
    The output should equal 'dry-run'
  End

  It 'retries commands until they succeed'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      counter_file="$(mktemp)"
      flake() {
        local count=0
        if [[ -f "${counter_file}" ]]; then
          count="$(cat "${counter_file}")"
        fi
        count=$((count + 1))
        printf "%s" "${count}" >"${counter_file}"
        [[ "${count}" -ge 3 ]]
      }
      run_shell() { flake; }
      run_shell_with_retries "flake test" 2 0 ignored
      rc=$?
      printf " attempts=%s" "$(cat "${counter_file}")"
      exit "${rc}"'
    The status should equal 0
    The output should include 'attempts=3'
  End

  It 'fails fast when retry timeout is exhausted'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'run_shell() { return 1; }; run_shell_with_retries "always fails" 0 0 ignored'
    The status should equal 1
  End

  It 'retries cluster node inspection after transient API refusal'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      counter_file="$(mktemp)"
      kubectl_k3s() {
        local count=0
        if [[ -f "${counter_file}" ]]; then
          count="$(cat "${counter_file}")"
        fi
        count=$((count + 1))
        printf "%s" "${count}" >"${counter_file}"
        if [[ "${count}" -lt 3 ]]; then
          printf "The connection to the server 127.0.0.1:6443 was refused\n" >&2
          return 1
        fi
        printf "node1 Ready control-plane 1d v1\n"
      }
      sleep() { :; }
      inspect_cluster_nodes_with_retries 5 0
      printf " attempts=%s" "$(cat "${counter_file}")"'
    The status should equal 0
    The output should include 'node1 Ready control-plane 1d v1'
    The output should include 'attempts=3'
    The output should include 'API was ready but node inspection failed; retrying'
    The stderr should include 'The connection to the server 127.0.0.1:6443 was refused'
  End

  It 'rejects unsupported installation engines'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'PRODUCTIVE_K3S_ENGINE=bad-engine; validate_runtime_engine'
    The status should equal 1
    The output should include 'Unsupported cluster installation engine: bad-engine'
  End

  It 'rejects unsupported distro and engine combinations'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'PRODUCTIVE_K3S_DISTRO=rke2; PRODUCTIVE_K3S_ENGINE=k3sup; validate_runtime_engine'
    The status should equal 1
    The output should include 'Unsupported cluster distro/engine selection: rke2/k3sup'
    The stderr should include 'Unsupported distro/engine combination: rke2/k3sup'
  End

  It 'records and completes manifest components'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      manifest_record_component runtime missing install
      manifest_complete_component runtime installed ok
      printf "%s|%s|%s" "${MANIFEST_DETECTED[runtime]}" "${MANIFEST_RESULT[runtime]}" "${MANIFEST_NOTES[runtime]}"'
    The status should equal 0
    The output should equal 'missing|installed|ok'
  End
End
