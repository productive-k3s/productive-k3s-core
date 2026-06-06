#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS_DIR="${REPO_DIR}/test-artifacts"

PROFILE=""
declare -a EXPECTED=()

usage() {
  cat <<'EOF'
Usage:
  ./tests/check-test-artifacts.sh --profile <profile> --expect <platform>|<image> [--expect <platform>|<image> ...]

Example:
  ./tests/check-test-artifacts.sh \
    --profile smoke \
    --expect 'ubuntu|24.04' \
    --expect 'ubuntu|22.04' \
    --expect 'debian12|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2' \
    --expect 'debian13|https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2'
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
  find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name "test-in-vm-*.json" ! -name "*-apply-manifest.json" ! -name "*-public.json" -print0 \
    | xargs -0 -r jq -r --arg profile "$PROFILE" 'select(.profile == $profile) | input_filename' \
    | sort
}

collect_manifests() {
  find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name "test-in-vm-*.json" ! -name "*-apply-manifest.json" ! -name "*-public.json" -print0 \
    | xargs -0 -r jq -r --arg profile "$PROFILE" 'select(.profile == $profile) | input_filename' \
    | sed 's/\.json$/-apply-manifest.json/' \
    | sort
}

main() {
  need_cmd jq
  parse_args "$@"

  mapfile -t artifacts < <(collect_artifacts)
  mapfile -t manifests < <(collect_manifests)
  if (( ${#artifacts[@]} != ${#EXPECTED[@]} )); then
    echo "[ERROR] Expected ${#EXPECTED[@]} artifact(s) for profile '${PROFILE}', found ${#artifacts[@]}" >&2
    printf '  %s\n' "${artifacts[@]}" >&2 || true
    exit 1
  fi
  if (( ${#manifests[@]} != ${#EXPECTED[@]} )); then
    echo "[ERROR] Expected ${#EXPECTED[@]} bootstrap manifest artifact(s) for profile '${PROFILE}', found ${#manifests[@]}" >&2
    printf '  %s\n' "${manifests[@]}" >&2 || true
    exit 1
  fi

  local expected platform image matched artifact manifest status artifact_profile artifact_platform artifact_image manifest_status manifest_path artifact_basename
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
        echo "[INFO] Verified artifact and bootstrap manifest success for ${platform} ${image}"
        matched="y"
        break
      fi
    done

    if [[ "$matched" != "y" ]]; then
      echo "[ERROR] Missing expected successful artifact/manifest pair for platform='${platform}' image='${image}' profile='${PROFILE}'" >&2
      printf '  %s\n' "${artifacts[@]}" >&2
      printf '  %s\n' "${manifests[@]}" >&2
      exit 1
    fi
  done

  echo "[INFO] Artifact and bootstrap manifest validation passed for profile '${PROFILE}'"
}

main "$@"
