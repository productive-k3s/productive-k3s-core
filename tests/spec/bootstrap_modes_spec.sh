# shellcheck shell=bash disable=SC2016
Describe 'bootstrap mode helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/bootstrap-k3s-stack.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'treats single-node as single-node defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=single-node; mode_uses_single_node_defaults'
    The status should equal 0
  End

  It 'treats stack as single-node defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=stack; mode_uses_single_node_defaults'
    The status should equal 0
  End

  It 'does not treat server as single-node defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=server; mode_uses_single_node_defaults'
    The status should equal 1
  End

  It 'does not treat agent as single-node defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=agent; mode_uses_single_node_defaults'
    The status should equal 1
  End

  It 'normalizes lifecycle event names'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'MODE=single-node; bootstrap_event_mode_name'
    The output should equal 'single_node'
  End
End
