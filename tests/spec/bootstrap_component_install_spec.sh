# shellcheck shell=bash disable=SC2016
Describe 'bootstrap component installers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'reuses an existing cert-manager installation'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      ensure_cert_manager y reuse
      printf "%s|%s" "${DRY_RUN_REUSE[0]}" "${MANIFEST_RESULT[cert_manager]}"'
    The status should equal 0
    The output should equal 'cert-manager|dry-run'
  End

  It 'installs cert-manager through the expected steps'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_cert_manager_install() { :; }
      ensure_namespace() { printf "ns:%s|" "$1"; }
      run_cmd() { local label="$1"; shift; printf "cmd:%s|%s|" "$label" "$*"; }
      wait_pods_ready() { printf "pods:%s:%s|" "$1" "$2"; }
      wait_service_endpoints() { printf "svc:%s:%s:%s|" "$1" "$2" "$3"; }
      ensure_cert_manager n install
      printf "track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[cert_manager]}"'
    The status should equal 0
    The output should include 'ns:cert-manager|'
    The output should include 'cmd:Applying cert-manager manifest|'
    The output should include 'v1.19.4/cert-manager.yaml'
    The output should include 'pods:cert-manager:420|'
    The output should include 'svc:cert-manager:cert-manager-webhook:180|'
    The output should include 'track=cert-manager'
    The output should include 'result=dry-run'
  End

  It 'reuses an existing issuer'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      clusterissuer_exists() { return 0; }
      ensure_issuer 1 letsencrypt-staging ops@example.test staging
      printf "%s|%s|%s" "${DRY_RUN_REUSE[0]}" "${MANIFEST_RESULT[clusterissuer]}" "${MANIFEST_NOTES[clusterissuer]}"'
    The status should equal 0
    The output should include "ClusterIssuer 'letsencrypt-staging' already exists"
    The output should include 'clusterissuer/letsencrypt-staging|dry-run|letsencrypt-staging'
  End

  It 'builds an ACME issuer manifest for letsencrypt mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      clusterissuer_exists() { return 1; }
      prompt_yesno() { printf -v "$1" "%s" "y"; }
      apply_manifest_with_retries() { printf "%s\n%s" "$1" "$2"; }
      ensure_issuer 1 letsencrypt-prod ops@example.test production
      printf "\ntrack=%s|result=%s|note=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[clusterissuer]}" "${MANIFEST_NOTES[clusterissuer]}"'
    The status should equal 0
    The output should include 'Creating ClusterIssuer letsencrypt-prod'
    The output should include 'server: https://acme-v02.api.letsencrypt.org/directory'
    The output should include 'email: ops@example.test'
    The output should include 'track=clusterissuer/letsencrypt-prod'
    The output should include 'result=dry-run'
    The output should include 'note=letsencrypt-prod'
  End

  It 'builds a self-signed issuer manifest when tls_choice is not letsencrypt'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      clusterissuer_exists() { return 1; }
      prompt_yesno() { printf -v "$1" "%s" "y"; }
      apply_manifest_with_retries() { printf "%s" "$2"; }
      ensure_issuer 2 local-selfsigned "" staging'
    The status should equal 0
    The output should include 'selfSigned: {}'
  End

  It 'installs Longhorn in single-node mode and patches storage defaults'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_longhorn_install() { :; }
      ensure_packages() { :; }
      ensure_iscsid() { :; }
      ensure_helm_repo() { printf "repo:%s|" "$1"; }
      run_cmd() { local label="$1"; shift; printf "cmd:%s|%s|" "$label" "$*"; }
      run_cmd_with_retries() { local label="$1"; shift 3; printf "retry:%s|%s|" "$label" "$*"; }
      ensure_namespace() { printf "ns:%s|" "$1"; }
      wait_pods_ready() { printf "pods:%s:%s|" "$1" "$2"; }
      apply_manifest() { printf "manifest:%s\n%s\n" "$1" "$2"; }
      prompt_yesno() { printf -v "$1" "%s" "y"; }
      storageclass_exists() {
        [[ "$1" == "longhorn-single" || "$1" == "longhorn" || "$1" == "local-path" ]]
      }
      install_longhorn_if_needed n install /var/lib/longhorn 1 10 y
      printf "track0=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[longhorn]}"'
    The status should equal 0
    The output should include 'repo:longhorn|'
    The output should include 'retry:Updating Helm repos for Longhorn|'
    The output should include 'retry:Installing Longhorn|'
    The output should include '--version v1.11.1'
    The output should include 'manifest:Creating Longhorn single-node StorageClass'
    The output should include 'numberOfReplicas: "1"'
    The output should include 'cmd:Setting Longhorn minimal available percentage to 10|'
    The output should include 'cmd:Marking longhorn-single as default StorageClass|'
    The output should include 'track0=Longhorn'
    The output should include 'result=dry-run'
  End

  It 'installs Rancher with letsencrypt settings'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_rancher_install() { :; }
      ensure_helm_repo() { printf "repo:%s|" "$1"; }
      run_cmd_with_retries() { local label="$1"; shift 3; printf "retry:%s|%s|" "$label" "$*"; }
      ensure_namespace() { printf "ns:%s|" "$1"; }
      install_rancher_if_needed n install 1 letsencrypt-prod rancher.home.arpa admin123 ops@example.test staging
      printf "track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[rancher]}"'
    The status should equal 0
    The output should include 'repo:rancher-latest|'
    The output should include 'retry:Updating Helm repos for Rancher|'
    The output should include 'retry:Installing Rancher|'
    The output should include '--version v2.14.2'
    The output should include 'ns:cattle-system|'
    The output should include 'track=Rancher'
    The output should include 'result=dry-run'
  End

  It 'creates Rancher secret-backed TLS assets when using private certificates'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_rancher_install() { :; }
      ensure_helm_repo() { :; }
      run_cmd_with_retries() { local label="$1"; shift 3; printf "retry:%s|%s|" "$label" "$*"; }
      ensure_namespace() { :; }
      secret_exists() { return 1; }
      apply_manifest() { printf "%s\n%s\n" "$1" "$2"; }
      wait_for_secret() { printf "wait-secret:%s:%s:%s|" "$1" "$2" "$3"; }
      wait_for_certificate_ready() { printf "wait-cert:%s:%s:%s|" "$1" "$2" "$3"; }
      ensure_rancher_private_ca_secret() { printf "ca-secret|"; }
      install_rancher_if_needed n install 2 local-selfsigned rancher.home.arpa admin123 "" staging'
    The status should equal 0
    The output should include 'Creating Rancher TLS certificate'
    The output should include 'secretName: rancher-tls'
    The output should include 'wait-secret:cattle-system:rancher-tls:120|'
    The output should include 'wait-cert:cattle-system:rancher-tls:180|'
    The output should include 'ca-secret|'
    The output should include 'retry:Installing Rancher|'
    The output should include '--version v2.14.2'
  End

  It 'installs the registry with auth and certificate wiring'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      preflight_registry_install() { :; }
      ensure_namespace() { printf "ns:%s|" "$1"; }
      secret_exists() { return 1; }
      need_cmd() { [[ "$1" == "openssl" ]]; }
      openssl() { printf "hashed-pass"; }
      apply_manifest() { printf "%s\n%s\n" "$1" "$2"; }
      wait_for_secret() { printf "wait-secret:%s:%s:%s|" "$1" "$2" "$3"; }
      wait_for_certificate_ready() { printf "wait-cert:%s:%s:%s|" "$1" "$2" "$3"; }
      wait_pods_ready() { printf "pods:%s:%s|" "$1" "$2"; }
      install_registry_if_needed n install 2 local-selfsigned registry.home.arpa 20Gi longhorn-single y reguser regpass
      printf "track=%s|result=%s" "${DRY_RUN_INSTALL[0]}" "${MANIFEST_RESULT[registry]}"'
    The status should equal 0
    The output should include 'Creating registry TLS certificate'
    The output should include 'secretName: registry-tls'
    The output should include '[dry-run] Creating/updating registry basic-auth secret'
    The output should include 'username: reguser'
    The output should include 'Installing the in-cluster registry'
    The output should include 'image: registry:2.8.3'
    The output should include 'secretName: registry-auth'
    The output should include 'storageClassName: longhorn-single'
    The output should include 'registry.home.arpa'
    The output should include 'wait-secret:registry:registry-tls:120|'
    The output should include 'wait-cert:registry:registry-tls:180|'
    The output should include 'pods:registry:300|'
    The output should include 'track=Registry'
    The output should include 'result=dry-run'
  End
End
