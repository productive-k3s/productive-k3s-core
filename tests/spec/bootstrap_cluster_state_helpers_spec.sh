# shellcheck shell=bash disable=SC2016
Describe 'bootstrap cluster state helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'selects the active k3s component from the current mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      agent_calls=0
      server_calls=0
      k3s_agent_active() { agent_calls=$((agent_calls + 1)); return 0; }
      k3s_server_active() { server_calls=$((server_calls + 1)); return 0; }
      MODE=agent
      k3s_component_active
      MODE=server
      k3s_component_active
      printf "%s|%s" "$agent_calls" "$server_calls"'
    The status should equal 0
    The output should equal '1|1'
  End

  It 'counts cluster nodes only when the server side is active'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      k3s_server_active() { return 0; }
      kubectl_k3s() { printf "node-1 Ready\nnode-2 Ready\n"; }
      printf "%s|" "$(cluster_node_count)"
      k3s_server_active() { return 1; }
      printf "%s" "$(cluster_node_count)"'
    The status should equal 0
    The output should equal '2|0'
  End

  It 'falls back to hostname output when the cluster api has no primary node ip'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      k3s_server_active() { return 0; }
      kubectl_k3s() { return 0; }
      hostname() {
        if [[ "$1" == "-I" ]]; then
          printf "10.0.0.25 172.16.0.10"
        fi
      }
      get_primary_node_ip'
    The status should equal 0
    The output should equal '10.0.0.25'
  End

  It 'detects the active nfs service name and status'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      systemctl() {
        if [[ "$1" == "list-unit-files" && "$2" == "nfs-server.service" ]]; then
          return 0
        fi
      }
      service_active() { [[ "$1" == "nfs-server" ]]; }
      printf "%s|" "$(nfs_service_name)"
      if nfs_server_active; then
        printf "active"
      else
        printf "inactive"
      fi'
    The status should equal 0
    The output should equal 'nfs-server|active'
  End
End
