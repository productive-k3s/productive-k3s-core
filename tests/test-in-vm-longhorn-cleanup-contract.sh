#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

export PRODUCTIVE_K3S_LIB_ONLY=1
# shellcheck source=tests/test-in-vm.sh
source "${REPO_DIR}/tests/test-in-vm.sh"

REMOTE_DIR="/opt/productive-k3s-core"
command_text="$(longhorn_cluster_resources_absent_command)"

required_resources=(
  storageclasses
  csidrivers
  priorityclasses
  validatingwebhookconfigurations
  mutatingwebhookconfigurations
  apiservices
  clusterroles
  clusterrolebindings
  customresourcedefinitions
)

for resource_type in "${required_resources[@]}"; do
  grep -q "${resource_type}|" <<< "${command_text}" || \
    fail "rollback verification does not inspect ${resource_type}"
done

grep -q 'Longhorn cluster-scoped resources remain after rollback' <<< "${command_text}" || \
  fail "rollback verification does not emit a residue diagnosis"
grep -q '/var/lib/rancher/rke2/bin/kubectl' <<< "${command_text}" || \
  fail "rollback verification does not support rke2"
grep -q 'sudo k3s kubectl' <<< "${command_text}" || \
  fail "rollback verification does not support k3s"

printf '[PASS] rollback verifies all known Longhorn cluster-scoped resources\n'
