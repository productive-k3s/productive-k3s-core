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

  It 'delegates cert-manager installation to the addon hook'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_cert_manager_install() { :; }
      addon_source_script_exists() { return 0; }
      run_addon_source_hook() {
        printf "hook:%s|script:%s|fn:%s|issuer=%s|tls=%s|email=%s|env=%s" \
          "$1" "$2" "$3" "$PK3S_CLUSTER_ISSUER" "$PK3S_TLS_SOURCE" "$PK3S_LETSENCRYPT_EMAIL" "$PK3S_LETSENCRYPT_ENVIRONMENT"
      }
      ensure_cert_manager n install install 1 letsencrypt-prod ops@example.test production
      printf "|track=%s|cert=%s|issuer=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[cert_manager]}" "${MANIFEST_RESULT[clusterissuer]}"'
    The status should equal 0
    The output should include 'hook:cert-manager|script:install.sh|fn:pk3s_addon_install'
    The output should include 'issuer=letsencrypt-prod|tls=letsencrypt|email=ops@example.test|env=production'
    The output should include 'track=cert-manager|cert=dry-run|issuer=dry-run'
  End

  It 'delegates Longhorn installation and host prep to the addon hook'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_longhorn_install() { :; }
      addon_source_script_exists() { return 0; }
      LONGHORN_MAKE_DEFAULT=y
      run_addon_source_hook() {
        printf "hook:%s|path=%s|replicas=%s|min=%s|single=%s|default=%s" \
          "$1" "$PK3S_LONGHORN_DATA_PATH" "$PK3S_LONGHORN_REPLICA_COUNT" "$PK3S_LONGHORN_MINIMAL_AVAILABLE_PERCENTAGE" "$PK3S_LONGHORN_SINGLE_NODE_MODE" "$PK3S_LONGHORN_MAKE_DEFAULT"
      }
      install_longhorn_if_needed n install /var/lib/longhorn 1 10 y
      printf "|track=%s|longhorn=%s|prep=%s|note=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[longhorn]}" "${MANIFEST_RESULT[longhorn_host_prep]}" "${MANIFEST_NOTES[longhorn_host_prep]}"'
    The status should equal 0
    The output should include 'hook:longhorn|path=/var/lib/longhorn|replicas=1|min=10|single=y|default=y'
    The output should include 'track=Longhorn|longhorn=dry-run|prep=dry-run|note=/var/lib/longhorn'
  End

  It 'delegates Rancher installation and host-local intent to the addon hook'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_rancher_install() { :; }
      addon_source_script_exists() { return 0; }
      NODE_IP=10.0.0.10
      RANCHER_MANAGE_LOCAL_HOSTS=y
      run_addon_source_hook() {
        printf "hook:%s|host=%s|pass=%s|tls=%s|issuer=%s|manage=%s|ip=%s" \
          "$1" "$PK3S_RANCHER_HOST" "$PK3S_RANCHER_BOOTSTRAP_PASSWORD" "$PK3S_TLS_SOURCE" "$PK3S_CLUSTER_ISSUER" "$PK3S_RANCHER_MANAGE_LOCAL_HOSTS" "$PK3S_NODE_PRIMARY_IP"
      }
      install_rancher_if_needed n install 1 letsencrypt-prod rancher.home.arpa admin123 ops@example.test staging
      printf "|track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[rancher]}"'
    The status should equal 0
    The output should include 'hook:rancher|host=rancher.home.arpa|pass=admin123|tls=letsencrypt|issuer=letsencrypt-prod|manage=y|ip=10.0.0.10'
    The output should include 'track=Rancher|result=dry-run'
  End

  It 'delegates Registry installation and host-local options to the addon hook'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_registry_install() { :; }
      addon_source_script_exists() { return 0; }
      NODE_IP=10.0.0.10
      REGISTRY_MANAGE_LOCAL_HOSTS=y
      REGISTRY_TRUST_DOCKER=y
      run_addon_source_hook() {
        printf "hook:%s|host=%s|size=%s|sc=%s|tls=%s|issuer=%s|auth=%s|user=%s|pass=%s|manage=%s|trust=%s|ip=%s" \
          "$1" "$PK3S_REGISTRY_HOST" "$PK3S_REGISTRY_PVC_SIZE" "$PK3S_REGISTRY_STORAGE_CLASS" "$PK3S_TLS_SOURCE" "$PK3S_CLUSTER_ISSUER" "$PK3S_REGISTRY_AUTH_ENABLED" "$PK3S_REGISTRY_AUTH_USER" "$PK3S_REGISTRY_AUTH_PASSWORD" "$PK3S_REGISTRY_MANAGE_LOCAL_HOSTS" "$PK3S_REGISTRY_TRUST_DOCKER" "$PK3S_NODE_PRIMARY_IP"
      }
      install_registry_if_needed n install 2 local-selfsigned registry.home.arpa 20Gi longhorn-single y reguser regpass
      printf "|track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[registry]}"'
    The status should equal 0
    The output should include 'hook:registry|host=registry.home.arpa|size=20Gi|sc=longhorn-single|tls=secret|issuer=local-selfsigned|auth=y|user=reguser|pass=regpass|manage=y|trust=y|ip=10.0.0.10'
    The output should include 'track=Registry|result=dry-run'
  End

  It 'refuses to skip cert-manager when a TLS issuer install is required'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      ensure_cert_manager n skip install 1 letsencrypt-prod ops@example.test production'
    The status should equal 1
    The output should include 'Skipping cert-manager would leave TLS-dependent installs unsupported.'
  End
End
