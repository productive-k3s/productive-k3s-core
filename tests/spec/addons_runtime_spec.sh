# shellcheck shell=bash disable=SC2016
Describe 'addons runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/addons-runtime.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'resolves stack and addon sources from the configured addons repository'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/addons/demo/scripts" "${repo}/stacks/base"
      cat >"${repo}/stacks/base/stack.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
spec:
  addons:
    - cert-manager
    - name: demo
      version: 0.1.0
      source: addons/demo.tgz
EOF
      PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo}"
      printf "repo=%s\n" "$(resolve_addons_repo_dir)"
      printf "addon=%s\n" "$(resolve_addon_source_dir demo)"
      printf "stack=%s\n" "$(resolve_stack_source_dir base)"
      printf "manifest=%s\n" "$(resolve_stack_source_manifest base)"
      stack_source_addon_records base
      printf "__NAMES__\n"
      stack_source_addon_names base'
    The status should equal 0
    The output should include 'repo='
    The output should include '/addons/demo'
    The output should include '/stacks/base'
    The output should include 'name=cert-manager'
    The output should include 'name=demo'
    The output should include 'version=0.1.0'
    The output should include 'source=addons/demo.tgz'
    The output should include '__NAMES__'
    The output should include 'cert-manager'
    The output should include 'demo'
  End

  It 'detects and runs addon source scripts from the addon directory'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/addons/demo/scripts"
      cat >"${repo}/addons/demo/scripts/validate.sh" <<EOF
#!/usr/bin/env bash
printf "pwd=%s args=%s %s\n" "\$(basename "\$PWD")" "\${1:-}" "\${2:-}"
EOF
      chmod +x "${repo}/addons/demo/scripts/validate.sh"
      PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo}"
      addon_source_script_exists demo validate.sh
      printf "exists=%s\n" "$?"
      run_addon_source_script demo validate.sh one two'
    The status should equal 0
    The output should include 'exists=0'
    The output should include 'pwd=demo args=one two'
  End

  It 'fails cleanly when sources are missing'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/addons" "${repo}/stacks"
      PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo}"
      resolve_addon_source_dir missing || printf "missing-addon\n"
      resolve_stack_source_manifest missing || printf "missing-stack\n"
      run_addon_source_script missing validate.sh || printf "missing-script\n"'
    The status should equal 0
    The output should include 'missing-addon'
    The output should include 'missing-stack'
    The output should include 'missing-script'
  End
End
