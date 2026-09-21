# shellcheck shell=bash disable=SC2016
Describe 'bundled stack addon runtime'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'treats bundled stack addons as dry-run actions without invoking packaged installers'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_bundle_dir="$(mktemp -d)"
      touch "${temp_bundle_dir}/cert-manager-0.1.0.tgz"
      DRY_RUN=1
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_bundle_dir}"
      addon_record="$(printf "name=cert-manager\tversion=0.1.0\tsource=addons/cert-manager-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"
      printf "|tracked=%s" "${DRY_RUN_INSTALL[0]}"'
    The status should equal 0
    The output should include "[dry-run] Would install bundled addon package 'addons/cert-manager-0.1.0.tgz' for stack 'base'"
    The output should include "|tracked=bundled-addon:cert-manager"
  End

  It 'passes declarative runtime inputs from bundled addon metadata'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_root="$(mktemp -d)"
      mkdir -p "${temp_root}/pkg/scripts" "${temp_root}/fake/scripts"
      cat >"${temp_root}/pkg/addon.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: custom-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
  productiveK3s:
    stack:
      runtime:
        inputs:
          - name: PK3S_CUSTOM_VALUE
            source: CUSTOM_SOURCE_VALUE
          - name: PK3S_TLS_SOURCE
            valueFrom: core.tlsSource
          - name: PK3S_DEFAULTED_VALUE
            source: EMPTY_SOURCE_VALUE
            default: fallback-value
EOF
      : >"${temp_root}/pkg/scripts/install.sh"
      tar -czf "${temp_root}/custom-addon-0.1.0.tgz" -C "${temp_root}/pkg" .
      cat >"${temp_root}/fake/productive-k3s-core.sh" <<EOF
#!/usr/bin/env bash
printf "args=%s %s %s %s|custom=%s|tls=%s|defaulted=%s" "\$1" "\$2" "\$3" "\$4" "\${PK3S_CUSTOM_VALUE:-}" "\${PK3S_TLS_SOURCE:-}" "\${PK3S_DEFAULTED_VALUE:-}"
EOF
      chmod +x "${temp_root}/fake/productive-k3s-core.sh"
      SCRIPT_DIR="${temp_root}/fake/scripts"
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_root}"
      CUSTOM_SOURCE_VALUE=from-core-session
      EMPTY_SOURCE_VALUE=""
      TLS_CHOICE=2
      addon_record="$(printf "name=custom-addon\tversion=0.1.0\tsource=addons/custom-addon-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"'
    The status should equal 0
    The output should include "args=addon install --tgz"
    The output should include "custom=from-core-session"
    The output should include "tls=secret"
    The output should include "defaulted=fallback-value"
  End

  It 'keeps the legacy bundled addon fallback for packages without runtime metadata'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_root="$(mktemp -d)"
      mkdir -p "${temp_root}/pkg/scripts" "${temp_root}/fake/scripts"
      cat >"${temp_root}/pkg/addon.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: custom-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
      : >"${temp_root}/pkg/scripts/install.sh"
      tar -czf "${temp_root}/custom-addon-0.1.0.tgz" -C "${temp_root}/pkg" .
      cat >"${temp_root}/fake/productive-k3s-core.sh" <<EOF
#!/usr/bin/env bash
printf "args=%s %s %s %s|custom=%s" "\$1" "\$2" "\$3" "\$4" "\${PK3S_CUSTOM_VALUE:-unset}"
EOF
      chmod +x "${temp_root}/fake/productive-k3s-core.sh"
      SCRIPT_DIR="${temp_root}/fake/scripts"
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_root}"
      export PK3S_CUSTOM_VALUE=from-parent-env
      addon_record="$(printf "name=custom-addon\tversion=0.1.0\tsource=addons/custom-addon-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"'
    The status should equal 0
    The output should include "args=addon install --tgz"
    The output should include "custom=from-parent-env"
  End

  It 'rejects invalid declarative runtime input metadata instead of using the legacy fallback'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_root="$(mktemp -d)"
      mkdir -p "${temp_root}/pkg/scripts" "${temp_root}/fake/scripts"
      cat >"${temp_root}/pkg/addon.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: custom-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
  productiveK3s:
    stack:
      runtime:
        inputs:
          - name: PK3S_CUSTOM_VALUE
            source: invalid-source-name
EOF
      : >"${temp_root}/pkg/scripts/install.sh"
      tar -czf "${temp_root}/custom-addon-0.1.0.tgz" -C "${temp_root}/pkg" .
      cat >"${temp_root}/fake/productive-k3s-core.sh" <<EOF
#!/usr/bin/env bash
printf "fallback-ran"
EOF
      chmod +x "${temp_root}/fake/productive-k3s-core.sh"
      SCRIPT_DIR="${temp_root}/fake/scripts"
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_root}"
      addon_record="$(printf "name=custom-addon\tversion=0.1.0\tsource=addons/custom-addon-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"'
    The status should equal 1
    The output should include "Invalid addon runtime input source"
    The output should not include "fallback-ran"
  End
End
