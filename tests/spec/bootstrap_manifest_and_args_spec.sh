# shellcheck shell=bash disable=SC2016
Describe 'bootstrap manifest and args'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'parses dry-run and stack mode arguments'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'parse_args --dry-run --mode stack; printf "%s|%s" "$DRY_RUN" "$MODE"'
    The status should equal 0
    The output should equal '1|stack'
  End

  It 'rejects unknown arguments'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'parse_args --wat'
    The status should equal 1
    The output should include 'Unknown argument: --wat'
  End

  It 'rejects unsupported modes'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'parse_args --mode weird'
    The status should equal 1
    The output should include 'Unsupported mode: weird'
  End

  It 'writes a public run manifest with settings and component results'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      RUNS_DIR="$(mktemp -d)"
      DRY_RUN=1
      CURRENT_STEP="testing manifests"
      RUN_STATUS="success"
      manifest_set_setting "bootstrap_mode" "stack"
      manifest_set_setting "telemetry_enabled" "true"
      manifest_set_setting "stack_name" "base"
      manifest_record_cluster_runtime_component "n" "install"
      manifest_complete_cluster_runtime_component "installed"
      manifest_record_component "stack_addons" "unknown" "install"
      manifest_complete_component "stack_addons" "installed" "2 add-on(s)"
      init_run_manifest
      write_run_manifest 0
      cat "$RUN_MANIFEST"'
    The status should equal 0
    The output should include '"mode": "dry-run"'
    The output should include '"bootstrap_mode": "stack"'
    The output should include '"telemetry_enabled": "true"'
    The output should include '"stack_name": "base"'
    The output should include '"cluster_runtime": {"detected_before": "n", "planned_action": "install", "result": "installed"}'
    The output should include '"k3s": {"detected_before": "n", "planned_action": "install", "result": "installed"}'
    The output should include '"stack_addons": {"detected_before": "unknown", "planned_action": "install", "result": "installed"}'
  End

  It 'writes private run context with private settings and component notes'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      RUNS_DIR="$(mktemp -d)"
      DRY_RUN=0
      RUN_STATUS="failed"
      manifest_set_setting "agent_server_url" "https://server.example.local:6443"
      manifest_record_component "stack_addons" "unknown" "install"
      manifest_complete_component "stack_addons" "installed" "2 add-on(s)"
      init_run_manifest
      write_private_run_context 17
      cat "$RUN_PRIVATE_CONTEXT"'
    The status should equal 0
    The output should include '"status": "failed"'
    The output should include '"exit_code": 17'
    The output should include '"agent_server_url": "https://server.example.local:6443"'
    The output should include '"stack_addons": {"note": "2 add-on(s)"}'
  End

End
