# shellcheck shell=bash disable=SC2016
Describe 'bootstrap component preflights and install helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/bootstrap-k3s-stack.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'records a partial Longhorn preflight when k3s is inactive'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      service_active() { return 1; }
      confirm_preflight() { printf "confirm:%s:%s" "$1" "$2"; }
      preflight_longhorn_install "/var/lib/longhorn"
      printf "|warnings=%s" "${#DRY_RUN_WARNINGS[@]}"'
    The status should equal 0
    The output should include 'confirm:Longhorn:1'
    The output should include 'warnings=1'
  End

  It 'surfaces multiple Longhorn preflight warnings before confirmation'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      data_path="$(mktemp -d)"
      service_active() { return 0; }
      namespace_exists() { return 0; }
      namespace_has_user_resources() { return 0; }
      storageclass_exists() { return 0; }
      mount_exists() { return 1; }
      count_default_storageclasses() { printf "2"; }
      confirm_preflight() { printf "confirm:%s:%s" "$1" "$2"; }
      preflight_longhorn_install "${data_path}"
      printf "|warning0=%s|warning_count=%s" "${DRY_RUN_WARNINGS[0]}" "${#DRY_RUN_WARNINGS[@]}"'
    The status should equal 0
    The output should include 'confirm:Longhorn:4'
    The output should include "warning0=Longhorn: longhorn-system namespace already has resources"
    The output should include 'warning_count=4'
  End

  It 'detects registry host conflicts and missing storage class'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      service_active() { return 0; }
      namespace_exists() { return 0; }
      namespace_has_user_resources() { return 0; }
      find_ingress_host_conflicts() { printf "default/other-registry"; }
      storageclass_exists() { return 1; }
      confirm_preflight() { printf "confirm:%s:%s" "$1" "$2"; }
      preflight_registry_install "registry.home.arpa" "fast-storage"
      printf "|warning_count=%s|last=%s" "${#DRY_RUN_WARNINGS[@]}" "${DRY_RUN_WARNINGS[2]}"'
    The status should equal 0
    The output should include 'confirm:Registry:3'
    The output should include 'warning_count=3'
    The output should include "last=Registry: storageclass 'fast-storage' does not exist"
  End

  It 'detects malformed NFS inputs before confirmation'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      nfs_export_exists() { return 0; }
      confirm_preflight() { printf "confirm:%s:%s" "$1" "$2"; }
      preflight_nfs_install "/srv/nfs/k8s-share" "bad network"
      printf "|warning_count=%s|warning1=%s" "${#DRY_RUN_WARNINGS[@]}" "${DRY_RUN_WARNINGS[1]}"'
    The status should equal 0
    The output should include 'confirm:NFS:2'
    The output should include 'warning_count=2'
    The output should include "warning1=NFS: allowed network 'bad network' looks malformed"
  End

  It 'tracks k3s reuse without installing again'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      install_k3s_if_needed reuse
      printf "%s|%s" "${DRY_RUN_REUSE[0]}" "${MANIFEST_RESULT[k3s]}"'
    The status should equal 0
    The output should equal 'k3s|dry-run'
  End

  It 'runs the native k3s install helper path when requested'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      PRODUCTIVE_K3S_ENGINE=native
      ensure_packages() { :; }
      install_k3s_with_native() { printf "native-install"; }
      install_k3s_if_needed install
      printf "|track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[k3s]}"'
    The status should equal 0
    The output should include 'native-install'
    The output should include 'track=k3s'
    The output should include 'result=dry-run'
  End

  It 'prepares user kubeconfig in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      ensure_user_kubeconfig'
    The status should equal 0
    The output should include 'Preparing user kubeconfig'
    The output should include 'sudo cp /etc/rancher/k3s/k3s.yaml'
    The output should include 'chmod 600'
  End
End
