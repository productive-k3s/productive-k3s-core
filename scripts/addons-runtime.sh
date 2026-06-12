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

stack_source_addon_records() {
  local stack_name="$1"
  local manifest
  manifest="$(resolve_stack_source_manifest "${stack_name}")" || return 1
  awk '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  addons:/ { in_addons=1; next }
    in_addons && /^  / && !/^    / { exit }
    !in_addons { next }
    /^    - / {
      flush_record()
      line=$0
      sub(/^    - /, "", line)
      current_name=""
      current_version=""
      current_source=""
      if (line ~ /^name:[[:space:]]*/) {
        sub(/^name:[[:space:]]*/, "", line)
        current_name=line
      } else if (line !~ /:/) {
        current_name=line
      }
      in_record=1
      next
    }
    in_record && /^      / {
      line=$0
      sub(/^      /, "", line)
      if (line ~ /^name:[[:space:]]*/) {
        sub(/^name:[[:space:]]*/, "", line)
        current_name=line
      } else if (line ~ /^version:[[:space:]]*/) {
        sub(/^version:[[:space:]]*/, "", line)
        current_version=line
      } else if (line ~ /^source:[[:space:]]*/) {
        sub(/^source:[[:space:]]*/, "", line)
        current_source=line
      }
      next
    }
    in_record { flush_record(); in_record=0 }
    END { flush_record() }
    function flush_record() {
      if (!in_record) {
        return
      }
      if (current_name != "" || current_version != "" || current_source != "") {
        printf "name=%s\tversion=%s\tsource=%s\n", current_name, current_version, current_source
      }
    }
  ' "${manifest}"
}

stack_source_addon_names() {
  local stack_name="$1"
  stack_source_addon_records "${stack_name}" | awk -F '\t' '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^name=/) {
          sub(/^name=/, "", $i)
          print $i
          break
        }
      }
    }
  '
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

resolve_addon_source_manifest() {
  local addon_name="$1"
  local addon_dir manifest
  addon_dir="$(resolve_addon_source_dir "${addon_name}")" || return 1
  manifest="$(find "${addon_dir}" -type f -name 'addon.yaml' | head -n1)"
  [[ -n "${manifest}" ]] || return 1
  printf '%s\n' "${manifest}"
}

addon_source_impact_value() {
  local addon_name="$1"
  local field_name="$2"
  local manifest
  manifest="$(resolve_addon_source_manifest "${addon_name}")" || return 1
  awk -v field="${field_name}" '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  impact:/ { in_impact=1; next }
    in_impact && $0 ~ ("^    " field ":") { sub("^    " field ":[[:space:]]*", "", $0); print; exit }
    in_impact && /^[^ ]/ { exit }
  ' "${manifest}"
}

addon_source_host_capabilities() {
  local addon_name="$1"
  local manifest
  manifest="$(resolve_addon_source_manifest "${addon_name}")" || return 1
  awk '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  impact:/ { in_impact=1; next }
    in_impact && /^    hostCapabilities:/ { in_caps=1; next }
    in_caps && /^      - / { sub(/^      - /, "", $0); print; next }
    in_caps && !/^      - / { exit }
    in_impact && /^[^ ]/ { exit }
  ' "${manifest}"
}
