# shellcheck shell=bash disable=SC2016
Describe 'bootstrap cluster runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'selects the active runtime component from the requested mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      agent_calls=0
      server_calls=0
      pk3s_runtime_agent_active() { agent_calls=$((agent_calls + 1)); return 0; }
      pk3s_runtime_server_active() { server_calls=$((server_calls + 1)); return 0; }
      pk3s_runtime_component_active agent
      pk3s_runtime_component_active server
      printf "%s|%s" "$agent_calls" "$server_calls"'
    The status should equal 0
    The output should equal '1|1'
  End

  It 'maps runtime service names for k3s and rke2'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=k3s
      printf "%s/%s|" "$(pk3s_runtime_server_service)" "$(pk3s_runtime_agent_service)"
      PRODUCTIVE_K3S_DISTRO=rke2
      printf "%s/%s" "$(pk3s_runtime_server_service)" "$(pk3s_runtime_agent_service)"'
    The status should equal 0
    The output should equal 'k3s/k3s-agent|rke2-server/rke2-agent'
  End

  It 'maps runtime kubeconfig paths for k3s and rke2'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      HOME=/tmp/operator
      PRODUCTIVE_K3S_DISTRO=k3s
      printf "%s|%s|" "$(pk3s_runtime_system_kubeconfig_path)" "$(pk3s_runtime_default_user_kubeconfig_path)"
      PRODUCTIVE_K3S_DISTRO=rke2
      printf "%s|%s" "$(pk3s_runtime_system_kubeconfig_path)" "$(pk3s_runtime_default_user_kubeconfig_path)"'
    The status should equal 0
    The output should equal '/etc/rancher/k3s/k3s.yaml|/tmp/operator/.kube/k3s.yaml|/etc/rancher/rke2/rke2.yaml|/tmp/operator/.kube/rke2.yaml'
  End
End
