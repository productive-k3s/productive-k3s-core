# shellcheck shell=bash disable=SC2016
Describe 'bootstrap component installers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'reuses an existing cert-manager installation and issuer'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      ensure_cert_manager y reuse reuse 1 letsencrypt-staging ops@example.test staging
      printf "%s|%s|%s|%s" "${DRY_RUN_REUSE[0]}" "${MANIFEST_RESULT[cert_manager]}" "${MANIFEST_RESULT[clusterissuer]}" "${MANIFEST_NOTES[clusterissuer]}"'
    The status should equal 0
    The output should equal 'cert-manager|dry-run|dry-run|letsencrypt-staging'
  End

  It 'describes cert-manager installation without executing the addon hook in dry-run'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_cert_manager_install() { :; }
      addon_source_script_exists() { return 0; }
      ensure_cert_manager n install install 1 letsencrypt-prod ops@example.test production
      printf "|track=%s|cert=%s|issuer=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[cert_manager]}" "${MANIFEST_RESULT[clusterissuer]}"'
    The status should equal 0
    The output should include '[dry-run] Would install cert-manager from addon source...'
    The output should include 'track=cert-manager|cert=dry-run|issuer=dry-run'
  End

  It 'describes Longhorn installation and host prep without executing the addon hook in dry-run'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_longhorn_install() { :; }
      addon_source_script_exists() { return 0; }
      LONGHORN_MAKE_DEFAULT=y
      install_longhorn_if_needed n install /var/lib/longhorn 1 10 y
      printf "|track=%s|longhorn=%s|prep=%s|note=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[longhorn]}" "${MANIFEST_RESULT[longhorn_host_prep]}" "${MANIFEST_NOTES[longhorn_host_prep]}"'
    The status should equal 0
    The output should include '[dry-run] Would install Longhorn from addon source...'
    The output should include 'track=Longhorn|longhorn=dry-run|prep=dry-run|note=/var/lib/longhorn'
  End

  It 'describes Rancher installation without executing the addon hook in dry-run'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_rancher_install() { :; }
      addon_source_script_exists() { return 0; }
      NODE_IP=10.0.0.10
      RANCHER_MANAGE_LOCAL_HOSTS=y
      install_rancher_if_needed n install 1 letsencrypt-prod rancher.home.arpa admin123 ops@example.test staging
      printf "|track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[rancher]}"'
    The status should equal 0
    The output should include '[dry-run] Would install Rancher from addon source...'
    The output should include 'track=Rancher|result=dry-run'
  End

  It 'describes Registry installation without executing the addon hook in dry-run'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_registry_install() { :; }
      addon_source_script_exists() { return 0; }
      NODE_IP=10.0.0.10
      REGISTRY_MANAGE_LOCAL_HOSTS=y
      REGISTRY_TRUST_DOCKER=y
      install_registry_if_needed n install 2 local-selfsigned registry.home.arpa 20Gi longhorn-single y reguser regpass
      printf "|track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[registry]}"'
    The status should equal 0
    The output should include '[dry-run] Would install Registry from addon source...'
    The output should include 'track=Registry|result=dry-run'
  End

  It 'refuses to skip cert-manager when a TLS issuer install is required'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      ensure_cert_manager n skip install 1 letsencrypt-prod ops@example.test production'
    The status should equal 1
    The output should include 'Skipping cert-manager would leave TLS-dependent installs unsupported.'
  End
End
