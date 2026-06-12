#!/usr/bin/env bash
set -euo pipefail

PROFILE="core"
PLATFORM="ubuntu"
VM_IMAGE=""
VM_CPUS="4"
VM_MEMORY="8G"
VM_DISK="40G"
KEEP_VM="n"
PURGE_ON_CLEANUP="n"
VM_CLEANUP_TIMEOUT_SECONDS="${VM_CLEANUP_TIMEOUT_SECONDS:-120}"
VM_NAME=""
REMOTE_USER=""
REMOTE_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"
VM_CREATED="n"
ARTIFACTS_DIR="$REPO_DIR/test-artifacts"
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_BASENAME=""
ARTIFACT_PATH=""
PUBLIC_ARTIFACT_PATH=""
ARTIFACT_STATUS="failed"
BOOTSTRAP_MANIFEST_REMOTE=""
BOOTSTRAP_MANIFEST_LOCAL=""
TRANSFER_STAGING_ROOT=""
TRANSFER_STAGED_REPO=""
TRANSFER_STAGED_ADDONS_REPO=""
ADDONS_REPO_DIR=""
REMOTE_ADDONS_DIR=""
REMOTE_COMMAND_STATUS=""

usage() {
  cat <<'EOU'
Usage:
  ./tests/test-in-vm.sh [--platform ubuntu|debian12|debian13] [--profile smoke|core|full|full-clean|full-rollback] [--name <vm-name>] [--image <release-or-url>] [--remote-user <user>] [--remote-dir <path>] [--cpus <n>] [--memory <size>] [--disk <size>] [--keep-vm] [--purge-on-cleanup]

Profiles:
  smoke          Launch a clean VM and run bootstrap in --dry-run mode
  core           Launch a clean VM, install k3s + helm, skip optional components, then validate
  full           Launch a clean VM, install the full stack with default answers, then validate
  full-clean     Run the full profile and then run scripts/cleanup.sh --apply inside the VM
  full-rollback  Run the full profile and then build/apply a rollback from the generated bootstrap manifest

Platforms:
  ubuntu         Supported baseline. Defaults to image 24.04 and user ubuntu
  debian12       Supported path. Defaults to Debian 12 bookworm cloud image and user ubuntu
  debian13       Supported path. Defaults to Debian 13 trixie cloud image and user ubuntu

Notes:
  - Requires Multipass on the host.
  - The VM is deleted automatically unless --keep-vm is set.
  - full, full-clean, and full-rollback are heavier and slower; use them intentionally.
EOU
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '[INFO] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

err() {
  printf '[ERROR] %s\n' "$1" >&2
}

default_image_for_platform() {
  case "$1" in
    ubuntu)
      printf '24.04'
      ;;
    debian12)
      printf 'https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2'
      ;;
    debian13)
      printf 'https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2'
      ;;
    *)
      return 1
      ;;
  esac
}

default_remote_user_for_platform() {
  case "$1" in
    ubuntu)
      printf 'ubuntu'
      ;;
    debian12)
      printf 'ubuntu'
      ;;
    debian13)
      printf 'ubuntu'
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_addons_repo_dir() {
  if [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" && -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/addons" ]]; then
    printf '%s\n' "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}"
    return 0
  fi

  local sibling_dir
  sibling_dir="$(cd "${REPO_DIR}/.." && pwd)/productive-k3s-addons"
  if [[ -d "${sibling_dir}/addons" ]]; then
    printf '%s\n' "${sibling_dir}"
    return 0
  fi

  return 1
}

apply_platform_defaults() {
  case "$PLATFORM" in
    ubuntu|debian12|debian13) ;;
    *)
      err "Unsupported platform: $PLATFORM"
      usage
      exit 1
      ;;
  esac

  if [[ -z "$VM_IMAGE" ]]; then
    VM_IMAGE="$(default_image_for_platform "$PLATFORM")"
  fi
  if [[ -z "$REMOTE_USER" ]]; then
    REMOTE_USER="$(default_remote_user_for_platform "$PLATFORM")"
  fi
  if [[ -z "$REMOTE_DIR" ]]; then
    REMOTE_DIR="/home/${REMOTE_USER}/${REPO_NAME}"
  fi
  if [[ -z "$REMOTE_ADDONS_DIR" ]]; then
    REMOTE_ADDONS_DIR="/home/${REMOTE_USER}/productive-k3s-addons"
  fi
}

cleanup() {
  if [[ -n "$TRANSFER_STAGING_ROOT" && -d "$TRANSFER_STAGING_ROOT" ]]; then
    rm -rf "$TRANSFER_STAGING_ROOT"
    TRANSFER_STAGING_ROOT=""
  fi
  write_artifacts
  TRANSFER_STAGED_REPO=""
  TRANSFER_STAGED_ADDONS_REPO=""
  if [[ "$KEEP_VM" == "y" || "$VM_CREATED" != "y" ]]; then
    return
  fi
  log "Cleaning up VM: $VM_NAME"
  run_multipass_cleanup delete "$VM_NAME"
  if [[ "$PURGE_ON_CLEANUP" == "y" ]]; then
    run_multipass_cleanup purge
  fi
}

run_multipass_cleanup() {
  local subcommand="$1"
  shift || true

  if command -v timeout >/dev/null 2>&1; then
    if timeout --kill-after=5s "${VM_CLEANUP_TIMEOUT_SECONDS}s" multipass "${subcommand}" "$@" >/dev/null 2>&1; then
      return 0
    fi
    warn "multipass ${subcommand} timed out after ${VM_CLEANUP_TIMEOUT_SECONDS}s; continuing"
    return 0
  fi

  multipass "${subcommand}" "$@" >/dev/null 2>&1 || true
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --platform)
        PLATFORM="${2:-}"
        shift
        ;;
      --profile)
        PROFILE="${2:-}"
        shift
        ;;
      --name)
        VM_NAME="${2:-}"
        shift
        ;;
      --image)
        VM_IMAGE="${2:-}"
        shift
        ;;
      --remote-user)
        REMOTE_USER="${2:-}"
        shift
        ;;
      --remote-dir)
        REMOTE_DIR="${2:-}"
        shift
        ;;
      --cpus)
        VM_CPUS="${2:-}"
        shift
        ;;
      --memory)
        VM_MEMORY="${2:-}"
        shift
        ;;
      --disk)
        VM_DISK="${2:-}"
        shift
        ;;
      --keep-vm)
        KEEP_VM="y"
        ;;
      --purge-on-cleanup)
        PURGE_ON_CLEANUP="y"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  case "$PROFILE" in
    smoke|core|full|full-clean|full-rollback) ;;
    *)
      err "Unsupported profile: $PROFILE"
      usage
      exit 1
      ;;
  esac

  apply_platform_defaults

  if [[ -z "$VM_NAME" ]]; then
    VM_NAME="productive-k3s-core-test-${PLATFORM}-${PROFILE}-$(date +%Y%m%d-%H%M%S)"
  fi

  ARTIFACT_BASENAME="test-in-vm-${RUN_TIMESTAMP}-${PROFILE}-${VM_NAME}"
  ARTIFACT_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.json"
  PUBLIC_ARTIFACT_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}-public.json"
}

ensure_artifacts_dir() {
  mkdir -p "$ARTIFACTS_DIR"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

write_local_artifact() {
  [[ -n "$ARTIFACT_PATH" ]] || return
  ensure_artifacts_dir
  cat > "$ARTIFACT_PATH" <<EOF
{
  "test_type": "vm",
  "platform": "$(json_escape "$PLATFORM")",
  "profile": "$(json_escape "$PROFILE")",
  "vm_name": "$(json_escape "$VM_NAME")",
  "vm_created": "$(json_escape "$VM_CREATED")",
  "keep_vm": "$(json_escape "$KEEP_VM")",
  "purge_on_cleanup": "$(json_escape "$PURGE_ON_CLEANUP")",
  "image": "$(json_escape "$VM_IMAGE")",
  "remote_user": "$(json_escape "$REMOTE_USER")",
  "remote_dir": "$(json_escape "$REMOTE_DIR")",
  "cpus": "$(json_escape "$VM_CPUS")",
  "memory": "$(json_escape "$VM_MEMORY")",
  "disk": "$(json_escape "$VM_DISK")",
  "repo_dir": "$(json_escape "$REPO_DIR")",
  "status": "$(json_escape "$ARTIFACT_STATUS")",
  "bootstrap_manifest_remote": "$(json_escape "$BOOTSTRAP_MANIFEST_REMOTE")",
  "bootstrap_manifest_local": "$(json_escape "$BOOTSTRAP_MANIFEST_LOCAL")"
}
EOF
}

write_public_artifact() {
  [[ -n "$PUBLIC_ARTIFACT_PATH" ]] || return
  ensure_artifacts_dir
  cat > "$PUBLIC_ARTIFACT_PATH" <<EOF
{
  "test_type": "vm",
  "artifact_scope": "public",
  "platform": "$(json_escape "$PLATFORM")",
  "profile": "$(json_escape "$PROFILE")",
  "vm_created": "$(json_escape "$VM_CREATED")",
  "keep_vm": "$(json_escape "$KEEP_VM")",
  "purge_on_cleanup": "$(json_escape "$PURGE_ON_CLEANUP")",
  "image": "$(json_escape "$VM_IMAGE")",
  "cpus": "$(json_escape "$VM_CPUS")",
  "memory": "$(json_escape "$VM_MEMORY")",
  "disk": "$(json_escape "$VM_DISK")",
  "status": "$(json_escape "$ARTIFACT_STATUS")",
  "bootstrap_manifest_copied": "$( [[ -n "$BOOTSTRAP_MANIFEST_LOCAL" ]] && printf 'y' || printf 'n' )"
}
EOF
}

write_artifacts() {
  write_local_artifact
  write_public_artifact
}

launch_vm() {
  local timeout_secs="300"
  local sleep_secs="15"
  local start_ts now_ts

  log "Launching VM: $VM_NAME"
  start_ts=$(date +%s)

  while true; do
    if multipass launch "$VM_IMAGE" --name "$VM_NAME" --cpus "$VM_CPUS" --memory "$VM_MEMORY" --disk "$VM_DISK"; then
      VM_CREATED="y"
      return 0
    fi

    now_ts=$(date +%s)
    if (( now_ts - start_ts >= timeout_secs )); then
      err "Failed to launch VM '${VM_NAME}' within ${timeout_secs}s"
      return 1
    fi

    warn "VM launch did not succeed yet. Waiting ${sleep_secs}s before retrying."
    sleep "$sleep_secs"
  done
}

copy_repo() {
  local remote_parent remote_addons_parent
  remote_parent="$(dirname "$REMOTE_DIR")"
  remote_addons_parent="$(dirname "$REMOTE_ADDONS_DIR")"
  log "Copying repository to VM"
  multipass exec "$VM_NAME" -- bash -lc "sudo mkdir -p '$remote_parent' '$remote_addons_parent' && sudo chown '$REMOTE_USER':'$REMOTE_USER' '$remote_parent' '$remote_addons_parent' && rm -rf '$REMOTE_DIR' '$REMOTE_ADDONS_DIR'"
  prepare_repo_transfer_dir
  multipass transfer -r "$TRANSFER_STAGED_REPO" "$VM_NAME:$remote_parent"
  if [[ -n "$ADDONS_REPO_DIR" ]]; then
    prepare_addons_transfer_dir
    multipass transfer -r "$TRANSFER_STAGED_ADDONS_REPO" "$VM_NAME:$remote_addons_parent"
  fi
}

prepare_repo_transfer_dir() {
  local staged_name
  local staging_parent

  staged_name="$(basename "$REMOTE_DIR")"
  if [[ -z "$TRANSFER_STAGING_ROOT" ]]; then
    staging_parent="${HOME}/pk3s-transfer-staging"
    mkdir -p "$staging_parent"
    TRANSFER_STAGING_ROOT="$(mktemp -d "${staging_parent}/staging.XXXXXX")"
  fi

  TRANSFER_STAGED_REPO="${TRANSFER_STAGING_ROOT}/${staged_name}"
  rm -rf "$TRANSFER_STAGED_REPO"
  mkdir -p "$TRANSFER_STAGED_REPO"

  tar -C "$REPO_DIR" \
    --exclude=.git \
    --exclude=.codex \
    --exclude=dist \
    --exclude=docs/.venv \
    --exclude=docs/site \
    --exclude=runs \
    --exclude=tests/coverage \
    --exclude=test-artifacts \
    -cf - . | tar -xf - -C "$TRANSFER_STAGED_REPO"
}

prepare_addons_transfer_dir() {
  local staged_name
  local staging_parent

  staged_name="$(basename "$REMOTE_ADDONS_DIR")"
  if [[ -z "$TRANSFER_STAGING_ROOT" ]]; then
    staging_parent="${HOME}/pk3s-transfer-staging"
    mkdir -p "$staging_parent"
    TRANSFER_STAGING_ROOT="$(mktemp -d "${staging_parent}/staging.XXXXXX")"
  fi

  TRANSFER_STAGED_ADDONS_REPO="${TRANSFER_STAGING_ROOT}/${staged_name}"
  rm -rf "$TRANSFER_STAGED_ADDONS_REPO"
  mkdir -p "$TRANSFER_STAGED_ADDONS_REPO"

  tar -C "$ADDONS_REPO_DIR" \
    --exclude=.git \
    --exclude=.codex \
    --exclude=dist \
    --exclude=docs/.venv \
    --exclude=docs/site \
    --exclude=runs \
    --exclude=tests/coverage \
    --exclude=test-artifacts \
    -cf - . | tar -xf - -C "$TRANSFER_STAGED_ADDONS_REPO"
}

run_in_vm() {
  local cmd="$1"
  multipass exec "$VM_NAME" -- bash -lc "$cmd" </dev/null
}

wait_for_remote_file() {
  local remote_path="$1"
  local timeout_secs="${2:-1800}"
  local sleep_secs="${3:-5}"
  local start_ts now_ts
  start_ts="$(date +%s)"

  while true; do
    if run_in_vm "test -f '$remote_path'"; then
      return 0
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_secs )); then
      return 1
    fi

    sleep "$sleep_secs"
  done
}

run_remote_command_with_status() {
  local command="$1"
  local timeout_secs="${2:-1800}"
  local remote_log remote_status remote_pid quoted_command command_status

  remote_log="/tmp/pk3s-remote-cmd-${RUN_TIMESTAMP}-$$.log"
  remote_status="/tmp/pk3s-remote-cmd-${RUN_TIMESTAMP}-$$.status"
  remote_pid="/tmp/pk3s-remote-cmd-${RUN_TIMESTAMP}-$$.pid"
  command="${command}; remote_rc=\$?; printf '%s\\n' \"\${remote_rc}\" > '${remote_status}'; exit \"\${remote_rc}\""
  quoted_command="$(printf '%q' "$command")"

  run_in_vm "rm -f '$remote_log' '$remote_status' '$remote_pid'; nohup bash -lc ${quoted_command} > '$remote_log' 2>&1 < /dev/null & echo \$! > '$remote_pid'"
  REMOTE_COMMAND_STATUS=""
  wait_for_remote_file "$remote_status" "$timeout_secs" 5 || return 124
  command_status="$(run_in_vm "cat '$remote_status' 2>/dev/null || true" | tr -d '\r\n')"
  REMOTE_COMMAND_STATUS="${command_status}"
  [[ "${command_status}" == "0" ]]
}

bootstrap_engine_env_prefix() {
  local prefix=""
  if [[ -n "${PRODUCTIVE_K3S_DISTRO:-}" ]]; then
    prefix+="PRODUCTIVE_K3S_DISTRO=$(printf '%q' "${PRODUCTIVE_K3S_DISTRO}") "
  fi
  if [[ -n "${PRODUCTIVE_K3S_ENGINE:-}" ]]; then
    prefix+="PRODUCTIVE_K3S_ENGINE=$(printf '%q' "${PRODUCTIVE_K3S_ENGINE}") "
  fi
  if [[ -n "${PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS:-}" ]]; then
    prefix+="PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=$(printf '%q' "${PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS}") "
  fi
  if [[ -n "$ADDONS_REPO_DIR" ]]; then
    prefix+="PRODUCTIVE_K3S_ADDONS_REPO_DIR=$(printf '%q' "${REMOTE_ADDONS_DIR}") "
  fi
  printf '%s' "${prefix}"
}

core_cli_command_in_vm() {
  local subcommand="$1"
  local extra_args="$2"
  local stdin_payload="$3"
  local engine_prefix
  engine_prefix="$(bootstrap_engine_env_prefix)"
  printf "cd '%s' && bootstrap_answers_file=\"\$(mktemp)\" && printf '%%s' %s > \"\${bootstrap_answers_file}\" && %s./productive-k3s-core.sh %s %s < \"\${bootstrap_answers_file}\"; bootstrap_rc=\$?; rm -f \"\${bootstrap_answers_file}\"; test \"\${bootstrap_rc}\" -eq 0" \
    "$REMOTE_DIR" \
    "$stdin_payload" \
    "$engine_prefix" \
    "$subcommand" \
    "$extra_args"
}

capture_bootstrap_manifest() {
  local remote_manifest local_target
  remote_manifest="$(run_in_vm "cd '$REMOTE_DIR' && ls -1t runs/apply-*.json 2>/dev/null | head -1" | tr -d '\r')"
  [[ -n "$remote_manifest" ]] || return 0

  BOOTSTRAP_MANIFEST_REMOTE="$REMOTE_DIR/$remote_manifest"
  local_target="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}-apply-manifest.json"
  ensure_artifacts_dir
  multipass transfer "$VM_NAME:$BOOTSTRAP_MANIFEST_REMOTE" "$local_target" >/dev/null 2>&1 || true
  if [[ -f "$local_target" ]]; then
    BOOTSTRAP_MANIFEST_LOCAL="$local_target"
  fi
}

run_core_cli_with_answers() {
  local subcommand="$1"
  local extra_args="$2"
  local answers="$3"
  local escaped_answers
  local wrapped_cmd
  escaped_answers=$(printf '%q' "$answers")
  wrapped_cmd="$(core_cli_command_in_vm "$subcommand" "$extra_args" "$escaped_answers")"
  if ! run_remote_command_with_status "$wrapped_cmd" 3600; then
    if [[ "${REMOTE_COMMAND_STATUS:-}" == "124" || -z "${REMOTE_COMMAND_STATUS:-}" ]]; then
      err "Timed out waiting for remote core CLI completion marker."
    else
      err "Remote core CLI command exited with status ${REMOTE_COMMAND_STATUS}."
    fi
    capture_bootstrap_manifest
    return 1
  fi
  capture_bootstrap_manifest
}

run_validate_with_retries() {
  local validate_mode="${1:-strict}"
  local timeout_secs="${2:-600}"
  local sleep_secs="${3:-15}"
  local validate_command
  local start_ts now_ts
  start_ts=$(date +%s)

  if [[ "$validate_mode" == "strict" ]]; then
    validate_command="cd '$REMOTE_DIR' && $(bootstrap_engine_env_prefix)./scripts/validate.sh --strict"
  else
    validate_command="cd '$REMOTE_DIR' && $(bootstrap_engine_env_prefix)./scripts/validate.sh"
  fi

  while true; do
    if run_remote_command_with_status "${validate_command}" 1200; then
      return 0
    fi

    now_ts=$(date +%s)
    if (( now_ts - start_ts >= timeout_secs )); then
      err "Validation did not converge within ${timeout_secs}s"
      return 1
    fi

    log "Validation is not clean yet; waiting ${sleep_secs}s before retrying"
    sleep "$sleep_secs"
  done
}

run_stack_validate_with_retries() {
  local stack_name="$1"
  local timeout_secs="${2:-900}"
  local sleep_secs="${3:-15}"
  local start_ts now_ts
  local validate_command
  start_ts=$(date +%s)
  validate_command="cd '$REMOTE_DIR' && $(bootstrap_engine_env_prefix)./productive-k3s-core.sh stack validate '${stack_name}' --strict"

  while true; do
    if run_remote_command_with_status "${validate_command}" 1200; then
      return 0
    fi

    now_ts=$(date +%s)
    if (( now_ts - start_ts >= timeout_secs )); then
      err "Stack validation for '${stack_name}' did not converge within ${timeout_secs}s"
      return 1
    fi

    log "Stack validation for '${stack_name}' is not clean yet; waiting ${sleep_secs}s before retrying"
    sleep "$sleep_secs"
  done
}

assert_in_vm() {
  local cmd="$1" description="$2"
  if run_in_vm "$cmd"; then
    log "Verified: $description"
  else
    err "Verification failed: $description"
    return 1
  fi
}

assert_in_vm_with_retries() {
  local cmd="$1" description="$2"
  local timeout_secs="${3:-300}"
  local sleep_secs="${4:-10}"
  local start_ts now_ts
  start_ts=$(date +%s)

  while true; do
    if run_in_vm "$cmd"; then
      log "Verified: $description"
      return 0
    fi

    now_ts=$(date +%s)
    if (( now_ts - start_ts >= timeout_secs )); then
      err "Verification failed: $description"
      return 1
    fi

    log "Rollback verification is not clean yet; waiting ${sleep_secs}s before retrying"
    sleep "$sleep_secs"
  done
}

smoke_answers() {
  printf '%s' $'y\ny\ny\n'
}

core_answers() {
  printf '%s' $'y\ny\ny\n'
}

full_answers() {
  cat <<'EOF'
y
y
y
y
home.arpa
2



y

admin





y
EOF
}

run_smoke() {
  log "Running smoke profile in VM"
  run_core_cli_with_answers "apply" "--dry-run" "$(smoke_answers)"
}

run_core() {
  log "Running core profile in VM"
  run_core_cli_with_answers "apply" "" "$(core_answers)"
  run_validate_with_retries non-strict 300 10
}

run_full() {
  log "Running full profile in VM"
  warn "This can take a while. It installs Longhorn, Rancher, Registry, cert-manager, and NFS inside the VM."
  local previous_auto_approve="${PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS:-}"
  if [[ -z "${PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS:-}" ]]; then
    export PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS=true
  fi
  run_core_cli_with_answers "apply" "" "$(core_answers)"
  run_core_cli_with_answers "stack install" "base" "$(full_answers)"
  if [[ -n "${previous_auto_approve}" ]]; then
    export PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS="${previous_auto_approve}"
  else
    unset PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS || true
  fi
  run_stack_validate_with_retries "base" 1200 15
}

run_full_clean() {
  run_full
  log "Running destructive clean profile inside the VM"
  run_in_vm "cd '$REMOTE_DIR' && $(bootstrap_engine_env_prefix)./productive-k3s-core.sh stack cleanup base --apply --yes --confirm-clean"
  assert_in_vm "if [[ '${PRODUCTIVE_K3S_DISTRO:-k3s}' == 'rke2' ]]; then systemctl is-active --quiet rke2-server && exit 1 || exit 0; else systemctl is-active --quiet k3s && exit 1 || exit 0; fi" "cluster service is no longer active after clean"
}

run_full_rollback() {
  local manifest
  run_full

  manifest="$(run_in_vm "cd '$REMOTE_DIR' && ls -1t runs/apply-*.json 2>/dev/null | head -1" | tr -d '\r')"
  if [[ -z "$manifest" ]]; then
    err "Could not determine the bootstrap manifest inside the VM."
    return 1
  fi

  log "Running rollback plan inside the VM"
  run_in_vm "cd '$REMOTE_DIR' && $(bootstrap_engine_env_prefix)./scripts/rollback.sh --to '$manifest' --plan"

  log "Applying rollback inside the VM"
  run_in_vm "cd '$REMOTE_DIR' && $(bootstrap_engine_env_prefix)./scripts/rollback.sh --to '$manifest' --apply --yes"

  assert_in_vm_with_retries "if [[ '${PRODUCTIVE_K3S_DISTRO:-k3s}' == 'rke2' ]]; then ! sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace cert-manager >/dev/null 2>&1; else ! sudo k3s kubectl get namespace cert-manager >/dev/null 2>&1; fi" "cert-manager namespace was removed by rollback" 600 15
  assert_in_vm_with_retries "if [[ '${PRODUCTIVE_K3S_DISTRO:-k3s}' == 'rke2' ]]; then ! sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace longhorn-system >/dev/null 2>&1; else ! sudo k3s kubectl get namespace longhorn-system >/dev/null 2>&1; fi" "longhorn-system namespace was removed by rollback" 600 15
  assert_in_vm_with_retries "if [[ '${PRODUCTIVE_K3S_DISTRO:-k3s}' == 'rke2' ]]; then ! sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace cattle-system >/dev/null 2>&1; else ! sudo k3s kubectl get namespace cattle-system >/dev/null 2>&1; fi" "cattle-system namespace was removed by rollback" 600 15
  assert_in_vm_with_retries "if [[ '${PRODUCTIVE_K3S_DISTRO:-k3s}' == 'rke2' ]]; then ! sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get namespace registry >/dev/null 2>&1; else ! sudo k3s kubectl get namespace registry >/dev/null 2>&1; fi" "registry namespace was removed by rollback" 600 15
  assert_in_vm_with_retries "if [[ '${PRODUCTIVE_K3S_DISTRO:-k3s}' == 'rke2' ]]; then ! sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get clusterissuer selfsigned >/dev/null 2>&1; else ! sudo k3s kubectl get clusterissuer selfsigned >/dev/null 2>&1; fi" "selfsigned ClusterIssuer was removed by rollback" 300 10
  assert_in_vm_with_retries "! grep -qE '^[[:space:]]*/srv/nfs/k8s-share[[:space:]]' /etc/exports" "NFS export was removed by rollback" 120 5
  assert_in_vm_with_retries "! grep -q 'rancher.home.arpa\\|registry.home.arpa' /etc/hosts" "apply-managed hosts entries were removed by rollback" 120 5
}

main() {
  parse_args "$@"
  need_cmd multipass || { err "multipass is required"; exit 1; }
  ADDONS_REPO_DIR="$(resolve_addons_repo_dir || true)"
  ensure_artifacts_dir
  trap cleanup EXIT

  launch_vm
  copy_repo

  case "$PROFILE" in
    smoke)
      run_smoke
      ;;
    core)
      run_core
      ;;
    full)
      run_full
      ;;
    full-clean)
      run_full_clean
      ;;
    full-rollback)
      run_full_rollback
      ;;
  esac

  ARTIFACT_STATUS="success"
  log "VM test completed successfully"
  log "Artifact written to: $ARTIFACT_PATH"
  log "Public artifact written to: $PUBLIC_ARTIFACT_PATH"
  if [[ -n "$BOOTSTRAP_MANIFEST_LOCAL" ]]; then
    log "Bootstrap manifest copied to: $BOOTSTRAP_MANIFEST_LOCAL"
  fi
  if [[ "$KEEP_VM" == "y" ]]; then
    log "VM preserved: $VM_NAME"
  fi
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
