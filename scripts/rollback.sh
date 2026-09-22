#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/runtime-contract.sh"
source "${SCRIPT_DIR}/addons-runtime.sh"

MODE="plan"
MANIFEST=""
AUTO_APPROVE="n"
PRODUCTIVE_K3S_DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-}"
PLAN_IDS=()
declare -A PLAN_DESCRIPTIONS=()
declare -A PLAN_APPLY_KIND=()

line() { printf '%s\n' "$*"; }
log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }
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

usage() {
  cat <<EOF
Usage: $0 --to runs/apply-...json [--plan|--apply] [--yes]

Generic rollback derives only engine-owned actions from the manifest. Stack or
add-on rollback is delegated to the selected stack's clean hooks when available.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --to) MANIFEST="${2:-}"; shift ;;
      --plan) MODE="plan" ;;
      --apply) MODE="apply" ;;
      --yes) AUTO_APPROVE="y" ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
    shift
  done
  [[ -n "$MANIFEST" ]] || { err "You must pass --to <manifest.json>."; usage; exit 1; }
}

require_prereqs() {
  need_cmd jq || { err "jq is required."; exit 1; }
  [[ -f "$MANIFEST" ]] || { err "Manifest not found: $MANIFEST"; exit 1; }
  local manifest_distro
  manifest_distro="$(jq -r '.settings.cluster_distro // empty' "$MANIFEST")"
  [[ -z "$manifest_distro" ]] || PRODUCTIVE_K3S_DISTRO="$manifest_distro"
  pk3s_runtime_validate_selection || { err "Manifest requested unsupported cluster distro/engine selection."; exit 1; }
}

manifest_string() {
  local jq_expr="$1"
  jq -r "$jq_expr // empty" "$MANIFEST"
}

component_field() {
  local component="$1" field="$2"
  jq -r --arg c "$component" --arg f "$field" '.components[$c][$f] // empty' "$MANIFEST"
}

add_plan_item() {
  local id="$1" description="$2" kind="$3"
  PLAN_IDS+=("$id")
  PLAN_DESCRIPTIONS["$id"]="$description"
  PLAN_APPLY_KIND["$id"]="$kind"
}

build_plan() {
  local status stack_planned stack_result runtime_detected runtime_planned runtime_result
  status="$(manifest_string '.status')"
  [[ "$status" == "success" ]] || warn "Manifest status is '${status}'. Rollback planning will be conservative."

  stack_planned="$(component_field stack_addons planned_action)"
  stack_result="$(component_field stack_addons result)"
  if [[ "$stack_planned" == "install" && "$stack_result" == "installed" && -n "${PRODUCTIVE_K3S_STACK_NAME}" ]]; then
    add_plan_item "stack_addons" "Run clean hooks for stack '${PRODUCTIVE_K3S_STACK_NAME}' add-ons" "stack_clean_hooks"
  fi

  runtime_detected="$(component_field cluster_runtime detected_before)"
  runtime_planned="$(component_field cluster_runtime planned_action)"
  runtime_result="$(component_field cluster_runtime result)"
  if [[ "$runtime_detected" == "missing" && "$runtime_planned" == "install" && "$runtime_result" == "installed" ]]; then
    add_plan_item "cluster_runtime_manual" "$(pk3s_runtime_cluster_label) was installed by this run. Runtime uninstall remains manual; use cleanup when that is intended." "manual"
  fi
}

print_plan() {
  log "Rollback plan for $(manifest_string '.run_id')"
  line "  Manifest: $MANIFEST"
  if (( ${#PLAN_IDS[@]} == 0 )); then
    line "  No rollback actions are safely derivable from this manifest."
    return
  fi
  local id
  for id in "${PLAN_IDS[@]}"; do
    line "  - ${PLAN_DESCRIPTIONS[$id]}"
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

apply_plan() {
  if (( ${#PLAN_IDS[@]} == 0 )); then
    log "Nothing to apply."
    return
  fi
  local confirm id
  if [[ "$AUTO_APPROVE" == "y" ]]; then
    confirm="y"
  else
    prompt_yesno confirm "n" "Apply rollback actions from this manifest?"
  fi
  [[ "$confirm" == "y" ]] || { warn "Rollback cancelled."; exit 0; }
  for id in "${PLAN_IDS[@]}"; do
    case "${PLAN_APPLY_KIND[$id]}" in
      stack_clean_hooks)
        run_stack_addon_clean_hooks
        ;;
      manual)
        warn "Manual follow-up: ${PLAN_DESCRIPTIONS[$id]}"
        ;;
      *)
        warn "Unknown rollback action kind for ${id}: ${PLAN_APPLY_KIND[$id]}"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  require_prereqs
  build_plan
  print_plan
  [[ "$MODE" == "apply" ]] && apply_plan
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
