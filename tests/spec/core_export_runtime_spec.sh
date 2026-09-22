# shellcheck shell=bash disable=SC2016
Describe 'core export runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/export-runtime.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'writes install-config.env with frozen export variables'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      export_runtime_init
      export_runtime_add_env "PRODUCTIVE_K3S_STACK_NAME" "base"
      export_runtime_add_env "TELEMETRY_ENABLED" "false"
      export_runtime_add_env "PRODUCTIVE_K3S_EXPORT_OUTPUT" "/tmp/bundle dir"
      export_runtime_write_install_config "${tmpdir}/install-config.env"
      cat "${tmpdir}/install-config.env"'
    The status should equal 0
    The output should include "export PRODUCTIVE_K3S_STACK_NAME='base'"
    The output should include "export TELEMETRY_ENABLED='false'"
    The output should include "export PRODUCTIVE_K3S_EXPORT_OUTPUT='/tmp/bundle dir'"
  End

  It 'writes manifest.json with resolved export metadata'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      export_runtime_init
      export_runtime_set_metadata "command" "stack export"
      export_runtime_set_metadata "subject_kind" "stack"
      export_runtime_set_metadata "subject_ref" "base"
      export_runtime_set_metadata "artifact_name" "stack.tgz"
      export_runtime_set_metadata "interactive" "false"
      export_runtime_set_metadata "telemetry_enabled" "false"
      export_runtime_write_manifest "${tmpdir}/manifest.json"
      cat "${tmpdir}/manifest.json"'
    The status should equal 0
    The output should include '"schema_version": "1"'
    The output should include '"command": "stack export"'
    The output should include '"kind": "stack"'
    The output should include '"ref": "base"'
    The output should include '"artifact_name": "stack.tgz"'
    The output should include '"interactive": "false"'
    The output should include '"telemetry_enabled": "false"'
  End

  It 'rejects unsupported manifest metadata keys'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      export_runtime_init
      export_runtime_set_metadata unsupported value'
    The status should equal 1
    The stderr should include 'Unsupported export metadata key: unsupported'
  End

  It 'renders stack templates with subject and artifact placeholders'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      readme="${tmpdir}/README.md"
      agents="${tmpdir}/AGENTS.md"
      export_runtime_write_readme "${readme}" "base" "base-stack.tgz"
      export_runtime_write_stack_agents_md "${agents}" "base" "base-stack.tgz"
      printf "__README__\n"
      grep -E "base|base-stack.tgz" "${readme}"
      printf "__AGENTS__\n"
      grep -E "Subject:|Packaged artifact:" "${agents}"'
    The status should equal 0
    The output should include '__README__'
    The output should include 'base-stack.tgz'
    The output should include '__AGENTS__'
    The output should include 'Subject: `base`'
    The output should include 'Packaged artifact: `base-stack.tgz`'
    The output should not include '{{subject_ref}}'
    The output should not include '{{artifact_name}}'
  End

  It 'fails when an export template is missing'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      export_runtime_render_template "${tmpdir}/missing.md" "${tmpdir}/out.md" base stack.tgz'
    The status should equal 1
    The stderr should include 'Export template not found:'
  End

  It 'copies the core runtime files into an exported bundle root'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo_root="${SHELLSPEC_PROJECT_ROOT}"
      bundle_root="$(mktemp -d)"
      export_runtime_copy_core_runtime "${repo_root}" "${bundle_root}"
      test -x "${bundle_root}/productive-k3s-core.sh"
      test -x "${bundle_root}/scripts/productive-k3s-core.sh"
      test -f "${bundle_root}/scripts/apply.sh"
      test -f "${bundle_root}/scripts/export-templates/stack/README.md"
      find "${bundle_root}" -maxdepth 4 -type f | sed "s#${bundle_root}/##" | sort | grep -E "^(productive-k3s-core.sh|scripts/(apply|export-runtime|validate)\\.sh|scripts/export-templates/stack/README.md)$"'
    The status should equal 0
    The output should include 'productive-k3s-core.sh'
    The output should include 'scripts/apply.sh'
    The output should include 'scripts/export-runtime.sh'
    The output should include 'scripts/export-templates/stack/README.md'
  End

  It 'writes stack install and preflight scripts with expected replay behavior'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      install_script="${tmpdir}/install.sh"
      preflight_script="${tmpdir}/preflight.sh"
      export_runtime_write_stack_install_script "${install_script}" "stack.tgz" --dry-run "--label=demo stack"
      export_runtime_write_stack_preflight_script "${preflight_script}" "stack.tgz"
      test -x "${install_script}"
      test -x "${preflight_script}"
      printf "__INSTALL__\n"
      grep -E "skip-preflight|preflight-only|stack install --tgz|--label=demo" "${install_script}"
      printf "__PREFLIGHT__\n"
      grep -E "need_exec|need_file|stack validate --tgz|preflight --mode stack|exported stack bundle preflight passed" "${preflight_script}"'
    The status should equal 0
    The output should include '__INSTALL__'
    The output should include '--skip-preflight'
    The output should include '--preflight-only'
    The output should include 'stack install --tgz "${SCRIPT_DIR}/stack.tgz"'
    The output should include "'--label=demo stack'"
    The output should include '__PREFLIGHT__'
    The output should include 'stack validate --tgz "${SCRIPT_DIR}/stack.tgz"'
    The output should include 'preflight --mode stack'
    The output should include 'exported stack bundle preflight passed'
  End
End
