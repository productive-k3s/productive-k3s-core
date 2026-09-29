# shellcheck shell=bash disable=SC2016
Describe 'addon host runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/addon-host-runtime.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'uses optional Core callbacks when they are available'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      log() { printf "log:%s\n" "$*"; }
      warn() { printf "warn:%s\n" "$*"; }
      manifest_complete_component() { printf "manifest:%s\n" "$*"; }
      track_install() { printf "install:%s\n" "$*"; }
      track_reuse() { printf "reuse:%s\n" "$*"; }
      result_for_mode() { printf "mode:%s\n" "$1"; }
      service_active() { [[ "$1" == active-service ]]; }
      pkg_installed() { [[ "$1" == installed-package ]]; }
      run_cmd() { printf "run:%s\n" "$*"; }
      ensure_packages() { printf "packages:%s\n" "$*"; }

      pk3s_runtime_log hello world
      pk3s_runtime_warn careful
      pk3s_manifest_complete_optional demo configured note
      pk3s_track_install_optional demo
      pk3s_track_reuse_optional demo
      pk3s_result_for_mode_optional configured
      pk3s_service_active_optional active-service
      pk3s_pkg_installed_optional installed-package
      pk3s_runtime_run_cmd label true
      pk3s_ensure_packages_optional runtime installed-package'
    The status should equal 0
    The output should include 'log:hello world'
    The output should include 'warn:careful'
    The output should include 'manifest:demo configured note'
    The output should include 'install:demo'
    The output should include 'reuse:demo'
    The output should include 'mode:configured'
    The output should include 'run:label true'
    The output should include 'packages:runtime installed-package'
  End

  It 'provides standalone logging and command fallbacks'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      systemctl() { [[ "$*" == "is-active --quiet active-service" ]]; }
      dpkg() { [[ "$*" == "-s installed-package" ]]; }
      pk3s_runtime_cmd_exists bash
      pk3s_runtime_log hello
      pk3s_runtime_warn careful
      printf "result=%s\n" "$(pk3s_result_for_mode_optional configured)"
      pk3s_service_active_optional active-service
      pk3s_pkg_installed_optional installed-package
      pk3s_runtime_run_cmd "Running command" printf "command-ok\n"'
    The status should equal 0
    The output should include '[INFO] hello'
    The stderr should include '[WARN] careful'
    The output should include 'result=configured'
    The output should include '[INFO] Running command'
    The output should include 'command-ok'
  End

  It 'installs only missing packages through the standalone fallback'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pk3s_pkg_installed_optional() { [[ "$1" == present ]]; }
      sudo() { printf "sudo:%s\n" "$*"; }
      pk3s_ensure_packages_optional runtime present missing'
    The status should equal 0
    The stderr should include 'Installing missing packages for runtime: missing'
    The output should include 'sudo:apt-get update -y'
    The output should include 'sudo:apt-get install -y missing'
  End

  It 'skips package and service changes when state is already converged'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pk3s_pkg_installed_optional() { return 0; }
      pk3s_service_active_optional() { return 0; }
      pk3s_ensure_packages_optional runtime one two
      pk3s_enable_service_optional iscsid'
    The status should equal 0
    The output should include 'Required packages for runtime are already installed.'
    The output should include "Service 'iscsid' already active."
  End

  It 'delegates host directory, service, and hosts-file mutations'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      pk3s_service_active_optional() { return 1; }
      pk3s_runtime_run_cmd() { printf "run:%s\n" "$*"; }
      pk3s_enable_service_optional iscsid
      pk3s_ensure_directory_optional /path/that/does/not/exist

      grep() { return 1; }
      pk3s_track_install_optional() { printf "install:%s\n" "$*"; }
      pk3s_manifest_complete_optional() { printf "manifest:%s\n" "$*"; }
      pk3s_result_for_mode_optional() { printf "%s\n" "$1"; }
      pk3s_replace_local_hosts_entry demo.local 10.0.0.2 demo-hosts
      sudo() { printf "sudo:%s\n" "$*"; }
      pk3s_remove_local_hosts_entry demo.local'
    The status should equal 0
    The output should include 'run:Enabling and starting iscsid sudo systemctl enable --now iscsid'
    The output should include 'run:Ensuring directory /path/that/does/not/exist exists sudo mkdir -p /path/that/does/not/exist'
    The output should include 'install:/etc/hosts demo.local'
    The output should include 'manifest:demo-hosts configured 10.0.0.2 demo.local'
    The output should include 'sudo:sed -i'
  End

  It 'reuses an existing hosts entry'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      grep() { return 0; }
      pk3s_track_reuse_optional() { printf "reuse:%s\n" "$*"; }
      pk3s_manifest_complete_optional() { printf "manifest:%s\n" "$*"; }
      pk3s_result_for_mode_optional() { printf "%s\n" "$1"; }
      pk3s_replace_local_hosts_entry localhost 127.0.0.1 demo-hosts'
    The status should equal 0
    The output should include 'reuse:/etc/hosts localhost'
    The output should include 'manifest:demo-hosts reused 127.0.0.1 localhost'
  End

  It 'exports certificates and removes Docker trust through selected commands'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      sudo() {
        case "$1" in
          k3s) printf "Y2VydA==\n" ;;
          tee) cat >/dev/null ;;
          *) printf "sudo:%s\n" "$*" ;;
        esac
      }
      kubectl() { printf "Y2VydA==\n"; }
      systemctl() { return 0; }
      pk3s_track_install_optional() { printf "install:%s\n" "$*"; }
      pk3s_manifest_complete_optional() { printf "manifest:%s\n" "$*"; }
      pk3s_result_for_mode_optional() { printf "%s\n" "$1"; }

      PK3S_KUBECTL_MODE=k3s pk3s_export_tls_secret_cert ns tls /tmp/cert-one
      PK3S_KUBECTL_MODE=kubectl PK3S_KUBECTL_BIN=kubectl pk3s_export_tls_secret_cert ns tls /tmp/cert-two
      pk3s_install_local_docker_trust namespace secret registry.local docker-trust
      pk3s_remove_local_docker_trust registry.local'
    The status should equal 0
    The output should include 'install:Docker trust registry.local'
    The output should include 'manifest:docker-trust configured registry.local'
    The output should include 'sudo:rm -rf /etc/docker/certs.d/registry.local'
    The output should include 'sudo:systemctl restart docker'
  End
End
