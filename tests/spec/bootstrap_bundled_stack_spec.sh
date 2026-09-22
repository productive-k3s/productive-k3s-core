# shellcheck shell=bash disable=SC2016
Describe 'bundled stack addon runtime'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/apply.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'treats bundled stack add-ons as dry-run actions without invoking packaged installers'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_bundle_dir="$(mktemp -d)"
      touch "${temp_bundle_dir}/custom-addon-0.1.0.tgz"
      DRY_RUN=1
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_bundle_dir}"
      addon_record="$(printf "name=custom-addon\tversion=0.1.0\tsource=addons/custom-addon-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"
      printf "|result=%s" "${MANIFEST_RESULT[stack_addons]:-pending}"'
    The status should equal 0
    The output should include "Installing stack add-on 'custom-addon' from stack 'base'"
    The output should include "[dry-run] Would install bundled add-on package 'addons/custom-addon-0.1.0.tgz'"
    The output should include "|result=pending"
  End

  It 'invokes the generic packaged add-on installer for bundled artifacts'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_root="$(mktemp -d)"
      mkdir -p "${temp_root}/pkg/scripts" "${temp_root}/fake"
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
      cat >"${temp_root}/fake/productive-k3s-core.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "args=%s %s %s %s" "$1" "$2" "$3" "$4"
EOF
      chmod +x "${temp_root}/fake/productive-k3s-core.sh"
      SCRIPT_DIR="${temp_root}/fake/scripts"
      mkdir -p "${SCRIPT_DIR}"
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_root}"
      addon_record="$(printf "name=custom-addon\tversion=0.1.0\tsource=addons/custom-addon-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"'
    The status should equal 0
    The output should include "args=addon install --tgz"
  End

  It 'rejects missing bundled add-on artifacts'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      temp_root="$(mktemp -d)"
      PRODUCTIVE_K3S_STACK_NAME=base
      PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR="${temp_root}"
      addon_record="$(printf "name=custom-addon\tversion=0.1.0\tsource=addons/custom-addon-0.1.0.tgz")"
      install_stack_addon_record "${addon_record}"'
    The status should equal 1
    The output should include "Bundled add-on package not found: addons/custom-addon-0.1.0.tgz"
  End
End
