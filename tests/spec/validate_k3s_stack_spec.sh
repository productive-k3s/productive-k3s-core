# shellcheck shell=bash disable=SC2016
Describe 'validate k3s stack'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/validate-k3s-stack.sh"

  It 'produces an ok JSON summary for a healthy mocked cluster'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      mkdir -p "${mockdir}"

      cat >"${mockdir}/sudo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == "-n" && "${2:-}" == "true" ]]; then
  exit 0
fi
if [[ "${1:-}" == "-v" ]]; then
  exit 0
fi
exec "$@"
EOF

      cat >"${mockdir}/systemctl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == "is-active" && "${2:-}" == "--quiet" ]]; then
  exit 0
fi
if [[ "${1:-}" == "list-unit-files" ]]; then
  printf "nfs-server.service enabled\n"
  exit 0
fi
exit 0
EOF

      cat >"${mockdir}/exportfs" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "/srv/nfs/k8s-share 192.168.1.0/24(sync,wdelay,hide)\n"
EOF

      cat >"${mockdir}/getent" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "hosts" ]]; then
  printf "127.0.0.1 %s\n" "${2:-unknown}"
  exit 0
fi
exit 1
EOF

      cat >"${mockdir}/curl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
url="${*: -1}"
if [[ "${url}" == *"/v2/" ]]; then
  printf "401"
else
  printf "200"
fi
EOF

      cat >"${mockdir}/docker" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF

      cat >"${mockdir}/jq" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf ""
EOF

      cat >"${mockdir}/k3s" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == "kubectl" ]]; then
  shift
fi
args="$*"
case "${args}" in
  "get nodes -o wide")
    cat <<'"'"'OUT'"'"'
NAME STATUS ROLES AGE VERSION INTERNAL-IP
node1 Ready control-plane,master 1d v1 10.0.0.1
OUT
    ;;
  "get nodes --no-headers")
    printf "node1 Ready control-plane,master 1d v1 10.0.0.1\n"
    ;;
  "get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide")
    cat <<'"'"'OUT'"'"'
NAMESPACE NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES
kube-system coredns-1 1/1 Running 0 1d 10.42.0.2 node1 <none> <none>
OUT
    ;;
  "get pods -A --no-headers")
    printf "kube-system coredns-1 1/1 Running 0 1d\n"
    ;;
  "get sc")
    cat <<'"'"'OUT'"'"'
NAME PROVISIONER RECLAIMPOLICY VOLUMEBINDINGMODE ALLOWVOLUMEEXPANSION AGE
longhorn-single (default) driver Delete Immediate true 1d
OUT
    ;;
  get\ sc\ -o\ jsonpath=*is-default-class* )
    printf "longhorn-single|true\n"
    ;;
  "get ingress -A")
    cat <<'"'"'OUT'"'"'
NAMESPACE NAME CLASS HOSTS ADDRESS PORTS AGE
cattle-system rancher traefik rancher.home.arpa 10.0.0.1 80,443 1d
registry registry traefik registry.home.arpa 10.0.0.1 80,443 1d
OUT
    ;;
  "get namespace cert-manager"|"get namespace longhorn-system"|"get namespace cattle-system"|"get namespace registry")
    exit 0
    ;;
  "get pods -n cert-manager --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide")
    cat <<'"'"'OUT'"'"'
NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES
cert-manager-1 1/1 Running 0 1d 10.42.0.3 node1 <none> <none>
OUT
    ;;
  "get pods -n longhorn-system --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide")
    cat <<'"'"'OUT'"'"'
NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES
longhorn-manager-1 1/1 Running 0 1d 10.42.0.4 node1 <none> <none>
OUT
    ;;
  "get pods -n cattle-system --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide")
    cat <<'"'"'OUT'"'"'
NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES
rancher-1 1/1 Running 0 1d 10.42.0.5 node1 <none> <none>
OUT
    ;;
  "get pods -n registry --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide")
    cat <<'"'"'OUT'"'"'
NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES
registry-1 1/1 Running 0 1d 10.42.0.6 node1 <none> <none>
OUT
    ;;
  "get pods -n cert-manager --no-headers"|"get pods -n longhorn-system --no-headers"|"get pods -n cattle-system --no-headers"|"get pods -n registry --no-headers")
    printf "pod 1/1 Running 0 1d\n"
    ;;
  "get deploy -n cert-manager --no-headers"|"get deploy -n longhorn-system --no-headers"|"get deploy -n cattle-system --no-headers"|"get deploy -n registry --no-headers")
    printf "deployment-a 1/1 1 1 1d\n"
    ;;
  "get statefulset -n cert-manager --no-headers"|"get statefulset -n longhorn-system --no-headers"|"get statefulset -n cattle-system --no-headers"|"get statefulset -n registry --no-headers")
    printf ""
    ;;
  "get daemonset -n cert-manager --no-headers"|"get daemonset -n longhorn-system --no-headers"|"get daemonset -n cattle-system --no-headers"|"get daemonset -n registry --no-headers")
    printf "daemon-a 1 1 1 1 1 1d\n"
    ;;
  "get clusterissuer")
    cat <<'"'"'OUT'"'"'
NAME READY AGE
letsencrypt True 1d
OUT
    ;;
  "get certificates -A")
    cat <<'"'"'OUT'"'"'
NAMESPACE NAME READY SECRET AGE
cattle-system tls-rancher True tls-rancher 1d
OUT
    ;;
  "get volumes.longhorn.io -n longhorn-system")
    cat <<'"'"'OUT'"'"'
NAME DATA ENGINE STATE ROBUSTNESS SCHEDULED NODE SIZE AGE
vol-1 v1 attached healthy node1 10Gi 1d
OUT
    ;;
  "get volumes.longhorn.io -n longhorn-system -o json")
    printf "{\"items\":[]}\n"
    ;;
  "get settings.longhorn.io -n longhorn-system storage-minimal-available-percentage -o jsonpath={.value}")
    printf "10"
    ;;
  "get secret tls-ca -n cattle-system"|"get ingress rancher -n cattle-system"|"get ingress registry -n registry")
    exit 0
    ;;
  "get pvc -n registry")
    cat <<'"'"'OUT'"'"'
NAME STATUS VOLUME CAPACITY ACCESS MODES STORAGECLASS AGE
registry-pvc Bound pvc-123 10Gi RWO longhorn-single 1d
OUT
    ;;
  *)
    printf "unhandled k3s mock args: %s\n" "${args}" >&2
    exit 1
    ;;
esac
EOF

      cat >"${mockdir}/kubectl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec k3s kubectl "$@"
EOF

      chmod +x "${mockdir}/sudo" "${mockdir}/systemctl" "${mockdir}/exportfs" "${mockdir}/getent" "${mockdir}/curl" "${mockdir}/docker" "${mockdir}/jq" "${mockdir}/k3s" "${mockdir}/kubectl"
      export PATH="${mockdir}:$PATH"
      /usr/bin/bash "${script}" --json
    ' bash "$SCRIPT"
    The status should equal 0
    The output should include '"status":"ok"'
    The output should include 'all nodes are Ready'
    The output should include 'Longhorn volumes API is responding'
    The output should include 'registry PVC is Bound'
    The output should include 'Rancher HTTPS endpoint responds with HTTP 200'
    The output should include 'Registry HTTPS endpoint responds with HTTP 401'
  End

  It 'fails docker registry validation when credentials are incomplete'
    When run bash -lc '
      script="$1"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      mkdir -p "${mockdir}"
      for cmd in sudo systemctl exportfs getent curl docker jq; do
        cat >"${mockdir}/${cmd}" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${mockdir}/${cmd}"
      done
      cat >"${mockdir}/k3s" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [[ "${1:-}" == "kubectl" ]]; then shift; fi
args="$*"
case "${args}" in
  "get nodes -o wide")
    printf "NAME STATUS ROLES AGE VERSION\nnode1 Ready control-plane 1d v1\n"
    ;;
  "get nodes --no-headers")
    printf "node1 Ready control-plane 1d v1\n"
    ;;
  "get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed -o wide")
    printf "NAMESPACE NAME READY STATUS RESTARTS AGE IP NODE NOMINATED NODE READINESS GATES\n"
    ;;
  "get pods -A --no-headers")
    printf ""
    ;;
  "get sc")
    printf "NAME\nlonghorn-single (default)\n"
    ;;
  "get ingress -A")
    printf "NAMESPACE NAME CLASS HOSTS ADDRESS PORTS AGE\n"
    ;;
  *)
    exit 1
    ;;
esac
EOF
      cat >"${mockdir}/kubectl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exec k3s kubectl "$@"
EOF
      chmod +x "${mockdir}/k3s" "${mockdir}/kubectl"
      export PATH="${mockdir}:$PATH"
      export REGISTRY_USER="only-user"
      unset REGISTRY_PASSWORD
      /usr/bin/bash "${script}" --json --docker-registry-test
    ' bash "$SCRIPT"
    The status should equal 1
    The output should include 'set both REGISTRY_USER and REGISTRY_PASSWORD, or neither'
    The output should include '"status":"fail"'
  End
End
