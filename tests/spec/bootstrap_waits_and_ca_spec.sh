# shellcheck shell=bash disable=SC2016
Describe 'bootstrap waits and rancher ca helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/bootstrap-k3s-stack.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'returns immediately for wait_for_secret in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      wait_for_secret cattle-system rancher-tls 30'
    The status should equal 0
    The output should include 'Skipping wait for secret cattle-system/rancher-tls'
  End

  It 'waits for a secret until it appears'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      counter=0
      secret_exists() {
        counter=$((counter + 1))
        [[ "${counter}" -ge 3 ]]
      }
      sleep() { :; }
      date() { printf "%s\n" "${counter}"; }
      wait_for_secret cattle-system rancher-tls 10
      printf "tries=%s" "$counter"'
    The status should equal 0
    The output should include 'tries=3'
  End

  It 'times out while waiting for a secret'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tick_file="$(mktemp)"
      printf "0" >"${tick_file}"
      secret_exists() { return 1; }
      sleep() { :; }
      date() {
        tick="$(cat "${tick_file}")"
        tick=$((tick + 1))
        printf "%s" "${tick}" >"${tick_file}"
        case "$tick" in
          1) printf "0\n" ;;
          2) printf "2\n" ;;
          *) printf "4\n" ;;
        esac
      }
      wait_for_secret cattle-system rancher-tls 1'
    The status should equal 1
  End

  It 'returns immediately for wait_for_certificate_ready in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      wait_for_certificate_ready cattle-system rancher-tls 30'
    The status should equal 0
    The output should include 'Skipping wait for certificate cattle-system/rancher-tls'
  End

  It 'waits for a certificate until it becomes Ready'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      counter_file="$(mktemp)"
      printf "0" >"${counter_file}"
      kubectl_k3s() {
        counter="$(cat "${counter_file}")"
        counter=$((counter + 1))
        printf "%s" "${counter}" >"${counter_file}"
        if [[ "${counter}" -ge 3 ]]; then
          printf "True"
        else
          printf "False"
        fi
      }
      sleep() { :; }
      date() { printf "%s\n" "$(cat "${counter_file}")"; }
      wait_for_certificate_ready cattle-system rancher-tls 10
      printf "tries=%s" "$(cat "${counter_file}")"'
    The status should equal 0
    The output should include 'tries=3'
  End

  It 'succeeds when the k3s api reports a ready node'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      service_active() { return 0; }
      kubectl_k3s() {
        if [[ "$1" == "get" && "$2" == "nodes" && "${3:-}" == "--no-headers" ]]; then
          printf "node1 Ready control-plane 1d v1\n"
        else
          :
        fi
      }
      wait_k3s_ready 10'
    The status should equal 0
    The output should include 'k3s API is reachable and at least one node is Ready'
  End

  It 'times out while waiting for the k3s api'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tick_file="$(mktemp)"
      printf "0" >"${tick_file}"
      service_active() { return 1; }
      kubectl_k3s() { return 1; }
      sleep() { :; }
      sudo() { printf "sudo:%s|" "$*"; return 0; }
      date() {
        tick="$(cat "${tick_file}")"
        tick=$((tick + 1))
        printf "%s" "${tick}" >"${tick_file}"
        case "$tick" in
          1) printf "0\n" ;;
          2) printf "2\n" ;;
          *) printf "4\n" ;;
        esac
      }
      wait_k3s_ready 1'
    The status should equal 1
    The output should include 'Timed out waiting for k3s API readiness'
    The output should include 'sudo:systemctl status k3s --no-pager|'
  End

  It 'prints rancher ca secret creation steps in dry-run mode'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      DRY_RUN=1
      ensure_rancher_private_ca_secret'
    The status should equal 0
    The output should include 'Creating Rancher CA secret cattle-system/tls-ca'
    The output should include 'kubectl create secret generic tls-ca'
  End

  It 'creates the rancher ca secret from the source secret'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      log_file="$(mktemp)"
      kubectl_k3s() {
        case "$1 $2 $3 ${4:-}" in
          "get secret rancher-tls -n")
            printf "Q0EgREFUQQ=="
            ;;
          "delete secret tls-ca -n")
            printf "delete:%s\n" "$*" >>"${log_file}"
            ;;
          "create secret generic tls-ca")
            printf "create:%s\n" "$*" >>"${log_file}"
            ;;
        esac
      }
      ensure_rancher_private_ca_secret
      cat "${log_file}"'
    The status should equal 0
    The output should include 'delete:delete secret tls-ca -n cattle-system'
    The output should include 'create:create secret generic tls-ca -n cattle-system --from-literal=cacerts.pem=CA DATA'
  End
End
