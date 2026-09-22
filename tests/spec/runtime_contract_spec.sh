# shellcheck shell=bash disable=SC2016
Describe 'runtime contract helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/runtime-contract.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'renders k3s runtime paths and commands'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=k3s
      PRODUCTIVE_K3S_ENGINE=native
      pk3s_runtime_validate_selection
      printf "label=%s\n" "$(pk3s_runtime_cluster_label)"
      printf "server=%s agent=%s\n" "$(pk3s_runtime_server_service)" "$(pk3s_runtime_agent_service)"
      printf "kubeconfig=%s\n" "$(pk3s_runtime_system_kubeconfig_path)"
      printf "user=%s\n" "$(HOME=/home/demo pk3s_runtime_default_user_kubeconfig_path)"
      printf "ingress=%s\n" "$(pk3s_runtime_default_ingress_class)"
      printf "uninstall=%s\n" "$(pk3s_runtime_uninstall_script_path)"
      printf "killall=%s\n" "$(pk3s_runtime_killall_script_path)"
      printf "embedded=%s mode=%s addon=%s\n" "$(pk3s_runtime_embedded_kubectl_bin)" "$(pk3s_runtime_addon_kubectl_mode)" "$(pk3s_runtime_addon_kubectl_bin)"
      printf "hint=%s\n" "$(pk3s_runtime_kubectl_hint)"
      pk3s_runtime_state_dirs'
    The status should equal 0
    The output should include 'label=k3s'
    The output should include 'server=k3s agent=k3s-agent'
    The output should include 'kubeconfig=/etc/rancher/k3s/k3s.yaml'
    The output should include 'user=/home/demo/.kube/k3s.yaml'
    The output should include 'ingress=traefik'
    The output should include 'uninstall=/usr/local/bin/k3s-uninstall.sh'
    The output should include 'killall=/usr/local/bin/k3s-killall.sh'
    The output should include 'embedded=k3s mode=k3s addon=kubectl'
    The output should include 'hint=sudo k3s kubectl'
    The output should include '/var/lib/rancher/k3s'
  End

  It 'renders rke2 runtime paths and commands'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=rke2
      PRODUCTIVE_K3S_ENGINE=native
      pk3s_runtime_validate_selection
      printf "label=%s\n" "$(pk3s_runtime_cluster_label)"
      printf "server=%s agent=%s\n" "$(pk3s_runtime_server_service)" "$(pk3s_runtime_agent_service)"
      printf "kubeconfig=%s\n" "$(pk3s_runtime_system_kubeconfig_path)"
      printf "ingress=%s\n" "$(pk3s_runtime_default_ingress_class)"
      printf "uninstall=%s\n" "$(pk3s_runtime_uninstall_script_path)"
      printf "killall=%s\n" "$(pk3s_runtime_killall_script_path)"
      printf "embedded=%s mode=%s addon=%s\n" "$(pk3s_runtime_embedded_kubectl_bin)" "$(pk3s_runtime_addon_kubectl_mode)" "$(pk3s_runtime_addon_kubectl_bin)"
      printf "hint=%s\n" "$(pk3s_runtime_kubectl_hint)"
      pk3s_runtime_state_dirs'
    The status should equal 0
    The output should include 'label=rke2'
    The output should include 'server=rke2-server agent=rke2-agent'
    The output should include 'kubeconfig=/etc/rancher/rke2/rke2.yaml'
    The output should include 'ingress=nginx'
    The output should include 'uninstall=/usr/bin/rke2-uninstall.sh'
    The output should include 'killall=/usr/bin/rke2-killall.sh'
    The output should include 'embedded=/var/lib/rancher/rke2/bin/kubectl mode=kubectl addon=/var/lib/rancher/rke2/bin/kubectl'
    The output should include 'hint=sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml'
    The output should include '/var/lib/rancher/rke2'
  End

  It 'dispatches component active checks by mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=k3s
      pk3s_runtime_server_active() { printf "server-active\n"; }
      pk3s_runtime_agent_active() { printf "agent-active\n"; }
      pk3s_runtime_component_active server
      pk3s_runtime_component_active agent'
    The status should equal 0
    The output should include 'server-active'
    The output should include 'agent-active'
  End

  It 'executes kubectl through the selected runtime'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      sudo() { printf "sudo:%s\n" "$*"; }
      PRODUCTIVE_K3S_DISTRO=k3s
      pk3s_runtime_kubectl get nodes
      PRODUCTIVE_K3S_DISTRO=rke2
      pk3s_runtime_kubectl get pods'
    The status should equal 0
    The output should include 'sudo:k3s kubectl get nodes'
    The output should include 'sudo:/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods'
  End

  It 'rejects invalid runtime selections'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=rke2
      PRODUCTIVE_K3S_ENGINE=k3sup
      pk3s_runtime_validate_selection'
    The status should equal 1
    The stderr should include 'Unsupported distro/engine combination: rke2/k3sup'
  End
End
