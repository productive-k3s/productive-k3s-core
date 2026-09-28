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
      addon_source_script_exists() { return 0; }
      prompt_yesno() {
        case "$1" in
          INSTALL_RUNTIME|INSTALL_HELM|proceed|install_pkgs)
            printf -v "$1" y ;;
          *)
            printf -v "$1" "$2" ;;
        esac
      }
      prompt() { printf -v "$1" "%s" "$2"; }
      main --dry-run'
    The status should equal 0
    The output should include 'Planned actions'
    The output should include '[dry-run] Installing k3s (v1.35.5+k3s1)'
    The output should include '[dry-run] Installing Helm'
    The output should not include 'stack add-ons: install'
  End

  It 'runs an explicit single-node dry-run bootstrap plan'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_runs="$(mktemp -d)"
      temp_addons="$(mktemp -d)"
      RUNS_DIR="${temp_runs}"
      mkdir -p "${temp_addons}/stacks/base"
      mkdir -p "${temp_addons}/addons/custom-a/scripts"
      mkdir -p "${temp_addons}/addons/custom-b/scripts"
      cat >"${temp_addons}/stacks/base/stack.yaml" <<'"'"'EOF'"'"'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
  version: 0.1.0
spec:
  addons:
    - custom-a
    - custom-b
EOF
      export PRODUCTIVE_K3S_ADDONS_REPO_DIR="${temp_addons}"
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
      addon_source_script_exists() { return 0; }
      prompt_yesno() {
        case "$1" in
          INSTALL_RUNTIME|INSTALL_HELM|proceed|install_pkgs)
            printf -v "$1" y ;;
          *)
            printf -v "$1" "$2" ;;
        esac
      }
      prompt() { printf -v "$1" "%s" "$2"; }
      main --dry-run --mode single-node'
    The status should equal 0
    The output should include "stack add-ons: install from 'base'"
    The output should include "Installing stack add-on 'custom-a' from stack 'base'"
    The output should include "Installing stack add-on 'custom-b' from stack 'base'"
    The output should include "[dry-run] Would run source add-on installer for 'custom-a'"
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
          INSTALL_AGENT|proceed) printf -v "$1" y ;;
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
    The output should include 'Joining k3s agent with k3sup'
    The output should include 'k3sup join'
  End
End
