# shellcheck shell=bash disable=SC2016
Describe 'bootstrap manifest and args'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/bootstrap-k3s-stack.sh"
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
      manifest_set_setting "rancher_host" "rancher.home.arpa"
      manifest_record_component "k3s" "n" "install"
      manifest_complete_component "k3s" "installed"
      manifest_record_component "clusterissuer" "n" "install"
      manifest_complete_component "clusterissuer" "installed" "letsencrypt-staging"
      init_run_manifest
      write_run_manifest 0
      cat "$RUN_MANIFEST"'
    The status should equal 0
    The output should include '"mode": "dry-run"'
    The output should include '"bootstrap_mode": "stack"'
    The output should include '"telemetry_enabled": "true"'
    The output should not include '"rancher_host": "rancher.home.arpa"'
    The output should include '"clusterissuer": {"detected_before": "n", "planned_action": "install", "result": "installed", "note": "letsencrypt-staging"}'
  End

  It 'writes private run context with private settings and non-clusterissuer notes'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      RUNS_DIR="$(mktemp -d)"
      DRY_RUN=0
      RUN_STATUS="failed"
      manifest_set_setting "rancher_host" "rancher.home.arpa"
      manifest_set_setting "registry_host" "registry.home.arpa"
      manifest_record_component "rancher" "n" "install"
      manifest_complete_component "rancher" "installed" "bootstrap password configured"
      manifest_record_component "clusterissuer" "n" "install"
      manifest_complete_component "clusterissuer" "installed" "letsencrypt-prod"
      init_run_manifest
      write_private_run_context 17
      cat "$RUN_PRIVATE_CONTEXT"'
    The status should equal 0
    The output should include '"status": "failed"'
    The output should include '"exit_code": 17'
    The output should include '"rancher_host": "rancher.home.arpa"'
    The output should include '"registry_host": "registry.home.arpa"'
    The output should include '"rancher": {"note": "bootstrap password configured"}'
    The output should not include 'clusterissuer'
  End

  It 'emits lifecycle events with sent_at and correlation fields'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      capture="${tmpdir}/captured.json"
      cat >"${tmpdir}/send-telemetry-event.sh" <<EOF
#!/usr/bin/env bash
cp "\$1" "${capture}"
EOF
      chmod +x "${tmpdir}/send-telemetry-event.sh"
      SCRIPT_DIR="${tmpdir}"
      TELEMETRY_ENABLED=true
      TELEMETRY_ENDPOINT="https://telemetry.example.test/telemetry"
      TELEMETRY_MARKER="pk3s-public-v1"
      TELEMETRY_SESSION_ID="session-xyz"
      TELEMETRY_PARENT_RUN_ID="parent-xyz"
      RUN_ID="run-xyz"
      MODE="single-node"
      emit_bootstrap_lifecycle_event started started
      cat "${capture}"'
    The status should equal 0
    The output should include '"event_name": "core.bootstrap.single_node.started"'
    The output should include '"sent_at":'
    The output should include '"session_id": "session-xyz"'
    The output should include '"run_id": "run-xyz"'
    The output should include '"parent_run_id": "parent-xyz"'
    The output should include '"result": "started"'
  End
End
