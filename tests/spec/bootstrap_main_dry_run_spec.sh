# shellcheck shell=bash disable=SC2016
Describe 'bootstrap dry-run main flows'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'runs a default core-only dry-run bootstrap plan'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_runs="$(mktemp -d)"
      RUNS_DIR="${temp_runs}"
      bind_stdin_to_tty() { :; }
      sudo_keepalive() { :; }
      resolve_telemetry_enabled() { TELEMETRY_ENABLED=false; }
      emit_bootstrap_lifecycle_event() { :; }
      maybe_send_telemetry() { return 0; }
      pkg_installed() { return 1; }
      service_active() { return 1; }
      need_cmd() {
        case "$1" in
          helm|kubectl|docker) return 1 ;;
          *) command -v "$1" >/dev/null 2>&1 ;;
        esac
      }
      namespace_exists() { return 1; }
      deployment_exists() { return 1; }
      secret_exists() { return 1; }
      storageclass_exists() { [[ "$1" == "local-path" ]] && return 0; return 1; }
      clusterissuer_exists() { return 1; }
      helm_release_exists() { return 1; }
      nfs_export_exists() { return 1; }
      mount_exists() { return 1; }
      addon_source_script_exists() { return 0; }
      run_addon_source_hook() { printf "hook:%s|" "$1"; return 0; }
      confirm_preflight() { return 0; }
      prompt_yesno() {
        case "$1" in
          INSTALL_K3S|INSTALL_HELM|INSTALL_LONGHORN|INSTALL_RANCHER|INSTALL_REGISTRY|INSTALL_CERT_MANAGER|ENABLE_NFS|RANCHER_MANAGE_LOCAL_HOSTS|REGISTRY_MANAGE_LOCAL_HOSTS|REGISTRY_TRUST_DOCKER|PROCEED_WITH_PLAN|create_issuer|make_default_sc|install_pkgs|REGISTRY_AUTH_ENABLED)
            printf -v "$1" y ;;
          REUSE_EXISTING_NFS)
            printf -v "$1" n ;;
          *)
            printf -v "$1" "$2" ;;
        esac
      }
      prompt() { printf -v "$1" "%s" "$2"; }
      main --dry-run'
    The status should equal 0
    The output should include 'Mode: server'
    The output should include 'Planned actions'
    The output should include '[dry-run] Installing k3s (v1.35.5+k3s1)'
    The output should include '[dry-run] Installing Helm'
    The output should not include "Processing stack addon 'cert-manager' from stack 'base'"
    The output should not include "Processing stack addon 'registry' from stack 'base'"
    The output should not include '[dry-run] Creating NFS export directory /srv/nfs/k8s-share'
  End

  It 'runs an explicit single-node dry-run bootstrap plan'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_runs="$(mktemp -d)"
      RUNS_DIR="${temp_runs}"
      bind_stdin_to_tty() { :; }
      sudo_keepalive() { :; }
      resolve_telemetry_enabled() { TELEMETRY_ENABLED=false; }
      emit_bootstrap_lifecycle_event() { :; }
      maybe_send_telemetry() { return 0; }
      pkg_installed() { return 1; }
      service_active() { return 1; }
      need_cmd() {
        case "$1" in
          helm|kubectl|docker) return 1 ;;
          *) command -v "$1" >/dev/null 2>&1 ;;
        esac
      }
      namespace_exists() { return 1; }
      deployment_exists() { return 1; }
      secret_exists() { return 1; }
      storageclass_exists() { [[ "$1" == "local-path" ]] && return 0; return 1; }
      clusterissuer_exists() { return 1; }
      helm_release_exists() { return 1; }
      nfs_export_exists() { return 1; }
      mount_exists() { return 1; }
      addon_source_script_exists() { return 0; }
      run_addon_source_hook() { printf "hook:%s|" "$1"; return 0; }
      confirm_preflight() { return 0; }
      prompt_yesno() {
        case "$1" in
          INSTALL_K3S|INSTALL_HELM|INSTALL_LONGHORN|INSTALL_RANCHER|INSTALL_REGISTRY|INSTALL_CERT_MANAGER|ENABLE_NFS|RANCHER_MANAGE_LOCAL_HOSTS|REGISTRY_MANAGE_LOCAL_HOSTS|REGISTRY_TRUST_DOCKER|PROCEED_WITH_PLAN|create_issuer|make_default_sc|install_pkgs|REGISTRY_AUTH_ENABLED)
            printf -v "$1" y ;;
          REUSE_EXISTING_NFS)
            printf -v "$1" n ;;
          *)
            printf -v "$1" "$2" ;;
        esac
      }
      prompt() { printf -v "$1" "%s" "$2"; }
      main --dry-run --mode single-node'
    The status should equal 0
    The output should include 'Mode: single-node'
    The output should include "Processing stack addon 'cert-manager' from stack 'base'"
    The output should include "Processing stack addon 'registry' from stack 'base'"
    The output should include '[dry-run] Creating NFS export directory /srv/nfs/k8s-share'
  End

  It 'runs an agent dry-run bootstrap with k3sup'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_runs="$(mktemp -d)"
      RUNS_DIR="${temp_runs}"
      PRODUCTIVE_K3S_ENGINE=k3sup
      PRODUCTIVE_K3S_SSH_HOST=10.0.0.20
      PRODUCTIVE_K3S_SSH_USER=ubuntu
      PRODUCTIVE_K3S_SSH_PORT=2222
      bind_stdin_to_tty() { :; }
      sudo_keepalive() { :; }
      resolve_telemetry_enabled() { TELEMETRY_ENABLED=false; }
      emit_bootstrap_lifecycle_event() { :; }
      maybe_send_telemetry() { return 0; }
      k3s_agent_active() { return 1; }
      k3s_server_active() { return 1; }
      need_cmd() { [[ "$1" == "k3sup" ]] && return 0; command -v "$1" >/dev/null 2>&1; }
      service_active() { [[ "$1" == "k3s-agent" ]] && return 1; [[ "$1" == "k3s" ]] && return 1; return 1; }
      prompt_yesno() {
        case "$1" in
          INSTALL_K3S_AGENT|PROCEED_WITH_PLAN) printf -v "$1" y ;;
          *) printf -v "$1" "$2" ;;
        esac
      }
      prompt() {
        case "$1" in
          AGENT_SERVER_URL) printf -v "$1" "https://server.example.local:6443" ;;
          AGENT_CLUSTER_TOKEN) printf -v "$1" "token-1" ;;
          *) printf -v "$1" "%s" "$2" ;;
        esac
      }
      main --dry-run --mode agent'
    The status should equal 0
    The output should include 'Mode: agent'
    The output should include 'k3s installation engine: k3sup'
    The output should include 'Joining k3s agent with k3sup'
    The output should include 'k3sup join'
    The output should include 'Agent server URL: https://server.example.local:6443'
  End
End
