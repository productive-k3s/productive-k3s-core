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
      run_cmd_with_retries "flake test" 2 0 flake
      rc=$?
      printf " attempts=%s" "$(cat "${counter_file}")"
      exit "${rc}"'
    The status should equal 0
    The output should include 'attempts=3'
  End

  It 'fails fast when retry timeout is exhausted'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'false_cmd() { return 1; }; run_cmd_with_retries "always fails" 0 0 false_cmd'
    The status should equal 1
  End

  It 'rejects unsupported installation engines'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'PRODUCTIVE_K3S_ENGINE=bad-engine; validate_k3s_engine'
    The status should equal 1
    The output should include 'Unsupported k3s installation engine: bad-engine'
  End

  It 'tracks dry-run reuse install skip and warning buckets'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'DRY_RUN=1; track_reuse "existing k3s"; track_install "helm"; track_skip "rancher"; track_warning "manual DNS needed"; print_dry_run_summary'
    The status should equal 0
    The output should include 'existing k3s'
    The output should include 'helm'
    The output should include 'rancher'
    The output should include 'manual DNS needed'
  End
End
