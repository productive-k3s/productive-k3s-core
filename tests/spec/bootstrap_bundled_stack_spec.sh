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
End
