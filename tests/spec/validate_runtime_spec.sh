# shellcheck shell=bash disable=SC2016
Describe 'validate runtime'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/validate.sh"

  It 'produces an OK JSON summary for a healthy mocked runtime'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      mkdir -p "${mockdir}"

      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec "$@"
EOF

      cat >"${mockdir}/systemctl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "k3s" ]]; then
  exit 0
fi
exit 1
EOF

      cat >"${mockdir}/k3s" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "kubectl" ]]; then
  shift
fi
case "$*" in
  "get nodes")
    printf "node1\n"
    ;;
  "get nodes --no-headers")
    printf "node1 Ready control-plane 1d v1\n"
    ;;
  *)
    printf "unexpected kubectl args: %s\n" "$*" >&2
    exit 1
    ;;
esac
EOF

      chmod +x "${mockdir}/sudo" "${mockdir}/systemctl" "${mockdir}/k3s"
      export PATH="${mockdir}:$PATH"
      /usr/bin/bash "${script}" --json
    ' bash "$SCRIPT"
    The status should equal 0
    The output should include '"status":"OK","name":"runtime","message":"k3s selected"'
    The output should include '"status":"OK","name":"api","message":"Kubernetes API is reachable"'
    The output should include '"status":"OK","name":"nodes","message":"1 Ready node(s)"'
  End

  It 'delegates stack validation to add-on validate hooks'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      addons_repo="${tmpdir}/addons-repo"
      mkdir -p "${mockdir}" "${addons_repo}/stacks/base" "${addons_repo}/addons/custom-a/scripts" "${addons_repo}/addons/custom-b/scripts"

      cat >"${addons_repo}/stacks/base/stack.yaml" <<'"'"'EOF'"'"'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
spec:
  addons:
    - custom-a
    - custom-b
EOF

      cat >"${addons_repo}/addons/custom-a/scripts/validate.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
      cat >"${addons_repo}/addons/custom-b/scripts/validate.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 1
EOF

      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec "$@"
EOF
      cat >"${mockdir}/systemctl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "k3s" ]]; then
  exit 0
fi
exit 1
EOF
      cat >"${mockdir}/k3s" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "kubectl" ]]; then
  shift
fi
case "$*" in
  "get nodes")
    printf "node1\n"
    ;;
  "get nodes --no-headers")
    printf "node1 Ready control-plane 1d v1\n"
    ;;
  *)
    exit 1
    ;;
esac
EOF

      chmod +x "${mockdir}/sudo" "${mockdir}/systemctl" "${mockdir}/k3s" \
        "${addons_repo}/addons/custom-a/scripts/validate.sh" \
        "${addons_repo}/addons/custom-b/scripts/validate.sh"
      export PATH="${mockdir}:$PATH"
      export PRODUCTIVE_K3S_STACK_NAME=base
      export PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}"
      /usr/bin/bash "${script}" --json
    ' bash "$SCRIPT"
    The status should equal 1
    The output should include '"status":"OK","name":"addon:custom-a","message":"validate hook passed"'
    The output should include '"status":"FAIL","name":"addon:custom-b","message":"validate hook failed"'
  End

  It 'fails strict mode when a stack add-on has no validate hook'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      addons_repo="${tmpdir}/addons-repo"
      mkdir -p "${mockdir}" "${addons_repo}/stacks/base" "${addons_repo}/addons/custom-a/scripts"

      cat >"${addons_repo}/stacks/base/stack.yaml" <<'"'"'EOF'"'"'
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
spec:
  addons:
    - custom-a
EOF

      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec "$@"
EOF
      cat >"${mockdir}/systemctl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" && "${3:-}" == "k3s" ]]; then
  exit 0
fi
exit 1
EOF
      cat >"${mockdir}/k3s" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "kubectl" ]]; then
  shift
fi
case "$*" in
  "get nodes")
    printf "node1\n"
    ;;
  "get nodes --no-headers")
    printf "node1 Ready control-plane 1d v1\n"
    ;;
  *)
    exit 1
    ;;
esac
EOF

      chmod +x "${mockdir}/sudo" "${mockdir}/systemctl" "${mockdir}/k3s"
      export PATH="${mockdir}:$PATH"
      export PRODUCTIVE_K3S_STACK_NAME=base
      export PRODUCTIVE_K3S_ADDONS_REPO_DIR="${addons_repo}"
      /usr/bin/bash "${script}" --json --strict
    ' bash "$SCRIPT"
    The status should equal 1
    The output should include '"status":"WARN","name":"addon:custom-a","message":"no validate hook"'
  End

  It 'prints validate help'
    When run /usr/bin/bash "$SCRIPT" --help
    The status should equal 0
    The output should include 'Usage:'
  End

  It 'rejects unknown validate arguments'
    When run /usr/bin/bash "$SCRIPT" --unknown
    The status should equal 1
    The stderr should include '[FAIL] Unknown argument: --unknown'
  End

  It 'reports runtime service failures before API checks'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      mkdir -p "${mockdir}"
      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec "$@"
EOF
      cat >"${mockdir}/systemctl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 1
EOF
      chmod +x "${mockdir}/sudo" "${mockdir}/systemctl"
      export PATH="${mockdir}:$PATH"
      /usr/bin/bash "${script}" --json
    ' bash "$SCRIPT"
    The status should equal 1
    The output should include '"status":"FAIL","name":"runtime-service","message":"k3s server service is not active"'
  End

  It 'reports API and node readiness failures'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      mkdir -p "${mockdir}"
      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec "$@"
EOF
      cat >"${mockdir}/systemctl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
      cat >"${mockdir}/k3s" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "kubectl" ]]; then
  shift
fi
case "$*" in
  "get nodes")
    printf "node1\n"
    ;;
  "get nodes --no-headers")
    printf "node1 NotReady control-plane 1d v1\n"
    ;;
  *)
    exit 1
    ;;
esac
EOF
      chmod +x "${mockdir}/sudo" "${mockdir}/systemctl" "${mockdir}/k3s"
      export PATH="${mockdir}:$PATH"
      /usr/bin/bash "${script}" --json
    ' bash "$SCRIPT"
    The status should equal 1
    The output should include '"status":"FAIL","name":"nodes","message":"no Ready nodes"'
  End
End
