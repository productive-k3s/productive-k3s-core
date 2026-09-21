# shellcheck shell=bash disable=SC2016
Describe 'productive-k3s-core operation events'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/productive-k3s-core.sh"

  It 'emits addon validation events without mixing human logs into stdout'
    work_dir="$(mktemp -d)"
    pkg_dir="${work_dir}/pkg"
    archive="${work_dir}/demo-addon.tgz"
    mkdir -p "${pkg_dir}/scripts"
    cat >"${pkg_dir}/addon.yaml" <<'EOF'
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: demo-addon
  version: 0.1.0
spec:
  type: shell
  install:
    script: scripts/install.sh
EOF
    cat >"${pkg_dir}/scripts/install.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${pkg_dir}/scripts/install.sh"
    tar -czf "${archive}" -C "${pkg_dir}" .

    When run bash -lc '"$1" --events ndjson addon validate --tgz "$2"' bash "$SCRIPT" "$archive"
    The status should equal 0
    The output should include '"schema_version":"productive-k3s-operation-event/v1"'
    The output should include '"component":"core"'
    The output should include '"operation":"addon.validate"'
    The output should include '"step":"operation.started"'
    The output should include '"step":"addon.package.extract"'
    The output should include '"step":"addon.package.validate"'
    The output should include '"step":"operation.completed"'
    The output should include '"subject":"demo-addon"'
    The output should not include 'Addon package validation passed'
    The stderr should include 'Addon package validation passed'
  End

  It 'rejects unsupported operation event formats'
    When run bash -lc '"$1" --events json help' bash "$SCRIPT"
    The status should equal 2
    The stderr should include 'unsupported --events format: json; supported format: ndjson'
  End
End
