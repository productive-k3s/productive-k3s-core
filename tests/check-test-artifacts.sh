#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${TEST_ARTIFACTS_DIR:-${REPO_DIR}/test-artifacts}"
VM_IMAGES_ENV="${SCRIPT_DIR}/vm-images.env"

PROFILE=""
declare -a EXPECTED=()

# shellcheck disable=SC1090
source "${VM_IMAGES_ENV}"

usage() {
  cat <<'EOF'
Usage:
  ./tests/check-test-artifacts.sh --profile <profile> --expect <platform>|<image> [--expect <platform>|<image> ...]

Example:
  ./tests/check-test-artifacts.sh \
    --profile smoke \
    --expect "ubuntu|${UBUNTU_24_04_IMAGE}" \
    --expect "ubuntu|${UBUNTU_22_04_IMAGE}" \
    --expect "debian12|${DEBIAN_12_IMAGE}" \
    --expect "debian13|${DEBIAN_13_IMAGE}"
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1" >&2
    exit 1
  }
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --profile)
        PROFILE="${2:-}"
        shift
        ;;
      --expect)
        EXPECTED+=("${2:-}")
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "[ERROR] Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done

  if [[ -z "$PROFILE" ]]; then
    echo "[ERROR] Missing --profile" >&2
    usage
    exit 1
  fi

  if (( ${#EXPECTED[@]} == 0 )); then
    echo "[ERROR] At least one --expect entry is required" >&2
    usage
    exit 1
  fi
}

collect_artifacts() {
  [[ -d "$ARTIFACTS_DIR" ]] || return 0
  local artifact artifact_profile artifact_platform artifact_image artifact_key artifact_mtime
  declare -A latest_path=()
  declare -A latest_mtime=()

  while IFS= read -r -d '' artifact; do
    artifact_profile="$(jq -r '.profile // empty' "$artifact")"
    [[ "$artifact_profile" == "$PROFILE" ]] || continue
    artifact_platform="$(jq -r '.platform // "unknown"' "$artifact")"
    artifact_image="$(jq -r '.image // "unknown"' "$artifact")"
    artifact_key="${artifact_platform}|${artifact_image}"
    artifact_mtime="$(stat -c '%Y' "$artifact")"
    if [[ -z "${latest_mtime[$artifact_key]:-}" || "$artifact_mtime" -ge "${latest_mtime[$artifact_key]}" ]]; then
      latest_mtime["$artifact_key"]="$artifact_mtime"
      latest_path["$artifact_key"]="$artifact"
    fi
  done < <(find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name "test-in-vm-*.json" ! -name "*-apply-manifest.json" ! -name "*-public.json" -print0)

  local key
  for key in "${!latest_path[@]}"; do
    printf '%s\n' "${latest_path[$key]}"
  done | sort
}

main() {
  need_cmd jq
  parse_args "$@"

  mapfile -t artifacts < <(collect_artifacts)
  if (( ${#artifacts[@]} != ${#EXPECTED[@]} )); then
    echo "[ERROR] Expected ${#EXPECTED[@]} artifact(s) for profile '${PROFILE}', found ${#artifacts[@]}" >&2
    printf '  %s\n' "${artifacts[@]}" >&2 || true
    exit 1
  fi

  local expected platform image matched artifact manifest status artifact_profile artifact_platform artifact_image manifest_status manifest_path artifact_basename bootstrap_manifest_local
  for expected in "${EXPECTED[@]}"; do
    platform="${expected%%|*}"
    image="${expected#*|}"
    matched="n"

    for artifact in "${artifacts[@]}"; do
      artifact_profile="$(jq -r '.profile' "$artifact")"
      artifact_platform="$(jq -r '.platform' "$artifact")"
      artifact_image="$(jq -r '.image' "$artifact")"
      status="$(jq -r '.status' "$artifact")"

      if [[ "$artifact_profile" == "$PROFILE" && "$artifact_platform" == "$platform" && "$artifact_image" == "$image" ]]; then
        if [[ "$status" != "success" ]]; then
          echo "[ERROR] Artifact did not succeed: $artifact" >&2
          jq '{status,profile,platform,image,vm_name}' "$artifact" >&2
          exit 1
        fi
        bootstrap_manifest_local="$(jq -r '.bootstrap_manifest_local // empty' "$artifact")"
        if [[ -n "$bootstrap_manifest_local" ]]; then
          artifact_basename="${artifact%.json}"
          manifest_path="${artifact_basename}-apply-manifest.json"
          if [[ ! -f "$manifest_path" ]]; then
            echo "[ERROR] Missing bootstrap manifest paired with artifact: $artifact" >&2
            exit 1
          fi
          manifest_status="$(jq -r '.status' "$manifest_path")"
          if [[ "$manifest_status" != "success" ]]; then
            echo "[ERROR] Bootstrap manifest did not succeed: $manifest_path" >&2
            jq '{status,run_id,mode,exit_code,current_step}' "$manifest_path" >&2
            exit 1
          fi
        fi
        echo "[INFO] Verified artifact and bootstrap manifest success for ${platform} ${image}"
        matched="y"
        break
      fi
    done

    if [[ "$matched" != "y" ]]; then
      echo "[ERROR] Missing expected successful artifact for platform='${platform}' image='${image}' profile='${PROFILE}'" >&2
      printf '  %s\n' "${artifacts[@]}" >&2
      exit 1
    fi
  done

  echo "[INFO] Artifact and bootstrap manifest validation passed for profile '${PROFILE}'"
}

main "$@"
