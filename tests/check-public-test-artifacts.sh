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
  ./tests/check-public-test-artifacts.sh --profile <profile> --expect <platform>|<image> [--expect <platform>|<image> ...]
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1" >&2
    exit 1
  }
}

search_file() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n -- "${pattern}" "${file}" >/dev/null
  else
    grep -En -- "${pattern}" "${file}" >/dev/null
  fi
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

collect_public_artifacts() {
  find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name "test-in-vm-*-public.json" -print0 \
    | xargs -0 -r jq -r --arg profile "$PROFILE" 'select(.profile == $profile) | input_filename' \
    | sort
}

assert_public_privacy() {
  local artifact="$1"

  if jq -e '
    has("vm_name")
    or has("remote_user")
    or has("remote_dir")
    or has("repo_dir")
    or has("bootstrap_manifest_remote")
    or has("bootstrap_manifest_local")
  ' "$artifact" >/dev/null; then
    echo "[ERROR] Public artifact contains forbidden keys: $artifact" >&2
    jq '.' "$artifact" >&2
    exit 1
  fi

  if search_file '/home/|/tmp/|/var/|/srv/|productive-k3s-core-test-|bootstrap-[0-9]{8}-[0-9]{6}.*\.json|jmacchi|ubuntu@|debian@' "$artifact"; then
    echo "[ERROR] Public artifact contains path-like or host-specific content: $artifact" >&2
    cat "$artifact" >&2
    exit 1
  fi
}

main() {
  need_cmd jq
  parse_args "$@"

  mapfile -t artifacts < <(collect_public_artifacts)
  if (( ${#artifacts[@]} != ${#EXPECTED[@]} )); then
    echo "[ERROR] Expected ${#EXPECTED[@]} public artifact(s) for profile '${PROFILE}', found ${#artifacts[@]}" >&2
    printf '  %s\n' "${artifacts[@]}" >&2 || true
    exit 1
  fi

  local expected platform image matched artifact artifact_profile artifact_platform artifact_image status scope
  for expected in "${EXPECTED[@]}"; do
    platform="${expected%%|*}"
    image="${expected#*|}"
    matched="n"

    for artifact in "${artifacts[@]}"; do
      artifact_profile="$(jq -r '.profile' "$artifact")"
      artifact_platform="$(jq -r '.platform' "$artifact")"
      artifact_image="$(jq -r '.image' "$artifact")"
      status="$(jq -r '.status' "$artifact")"
      scope="$(jq -r '.artifact_scope // empty' "$artifact")"

      if [[ "$artifact_profile" == "$PROFILE" && "$artifact_platform" == "$platform" && "$artifact_image" == "$image" ]]; then
        if [[ "$status" != "success" ]]; then
          echo "[ERROR] Public artifact did not succeed: $artifact" >&2
          jq '{status,profile,platform,image}' "$artifact" >&2
          exit 1
        fi
        if [[ "$scope" != "public" ]]; then
          echo "[ERROR] Public artifact scope is invalid: $artifact" >&2
          jq '{artifact_scope,profile,platform,image}' "$artifact" >&2
          exit 1
        fi
        assert_public_privacy "$artifact"
        echo "[INFO] Verified public artifact privacy for ${platform} ${image}"
        matched="y"
        break
      fi
    done

    if [[ "$matched" != "y" ]]; then
      echo "[ERROR] Missing expected successful public artifact for platform='${platform}' image='${image}' profile='${PROFILE}'" >&2
      printf '  %s\n' "${artifacts[@]}" >&2
      exit 1
    fi
  done

  echo "[INFO] Public artifact privacy validation passed for profile '${PROFILE}'"
}

main "$@"
