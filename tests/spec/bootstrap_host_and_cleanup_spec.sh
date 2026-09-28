# shellcheck shell=bash disable=SC2016
Describe 'bootstrap host helpers and cleanup'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'skips telemetry delivery when telemetry is disabled'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'TELEMETRY_ENABLED=false; maybe_send_telemetry 0; printf "done"'
    The status should equal 0
    The output should equal 'done'
  End

  It 'invokes the telemetry sender with propagated context'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      RUN_MANIFEST="${tmpdir}/manifest.json"
      cat >"${RUN_MANIFEST}" <<EOF
{"status":"success"}
EOF
      cat >"${tmpdir}/send-telemetry.sh" <<EOF
#!/usr/bin/env bash
printf "endpoint=%s|run=%s|parent=%s|exit=%s|manifest=%s" "\$TELEMETRY_ENDPOINT" "\$TELEMETRY_RUN_ID" "\$TELEMETRY_PARENT_RUN_ID" "\$TELEMETRY_EXIT_CODE" "\$1"
EOF
      chmod +x "${tmpdir}/send-telemetry.sh"
      SCRIPT_DIR="${tmpdir}"
      TELEMETRY_ENABLED=true
      TELEMETRY_ENDPOINT="https://telemetry.example.test/telemetry"
      TELEMETRY_SESSION_ID="session-123"
      TELEMETRY_PARENT_RUN_ID="parent-123"
      RUN_ID="run-123"
      maybe_send_telemetry 9'
    The status should equal 0
    The output should include 'endpoint=https://telemetry.example.test/telemetry'
    The output should include 'run=run-123'
    The output should include 'parent=parent-123'
    The output should include 'exit=9'
    The output should include 'manifest='
  End

  It 'marks cleanup as failed and warns when telemetry delivery fails'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      RUN_STATUS="running"
      SUDO_KA_PID=""
      write_run_manifest() { printf "manifest:%s|" "$1"; }
      write_private_run_context() { printf "private:%s|" "$1"; }
      maybe_send_telemetry() { return 1; }
      set +e
      false
      cleanup_exit
      printf "status=%s" "$RUN_STATUS"'
    The status should equal 0
    The output should include 'manifest:1|'
    The output should include 'private:1|'
    The output should include 'Telemetry delivery did not complete successfully'
    The output should include 'status=failed'
  End
End
