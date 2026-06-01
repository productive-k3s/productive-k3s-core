# shellcheck shell=bash disable=SC2016
Describe 'bootstrap package and engine helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/bootstrap-k3s-stack.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'keeps ensure_packages as a no-op when everything is installed'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pkg_installed() { return 0; }
      ensure_packages "Helm installation" curl ca-certificates'
    The status should equal 0
    The output should include 'Required packages for Helm installation are already installed.'
  End

  It 'installs missing packages through dry-run commands'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      pkg_installed() { [[ "$1" == "curl" ]]; }
      prompt_yesno() { printf -v "$1" y; }
      ensure_packages "Longhorn" curl jq open-iscsi'
    The status should equal 0
    The output should include 'Missing OS packages for Longhorn: jq open-iscsi'
    The output should include '[dry-run] Updating apt indexes for Longhorn'
    The output should include 'sudo apt-get install -y jq open-iscsi'
  End

  It 'rejects missing packages when the operator declines'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pkg_installed() { return 1; }
      prompt_yesno() { printf -v "$1" n; }
      ensure_packages "Longhorn" jq'
    The status should equal 1
    The output should include 'Cannot continue with Longhorn without those packages.'
  End

  It 'enables iscsid when it is inactive'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      service_active() { return 1; }
      prompt_yesno() { printf -v "$1" y; }
      ensure_iscsid'
    The status should equal 0
    The output should include '[dry-run] Enabling and starting iscsid'
  End

  It 'skips iscsid enablement after a negative answer'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      service_active() { return 1; }
      prompt_yesno() { printf -v "$1" n; }
      ensure_iscsid'
    The status should equal 0
    The output should include "Longhorn requires 'iscsid'"
  End

  It 'installs k3sup in dry-run mode when missing'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      need_cmd() { return 1; }
      install_k3sup_if_needed'
    The status should equal 0
    The output should include 'Installing k3sup...'
    The output should include 'curl -sLS https://get.k3sup.dev | sh'
    The output should include 'sudo install k3sup /usr/local/bin/'
  End

  It 'installs a server with native k3s in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      MODE=single-node
      install_k3s_with_native'
    The status should equal 0
    The output should include 'Installing k3s (v1.36.1+k3s1)'
    The output should include 'INSTALL_K3S_VERSION=v1.36.1+k3s1'
  End

  It 'installs an agent with native k3s in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      MODE=agent
      AGENT_SERVER_URL=https://server.example.local:6443
      AGENT_CLUSTER_TOKEN=token-1
      install_k3s_with_native'
    The status should equal 0
    The output should include 'Installing k3s agent'
    The output should include 'K3S_URL=https://server.example.local:6443'
    The output should include 'K3S_TOKEN=token-1'
    The output should include 'INSTALL_K3S_EXEC=agent'
    The output should include 'INSTALL_K3S_VERSION=v1.36.1+k3s1'
  End

  It 'requires agent connection details for native agent installs'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      MODE=agent
      AGENT_SERVER_URL=""
      AGENT_CLUSTER_TOKEN=""
      install_k3s_with_native'
    The status should equal 1
    The output should include 'Agent mode requires both the server URL and cluster token.'
  End

  It 'builds k3sup ssh and remote target args'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_SSH_KEY_PATH=/tmp/id_ed25519
      PRODUCTIVE_K3S_SSH_PORT=2222
      PRODUCTIVE_K3S_SSH_HOST=10.0.0.10
      PRODUCTIVE_K3S_SSH_USER=ubuntu
      printf "%s\n__SEP__\n%s" "$(tr "\0" " " < <(k3sup_ssh_args))" "$(k3sup_remote_target_args --ip)"'
    The status should equal 0
    The output should include '--ssh-key /tmp/id_ed25519'
    The output should include '--ssh-port 2222'
    The output should include '--ip 10.0.0.10'
    The output should include '--user ubuntu'
  End

  It 'requires a k3sup remote host'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_SSH_HOST=""
      PRODUCTIVE_K3S_SSH_USER=ubuntu
      k3sup_remote_target_args --host'
    The status should equal 1
    The output should include 'PRODUCTIVE_K3S_SSH_HOST'
  End

  It 'installs k3s with k3sup in single-node mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      MODE=single-node
      install_k3s_with_k3sup'
    The status should equal 0
    The output should include 'k3sup install --local --local-path'
    The output should include 'productive-k3s-single-node'
    The output should include '--k3s-version v1.36.1+k3s1'
  End

  It 'joins an agent with k3sup in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      MODE=agent
      AGENT_SERVER_URL=https://server.example.local:6443
      AGENT_CLUSTER_TOKEN=token-1
      PRODUCTIVE_K3S_SSH_HOST=10.0.0.20
      PRODUCTIVE_K3S_SSH_USER=ubuntu
      PRODUCTIVE_K3S_SSH_PORT=2222
      install_k3s_with_k3sup'
    The status should equal 0
    The output should include 'Joining k3s agent with k3sup'
    The output should include 'k3sup join'
    The output should include '--server-ip server.example.local'
    The output should include '--server-user ubuntu'
    The output should include '--k3s-version v1.36.1+k3s1'
  End

  It 'installs Helm through the official script in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      install_helm_if_needed install'
    The status should equal 0
    The output should include 'Installing Helm (v3.21.0)...'
    The output should include 'raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3'
    The output should include 'DESIRED_VERSION=v3.21.0'
  End

  It 'adds a Helm repo in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      ensure_helm_repo rancher-latest https://releases.rancher.com/server-charts/latest'
    The status should equal 0
    The output should include '[dry-run] Adding Helm repo rancher-latest'
    The output should include 'helm repo add rancher-latest https://releases.rancher.com/server-charts/latest'
  End
End
