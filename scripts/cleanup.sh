#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime-contract.sh"
source "${SCRIPT_DIR}/addons-runtime.sh"

PRODUCTIVE_K3S_DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-}"
MODE="plan"
AUTO_APPROVE="n"
FORCE_CONFIRM="n"
SUDO_KA_PID=""
PLAN_ITEMS=()

line() { printf '%s\n' "$*"; }
log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }
can_use_tty() { [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]; }

prompt_yesno() {
  local var="$1" default="$2" msg="$3" val
  if can_use_tty; then
    printf '%s [%s] (y/n): ' "$msg" "$default" > /dev/tty
    IFS= read -r val < /dev/tty
  else
    printf '%s [%s] (y/n): ' "$msg" "$default"
    IFS= read -r val
  fi
  val="${val:-$default}"
  case "$val" in
    y|Y) printf -v "$var" 'y' ;;
    n|N) printf -v "$var" 'n' ;;
    *) printf -v "$var" '%s' "$default" ;;
  esac
}

prompt_text() {
  local var="$1" msg="$2" val
  if can_use_tty; then
    printf '%s: ' "$msg" > /dev/tty
    IFS= read -r val < /dev/tty
  else
    printf '%s: ' "$msg"
    IFS= read -r val
  fi
  printf -v "$var" '%s' "$val"
}

sudo_keepalive() {
  if ! sudo -n true 2>/dev/null; then
    log "Requesting sudo..."
    sudo -v
  fi
  ( while true; do sudo -n true; sleep 30; done ) </dev/null >/dev/null 2>&1 &
  SUDO_KA_PID=$!
}

cleanup_exit() {
  if [[ -n "${SUDO_KA_PID:-}" ]]; then
    kill "${SUDO_KA_PID}" >/dev/null 2>&1 || true
  fi
}

usage() {
  cat <<EOF
Usage: $0 [--plan|--apply] [--yes] [--confirm-clean]

Generic cleanup removes the local cluster runtime. When PRODUCTIVE_K3S_STACK_NAME
is set, stack add-on cleanup is delegated to each add-on clean hook first.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --plan) MODE="plan" ;;
      --apply) MODE="apply" ;;
      --yes) AUTO_APPROVE="y" ;;
      --confirm-clean) FORCE_CONFIRM="y" ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

add_plan_item() {
  PLAN_ITEMS+=("$1")
}

build_plan() {
  if [[ -n "${PRODUCTIVE_K3S_STACK_NAME}" ]]; then
    add_plan_item "Run clean hooks for stack '${PRODUCTIVE_K3S_STACK_NAME}' add-ons when provided"
  fi
  add_plan_item "Uninstall $(pk3s_runtime_cluster_label) and remove local runtime state directories"
}

print_plan() {
  log "Clean plan"
  local item
  for item in "${PLAN_ITEMS[@]}"; do
    line "  - ${item}"
  done
}

run_stack_addon_clean_hooks() {
  local addon_name addon_dir clean_fn
  [[ -n "${PRODUCTIVE_K3S_STACK_NAME}" ]] || return 0
  if ! stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    err "Stack source '${PRODUCTIVE_K3S_STACK_NAME}' was not found."
    exit 1
  fi
  while IFS= read -r addon_name; do
    [[ -n "${addon_name}" ]] || continue
    if ! addon_source_script_exists "${addon_name}" clean.sh; then
      warn "Add-on '${addon_name}' does not provide scripts/clean.sh; skipping."
      continue
    fi
    addon_dir="$(resolve_addon_source_dir "${addon_name}")"
    # shellcheck source=/dev/null
    source "${addon_dir}/scripts/clean.sh"
    clean_fn="pk3s_addon_clean"
    if ! declare -F "${clean_fn}" >/dev/null 2>&1; then
      err "Add-on '${addon_name}' clean hook '${clean_fn}' is missing"
      exit 1
    fi
    "${clean_fn}"
  done < <(stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}")
}

runtime_mount_points() {
  awk '{print $5}' /proc/self/mountinfo | sort -r
}

unmount_runtime_state_dirs() {
  local runtime_path mount_path
  local -a runtime_paths=()
  mapfile -t runtime_paths < <(pk3s_runtime_state_dirs)
  while IFS= read -r mount_path; do
    [[ -n "${mount_path}" ]] || continue
    for runtime_path in "${runtime_paths[@]}"; do
      [[ -n "${runtime_path}" ]] || continue
      if [[ "${mount_path}" == "${runtime_path}" || "${mount_path}" == "${runtime_path}/"* ]]; then
        sudo umount "${mount_path}" >/dev/null 2>&1 || sudo umount -l "${mount_path}" >/dev/null 2>&1 || true
        break
      fi
    done
  done < <(runtime_mount_points)
}

stop_runtime_services() {
  local service_name
  for service_name in "$(pk3s_runtime_server_service)" "$(pk3s_runtime_agent_service)"; do
    [[ -n "${service_name}" ]] || continue
    sudo systemctl stop "${service_name}" >/dev/null 2>&1 || true
    sudo systemctl disable "${service_name}" >/dev/null 2>&1 || true
  done
}

uninstall_runtime() {
  local uninstall_script killall_script runtime_path
  stop_runtime_services
  killall_script="$(pk3s_runtime_killall_script_path)"
  uninstall_script="$(pk3s_runtime_uninstall_script_path)"
  [[ -x "${killall_script}" ]] && sudo "${killall_script}" || true
  [[ -x "${uninstall_script}" ]] && sudo "${uninstall_script}" || true
  unmount_runtime_state_dirs
  while IFS= read -r runtime_path; do
    [[ -n "${runtime_path}" ]] || continue
    sudo rm -rf "${runtime_path}"
  done < <(pk3s_runtime_state_dirs)
  sudo systemctl daemon-reload >/dev/null 2>&1 || true
  sudo systemctl reset-failed >/dev/null 2>&1 || true
}

apply_cleanup() {
  local confirm typed
  if [[ "$AUTO_APPROVE" == "y" ]]; then
    confirm="y"
  else
    prompt_yesno confirm "n" "Apply cleanup?"
  fi
  [[ "$confirm" == "y" ]] || { warn "Cleanup cancelled."; exit 0; }
  if [[ "$FORCE_CONFIRM" == "y" ]]; then
    typed="CLEAN"
  else
    prompt_text typed "Type CLEAN to continue"
  fi
  [[ "$typed" == "CLEAN" ]] || { warn "Cleanup cancelled because confirmation text did not match."; exit 0; }
  sudo_keepalive
  run_stack_addon_clean_hooks
  uninstall_runtime
  log "Cleanup completed"
}

main() {
  parse_args "$@"
  pk3s_runtime_validate_selection || { err "Unsupported cluster distro/engine selection."; exit 1; }
  trap cleanup_exit EXIT
  build_plan
  print_plan
  if [[ "$MODE" == "apply" ]]; then
    apply_cleanup
  fi
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
