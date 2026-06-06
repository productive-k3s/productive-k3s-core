#!/usr/bin/env bash

resolve_addons_repo_dir() {
  if [[ -n "${PRODUCTIVE_K3S_ADDONS_REPO_DIR:-}" && -d "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}/addons" ]]; then
    printf '%s\n' "${PRODUCTIVE_K3S_ADDONS_REPO_DIR}"
    return 0
  fi

  local sibling_dir
  sibling_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)/productive-k3s-addons"
  if [[ -d "${sibling_dir}/addons" ]]; then
    printf '%s\n' "${sibling_dir}"
    return 0
  fi

  return 1
}

resolve_addon_source_dir() {
  local addon_name="$1"
  local repo_dir
  repo_dir="$(resolve_addons_repo_dir)" || return 1
  [[ -d "${repo_dir}/addons/${addon_name}" ]] || return 1
  printf '%s\n' "${repo_dir}/addons/${addon_name}"
}

resolve_stack_source_dir() {
  local stack_name="$1"
  local repo_dir
  repo_dir="$(resolve_addons_repo_dir)" || return 1
  [[ -d "${repo_dir}/stacks/${stack_name}" ]] || return 1
  printf '%s\n' "${repo_dir}/stacks/${stack_name}"
}

resolve_stack_source_manifest() {
  local stack_name="$1"
  local stack_dir manifest
  stack_dir="$(resolve_stack_source_dir "${stack_name}")" || return 1
  manifest="$(find "${stack_dir}" -type f -name 'stack.yaml' | head -n1)"
  [[ -n "${manifest}" ]] || return 1
  printf '%s\n' "${manifest}"
}

stack_source_addon_names() {
  local stack_name="$1"
  local manifest
  manifest="$(resolve_stack_source_manifest "${stack_name}")" || return 1
  awk '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  addons:/ { in_addons=1; next }
    in_addons && /^    - / { sub(/^    - /, "", $0); print; next }
    in_addons && !/^    - / { exit }
  ' "${manifest}"
}

addon_component_key() {
  printf '%s\n' "${1//-/_}"
}

addon_source_script_exists() {
  local addon_name="$1"
  local script_name="$2"
  local addon_dir
  addon_dir="$(resolve_addon_source_dir "${addon_name}")" || return 1
  [[ -f "${addon_dir}/scripts/${script_name}" ]]
}

run_addon_source_script() {
  local addon_name="$1"
  local script_name="$2"
  shift 2
  local addon_dir script_path
  addon_dir="$(resolve_addon_source_dir "${addon_name}")" || return 1
  script_path="${addon_dir}/scripts/${script_name}"
  [[ -f "${script_path}" ]] || return 1
  (
    cd "${addon_dir}"
    bash "${script_path}" "$@"
  )
}

source_addon_source_script() {
  local addon_name="$1"
  local script_name="$2"
  local addon_dir script_path
  addon_dir="$(resolve_addon_source_dir "${addon_name}")" || return 1
  script_path="${addon_dir}/scripts/${script_name}"
  [[ -f "${script_path}" ]] || return 1
  # shellcheck disable=SC1090
  source "${script_path}"
}

run_addon_source_hook() {
  local addon_name="$1"
  local script_name="$2"
  local function_name="$3"
  shift 3

  source_addon_source_script "${addon_name}" "${script_name}" || return 1
  if ! declare -F "${function_name}" >/dev/null 2>&1; then
    return 2
  fi
  "${function_name}" "$@"
}
