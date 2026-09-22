# shellcheck shell=bash disable=SC2016
Describe 'rollback runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/rollback.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'derives stack cleanup plan from the manifest stack name'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      manifest="$(mktemp)"
      cat >"${manifest}" <<EOF
{
  "run_id": "test-run",
  "status": "success",
  "settings": {
    "cluster_distro": "k3s",
    "stack_name": "base"
  },
  "components": {
    "stack_addons": {
      "detected_before": "unknown",
      "planned_action": "install",
      "result": "installed"
    }
  }
}
EOF
      unset PRODUCTIVE_K3S_STACK_NAME
      MANIFEST="${manifest}"
      require_prereqs
      build_plan
      print_plan'
    The status should equal 0
    The output should include "Rollback plan for test-run"
    The output should include "Run clean hooks for stack 'base' add-ons"
  End

End
