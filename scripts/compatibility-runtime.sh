#!/usr/bin/env bash

pk3s_normalize_semver() {
  printf '%s\n' "${1#v}"
}

pk3s_semver_is_valid() {
  local version
  version="$(pk3s_normalize_semver "${1:-}")"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

pk3s_semver_gte() {
  local left right
  left="$(pk3s_normalize_semver "$1")"
  right="$(pk3s_normalize_semver "$2")"
  [[ "$(printf '%s\n%s\n' "${right}" "${left}" | sort -V | head -n1)" == "${right}" ]]
}

pk3s_semver_lt() {
  local left right
  left="$(pk3s_normalize_semver "$1")"
  right="$(pk3s_normalize_semver "$2")"
  [[ "${left}" != "${right}" ]] && [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | head -n1)" == "${left}" ]]
}

pk3s_compatibility_value() {
  local manifest="$1"
  local owner="$2"
  local key="$3"
  awk -v owner="${owner}" -v key="${key}" '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  compatibility:/ { in_compat=1; next }
    in_compat && /^    requires:/ { in_requires=1; next }
    in_requires && $0 == "      " owner ":" { in_owner=1; next }
    in_owner && $0 ~ "^        " key ":" { print; exit }
    in_owner && /^      [^[:space:]]/ { exit }
    in_compat && /^  [^[:space:]]/ { exit }
  ' "${manifest}"
}

pk3s_compatibility_distros() {
  local manifest="$1"
  awk '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  compatibility:/ { in_compat=1; next }
    in_compat && /^    requires:/ { in_requires=1; next }
    in_requires && /^      kubernetes:/ { in_kubernetes=1; next }
    in_kubernetes && /^        distros:/ { in_distros=1; next }
    in_distros && /^          - / {
      line=$0
      sub(/^          - /, "", line)
      print line
      next
    }
    in_distros { exit }
  ' "${manifest}"
}

pk3s_validate_core_compatibility() {
  local manifest="$1"
  local subject="$2"
  local artifact_version="$3"
  local running_version="$4"
  local contract min_version max_version distro distros allowed="n"

  contract="$(trim_yaml_value "$(pk3s_compatibility_value "${manifest}" core contract)")"
  min_version="$(trim_yaml_value "$(pk3s_compatibility_value "${manifest}" core minVersion)")"
  max_version="$(trim_yaml_value "$(pk3s_compatibility_value "${manifest}" core maxVersionExclusive)")"
  distros="$(pk3s_compatibility_distros "${manifest}" || true)"

  [[ "${contract}" == "artifact/v1" ]] || {
    printf '%s %s is incompatible: requires supported Core contract artifact/v1; declared %s\n' \
      "${subject}" "${artifact_version}" "${contract:-missing}" >&2
    return 4
  }
  if ! pk3s_semver_is_valid "${min_version}" || ! pk3s_semver_is_valid "${max_version}" || ! pk3s_semver_lt "${min_version}" "${max_version}"; then
    printf '%s %s is incompatible: invalid Core version window [%s, %s)\n' \
      "${subject}" "${artifact_version}" "${min_version:-missing}" "${max_version:-missing}" >&2
    return 4
  fi
  if ! pk3s_semver_is_valid "${running_version}"; then
    printf '%s %s is incompatible: running Core version is not comparable: %s\n' \
      "${subject}" "${artifact_version}" "${running_version:-unknown}" >&2
    return 4
  fi
  if ! pk3s_semver_gte "${running_version}" "${min_version}" || ! pk3s_semver_lt "${running_version}" "${max_version}"; then
    printf '%s %s is incompatible: requires Core >=%s and <%s; running Core %s\n' \
      "${subject}" "${artifact_version}" "${min_version}" "${max_version}" "${running_version}" >&2
    printf 'upgrade Core or select an older compatible artifact version\n' >&2
    return 4
  fi
  [[ -n "${distros}" ]] || {
    printf '%s %s is incompatible: spec.compatibility.requires.kubernetes.distros is required\n' \
      "${subject}" "${artifact_version}" >&2
    return 4
  }
  distro="${PRODUCTIVE_K3S_DISTRO:-k3s}"
  while IFS= read -r candidate; do
    case "${candidate}" in
      k3s|rke2) ;;
      *)
        printf '%s %s is incompatible: unsupported Kubernetes distro declaration %s\n' \
          "${subject}" "${artifact_version}" "${candidate}" >&2
        return 4
        ;;
    esac
    [[ "${candidate}" == "${distro}" ]] && allowed="y"
  done <<< "${distros}"
  [[ "${allowed}" == "y" ]] || {
    printf '%s %s is incompatible: Kubernetes distro %s is not in the declared compatibility set\n' \
      "${subject}" "${artifact_version}" "${distro}" >&2
    return 4
  }
}
