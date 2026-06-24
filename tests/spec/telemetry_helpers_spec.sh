# shellcheck shell=bash disable=SC2016
Describe 'bootstrap telemetry helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'escapes JSON control characters'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'json_escape "quote\" slash\\ tab	"'
    The output should include 'quote\" slash\\ tab'
  End

  It 'skips lifecycle emission when telemetry is disabled'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=single-node; TELEMETRY_ENABLED=false; TELEMETRY_ENDPOINT=https://telemetry.invalid; emit_bootstrap_lifecycle_event started success'
    The status should equal 0
  End

  It 'reports stack mode as stack'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=stack; bootstrap_event_mode_name'
    The output should equal 'stack'
  End
End
