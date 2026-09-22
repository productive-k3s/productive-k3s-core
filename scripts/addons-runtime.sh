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

parse_stack_addon_records_from_manifest() {
  local manifest="$1"
  local line item key value in_spec=0 in_addons=0 in_record=0
  local current_name="" current_version="" current_source=""

  __pk3s_flush_stack_addon_record() {
    [[ "${in_record}" == "1" ]] || return 0
    if [[ -n "${current_name}" || -n "${current_version}" || -n "${current_source}" ]]; then
      printf 'name=%s\tversion=%s\tsource=%s\n' "${current_name}" "${current_version}" "${current_source}"
    fi
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == "spec:" ]]; then
      in_spec=1
      continue
    fi
    if [[ "${in_spec}" == "1" && "${line}" == "  addons:" ]]; then
      in_addons=1
      continue
    fi
    if [[ "${in_addons}" == "1" && "${line}" == "  "* && "${line}" != "    "* ]]; then
      break
    fi
    [[ "${in_addons}" == "1" ]] || continue

    if [[ "${line}" == "    - "* ]]; then
      __pk3s_flush_stack_addon_record
      item="${line#    - }"
      current_name=""
      current_version=""
      current_source=""
      in_record=1
      if [[ "${item}" == name:* ]]; then
        current_name="${item#name:}"
        current_name="${current_name# }"
      elif [[ "${item}" != *:* ]]; then
        current_name="${item}"
      fi
      continue
    fi

    if [[ "${in_record}" == "1" && "${line}" == "      "* ]]; then
      item="${line#      }"
      key="${item%%:*}"
      value="${item#*:}"
      value="${value# }"
      case "${key}" in
        name) current_name="${value}" ;;
        version) current_version="${value}" ;;
        source) current_source="${value}" ;;
      esac
      continue
    fi

    if [[ "${in_record}" == "1" ]]; then
      __pk3s_flush_stack_addon_record
      in_record=0
    fi
  done < "${manifest}"

  __pk3s_flush_stack_addon_record
  unset -f __pk3s_flush_stack_addon_record
}

stack_source_addon_records() {
  local stack_name="$1"
  local manifest
  manifest="$(resolve_stack_source_manifest "${stack_name}")" || return 1
  parse_stack_addon_records_from_manifest "${manifest}"
}

stack_addon_record_value() {
  local record="$1"
  local key="$2"
  local field
  while IFS= read -r field; do
    if [[ "${field}" == "${key}="* ]]; then
      printf '%s\n' "${field#${key}=}"
      return 0
    fi
  done < <(printf '%s\n' "${record}" | tr '\t' '\n')
  return 1
}

stack_source_addon_names() {
  local stack_name="$1"
  local addon_record addon_name addon_records
  addon_records="$(stack_source_addon_records "${stack_name}")" || return 1
  while IFS= read -r addon_record; do
    addon_name="$(stack_addon_record_value "${addon_record}" "name" || true)"
    [[ -n "${addon_name}" ]] || continue
    printf '%s\n' "${addon_name}"
  done <<< "${addon_records}"
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
