# shellcheck shell=bash disable=SC2016
Describe 'bootstrap waits and retry helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'retries manifest application until it succeeds'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      attempts=0
      apply_manifest() {
        attempts=$((attempts + 1))
        [[ "${attempts}" -ge 3 ]]
      }
      state_file="$(mktemp)"
      printf "0" >"${state_file}"
      date() {
        now="$(cat "${state_file}")"
        printf "%s\n" "${now}"
        printf "%s" "$((now + 1))" >"${state_file}"
      }
      sleep() { :; }
      apply_manifest_with_retries "Applying test manifest" "kind: ConfigMap" 10 1'
    The status should equal 0
    The output should include 'Applying test manifest did not succeed yet.'
  End

  It 'times out manifest application retries'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      apply_manifest() { return 1; }
      state_file="$(mktemp)"
      printf "0" >"${state_file}"
      date() {
        now="$(cat "${state_file}")"
        printf "%s\n" "${now}"
        printf "%s" "$((now + 5))" >"${state_file}"
      }
      sleep() { :; }
      apply_manifest_with_retries "Applying test manifest" "kind: ConfigMap" 4 1'
    The status should equal 1
  End

  It 'waits for pods to become ready'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      state_file="$(mktemp)"
      printf "0" >"${state_file}"
      kubectl_k3s() {
        if [[ "$1 $2 $3 $4" == "get pods -n cert-manager" ]]; then
          phase="$(cat "${state_file}")"
          phase=$((phase + 1))
          printf "%s" "${phase}" >"${state_file}"
          if [[ "${5:-}" == "--no-headers" ]]; then
            if [[ "${phase}" -lt 3 ]]; then
              printf "cm-1 0/1 Pending 0 1s\n"
            else
              printf "cm-1 1/1 Running 0 5s\n"
            fi
          fi
          return 0
        fi
      }
      time_file="$(mktemp)"
      printf "0" >"${time_file}"
      date() {
        now="$(cat "${time_file}")"
        printf "%s\n" "${now}"
        printf "%s" "$((now + 1))" >"${time_file}"
      }
      sleep() { :; }
      wait_pods_ready cert-manager 20'
    The status should equal 0
    The output should include "Namespace 'cert-manager' looks Ready."
  End

  It 'times out while waiting for pods'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      kubectl_k3s() {
        if [[ "$1" == "get" && "$2" == "pods" ]]; then
          if [[ "${5:-}" == "--no-headers" ]]; then
            printf "cm-1 0/1 Pending 0 1s\n"
          else
            printf "cm-1 0/1 Pending 0 1s\n"
          fi
        fi
      }
      time_file="$(mktemp)"
      printf "0" >"${time_file}"
      date() {
        now="$(cat "${time_file}")"
        printf "%s\n" "${now}"
        printf "%s" "$((now + 6))" >"${time_file}"
      }
      sleep() { :; }
      wait_pods_ready cert-manager 5'
    The status should equal 0
    The output should include "Timeout waiting for namespace 'cert-manager'."
  End

  It 'waits for service endpoints to appear'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      state_file="$(mktemp)"
      printf "0" >"${state_file}"
      kubectl_k3s() {
        calls="$(cat "${state_file}")"
        calls=$((calls + 1))
        printf "%s" "${calls}" >"${state_file}"
        if [[ "${calls}" -lt 2 ]]; then
          return 0
        fi
        printf "10.43.0.15"
      }
      time_file="$(mktemp)"
      printf "0" >"${time_file}"
      date() {
        now="$(cat "${time_file}")"
        printf "%s\n" "${now}"
        printf "%s" "$((now + 1))" >"${time_file}"
      }
      sleep() { :; }
      wait_service_endpoints cert-manager cert-manager-webhook 10'
    The status should equal 0
    The output should include "has endpoints."
  End

  It 'times out while waiting for service endpoints'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      kubectl_k3s() { return 0; }
      time_file="$(mktemp)"
      printf "0" >"${time_file}"
      date() {
        now="$(cat "${time_file}")"
        printf "%s\n" "${now}"
        printf "%s" "$((now + 6))" >"${time_file}"
      }
      sleep() { :; }
      wait_service_endpoints cert-manager cert-manager-webhook 5'
    The status should equal 0
    The output should include "Timeout waiting for service 'cert-manager-webhook'"
  End
End
