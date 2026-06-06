# shellcheck shell=bash disable=SC2016
Describe 'bootstrap host helpers and cleanup'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'skips telemetry delivery when telemetry is disabled'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'TELEMETRY_ENABLED=false; maybe_send_telemetry 0; printf "done"'
    The status should equal 0
    The output should equal 'done'
  End

  It 'warns when telemetry manifest is missing'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      TELEMETRY_ENABLED=true
      TELEMETRY_ENDPOINT="https://telemetry.example.test/telemetry"
      SCRIPT_DIR="$(mktemp -d)"
      chmod 755 "$SCRIPT_DIR"
      maybe_send_telemetry 7'
    The status should equal 1
    The output should include 'public run manifest is unavailable'
  End

  It 'invokes the telemetry sender with propagated context'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      RUN_MANIFEST="${tmpdir}/manifest.json"
      cat >"${RUN_MANIFEST}" <<EOF
{"status":"success"}
EOF
      cat >"${tmpdir}/send-telemetry.sh" <<EOF
#!/usr/bin/env bash
printf "endpoint=%s|run=%s|parent=%s|exit=%s|manifest=%s" "\$TELEMETRY_ENDPOINT" "\$TELEMETRY_RUN_ID" "\$TELEMETRY_PARENT_RUN_ID" "\$TELEMETRY_EXIT_CODE" "\$1"
EOF
      chmod +x "${tmpdir}/send-telemetry.sh"
      SCRIPT_DIR="${tmpdir}"
      TELEMETRY_ENABLED=true
      TELEMETRY_ENDPOINT="https://telemetry.example.test/telemetry"
      TELEMETRY_SESSION_ID="session-123"
      TELEMETRY_PARENT_RUN_ID="parent-123"
      RUN_ID="run-123"
      maybe_send_telemetry 9'
    The status should equal 0
    The output should include 'endpoint=https://telemetry.example.test/telemetry'
    The output should include 'run=run-123'
    The output should include 'parent=parent-123'
    The output should include 'exit=9'
    The output should include 'manifest='
  End

  It 'tracks local hosts changes in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      ensure_local_hosts_entries "10.0.0.10" rancher.home.arpa registry.home.arpa
      printf "track=%s|result=%s|note=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[local_hosts]}" "${MANIFEST_NOTES[local_hosts]}"'
    The status should equal 0
    The output should include 'Adding/updating local /etc/hosts entries'
    The output should include '10.0.0.10 rancher.home.arpa registry.home.arpa'
    The output should include 'track=local /etc/hosts entries'
    The output should include 'result=dry-run'
  End

  It 'warns when docker trust cannot be configured without docker'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      need_cmd() { return 1; }
      ensure_local_docker_registry_trust registry.home.arpa'
    The status should equal 0
    The output should include 'docker is not installed on this machine'
  End

  It 'prints docker trust steps in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      need_cmd() { [[ "$1" == "docker" ]]; }
      secret_exists() { return 0; }
      ensure_local_docker_registry_trust registry.home.arpa
      printf "track=%s|result=%s|note=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[docker_registry_trust]}" "${MANIFEST_NOTES[docker_registry_trust]}"'
    The status should equal 0
    The output should include 'Installing Docker trust for registry.home.arpa'
    The output should include 'sudo mkdir -p /etc/docker/certs.d/registry.home.arpa'
    The output should include 'sudo systemctl restart docker'
    The output should include 'track=Docker registry trust for registry.home.arpa'
    The output should include 'result=dry-run'
  End

  It 'reuses an existing NFS server and export'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      install_nfs_if_needed y y reuse /srv/nfs/k8s-share 192.168.1.0/24
      printf "%s|%s|%s|%s" "${DRY_RUN_REUSE[0]}" "${DRY_RUN_REUSE[1]}" "${MANIFEST_RESULT[nfs]}" "${MANIFEST_NOTES[nfs]}"'
    The status should equal 0
    The output should equal 'NFS server|NFS export /srv/nfs/k8s-share|dry-run|/srv/nfs/k8s-share 192.168.1.0/24'
  End

  It 'installs and exports NFS in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_nfs_install() { :; }
      ensure_packages() { :; }
      nfs_service_name() { printf "nfs-kernel-server"; }
      nfs_export_exists() { return 1; }
      run_cmd() { printf "cmd:%s|" "$1"; }
      install_nfs_if_needed n n install /srv/nfs/k8s-share 192.168.1.0/24
      printf "track0=%s|track1=%s|result=%s|note=%s" "${DRY_RUN_INSTALL[0]}" "${DRY_RUN_INSTALL[1]}" "${MANIFEST_RESULT[nfs]}" "${MANIFEST_NOTES[nfs]}"'
    The status should equal 0
    The output should include 'cmd:Enabling and starting nfs-kernel-server|'
    The output should include 'cmd:Creating NFS export directory /srv/nfs/k8s-share|'
    The output should include '[dry-run] Adding NFS export to /etc/exports'
    The output should include '/srv/nfs/k8s-share 192.168.1.0/24(rw,sync,no_subtree_check)'
    The output should include 'cmd:Reloading NFS exports|'
    The output should include 'track0=NFS server'
    The output should include 'track1=NFS export /srv/nfs/k8s-share (192.168.1.0/24)'
    The output should include 'result=dry-run'
  End

  It 'rejects invalid NFS export paths'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" 'install_nfs_if_needed n n install relative/path 192.168.1.0/24'
    The status should equal 1
    The output should include "NFS export path 'relative/path' is invalid"
  End

  It 'marks cleanup as failed and warns when telemetry delivery fails'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      RUN_STATUS="running"
      SUDO_KA_PID=""
      write_run_manifest() { printf "manifest:%s|" "$1"; }
      write_private_run_context() { printf "private:%s|" "$1"; }
      emit_bootstrap_lifecycle_event() { printf "event:%s:%s|" "$1" "$2"; }
      maybe_send_telemetry() { return 1; }
      set +e
      false
      cleanup_exit
      printf "status=%s" "$RUN_STATUS"'
    The status should equal 0
    The output should include 'manifest:1|'
    The output should include 'private:1|'
    The output should include 'event:completed:failed|'
    The output should include 'Telemetry delivery did not complete successfully'
    The output should include 'status=failed'
  End
End
