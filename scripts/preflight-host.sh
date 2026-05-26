#!/usr/bin/env bash
set -uo pipefail

STRICT=0
JSON_OUTPUT=0
MODE="single-node"
FAILURES=0
WARNINGS=0
CHECK_RESULTS=()
OS_ID="unknown"
OS_VERSION_ID="unknown"
OS_CODENAME="unknown"
OS_PRETTY_NAME="unknown"
PLATFORM_SUPPORT="unsupported"
ARCHITECTURE="unknown"
ARCHITECTURE_SUPPORT="unsupported"
CPU_COUNT=0
MEMTOTAL_KB=0
DISK_AVAILABLE_BYTES=0

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

append_result() {
  local level="$1" check="$2" message="$3"
  CHECK_RESULTS+=("{\"level\":\"$(json_escape "$level")\",\"check\":\"$(json_escape "$check")\",\"message\":\"$(json_escape "$message")\"}")
}

ok() {
  append_result "ok" "$1" "$2"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\033[1;32m[OK]\033[0m %s\n" "$2"
  fi
}

warn() {
  append_result "warn" "$1" "$2"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\033[1;33m[WARN]\033[0m %s\n" "$2"
  fi
}

fail() {
  append_result "fail" "$1" "$2"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\033[1;31m[FAIL]\033[0m %s\n" "$2"
  fi
}

info() {
  append_result "info" "$1" "$2"
  if [[ "$JSON_OUTPUT" == "0" ]]; then
    printf "\n\033[1;34m[INFO]\033[0m %s\n" "$2"
  fi
}

record_ok() {
  ok "$1" "$2"
}

record_warn() {
  WARNINGS=$((WARNINGS + 1))
  warn "$1" "$2"
}

record_fail() {
  FAILURES=$((FAILURES + 1))
  fail "$1" "$2"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

read_os_release() {
  local os_release_file="${PRODUCTIVE_K3S_PREFLIGHT_OS_RELEASE_FILE:-/etc/os-release}"
  if [[ -r "$os_release_file" ]]; then
    # shellcheck disable=SC1090
    . "$os_release_file"
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    OS_CODENAME="${VERSION_CODENAME:-unknown}"
    OS_PRETTY_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
  fi
}

detect_platform_support() {
  read_os_release

  case "$OS_ID:$OS_VERSION_ID" in
    ubuntu:22.04|ubuntu:24.04|debian:12|debian:13)
      PLATFORM_SUPPORT="supported"
      ;;
    *)
      PLATFORM_SUPPORT="unsupported"
      ;;
  esac
}

read_architecture() {
  if [[ -n "${PRODUCTIVE_K3S_PREFLIGHT_ARCH:-}" ]]; then
    printf '%s' "${PRODUCTIVE_K3S_PREFLIGHT_ARCH}"
    return
  fi

  uname -m 2>/dev/null || printf 'unknown'
}

detect_architecture_support() {
  ARCHITECTURE="$(read_architecture)"

  case "$ARCHITECTURE" in
    x86_64|amd64|aarch64|arm64)
      ARCHITECTURE_SUPPORT="supported"
      ;;
    *)
      ARCHITECTURE_SUPPORT="unsupported"
      ;;
  esac
}

read_pid1_comm() {
  local pid1_comm_file="${PRODUCTIVE_K3S_PREFLIGHT_PID1_COMM_FILE:-/proc/1/comm}"
  if [[ -r "$pid1_comm_file" ]]; then
    tr -d '\n' < "$pid1_comm_file"
  else
    printf 'unknown'
  fi
}

read_cpu_count() {
  if [[ -n "${PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT:-}" ]]; then
    printf '%s' "${PRODUCTIVE_K3S_PREFLIGHT_CPU_COUNT}"
    return
  fi
  getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || printf '0'
}

read_memtotal_kb() {
  if [[ -n "${PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB:-}" ]]; then
    printf '%s' "${PRODUCTIVE_K3S_PREFLIGHT_MEMTOTAL_KB}"
    return
  fi

  local meminfo_file="${PRODUCTIVE_K3S_PREFLIGHT_MEMINFO_FILE:-/proc/meminfo}"
  awk '/MemTotal:/ {print $2; exit}' "$meminfo_file" 2>/dev/null || printf '0'
}

read_disk_available_bytes() {
  if [[ -n "${PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES:-}" ]]; then
    printf '%s' "${PRODUCTIVE_K3S_PREFLIGHT_DISK_AVAILABLE_BYTES}"
    return
  fi

  df -B1 / 2>/dev/null | awk 'NR==2 {print $4; exit}' || printf '0'
}

bytes_to_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.1f", (bytes / 1024 / 1024 / 1024) }'
}

kb_to_gib() {
  awk -v kb="$1" 'BEGIN { printf "%.1f", (kb / 1024 / 1024) }'
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --mode)
        MODE="${2:-}"
        shift
        ;;
      --strict)
        STRICT=1
        ;;
      --json-output)
        JSON_OUTPUT=1
        ;;
      -h|--help)
        cat <<EOF
Usage: $0 [--mode <single-node|server|agent|stack>] [--strict] [--json-output]

  --mode <single-node|server|agent|stack>
                 Select the host profile to evaluate
  --strict       Exit non-zero on warnings as well as failures
  --json-output  Emit machine-readable JSON instead of human-readable output
  -h, --help     Show CLI help
EOF
        exit 0
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done

  case "$MODE" in
    single-node|server|agent|stack)
      ;;
    *)
      printf 'Unsupported mode: %s\n' "$MODE" >&2
      exit 1
      ;;
  esac
}

check_platform() {
  info "platform" "Checking supported platform"
  detect_platform_support
  if [[ "$PLATFORM_SUPPORT" == "supported" ]]; then
    record_ok "platform" "supported platform detected: ${OS_PRETTY_NAME}"
  else
    record_fail "platform" "unsupported platform detected: ${OS_PRETTY_NAME} (${OS_ID} ${OS_VERSION_ID})"
  fi
}

check_architecture() {
  info "architecture" "Checking supported architecture"
  detect_architecture_support
  if [[ "$ARCHITECTURE_SUPPORT" == "supported" ]]; then
    record_ok "architecture" "supported architecture detected: ${ARCHITECTURE}"
  else
    record_fail "architecture" "unsupported architecture detected: ${ARCHITECTURE}. The current public support baseline is amd64/x86_64 plus Ubuntu 24.04 on arm64/aarch64"
  fi
}

check_init_system() {
  info "init" "Checking init system"
  local pid1
  pid1="$(read_pid1_comm)"
  if [[ "$pid1" == "systemd" ]]; then
    record_ok "init" "systemd is running as PID 1"
  else
    record_fail "init" "systemd is required as PID 1, detected ${pid1}"
  fi
}

check_required_commands() {
  info "commands" "Checking required commands"
  local cmd missing=()
  for cmd in bash sudo curl getent apt-get systemctl tar sha256sum mktemp; do
    if ! need_cmd "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    record_fail "commands" "missing required commands: ${missing[*]}"
  else
    record_ok "commands" "required commands are available"
  fi
}

check_sudo_posture() {
  info "sudo" "Checking sudo posture"
  if ! need_cmd sudo; then
    return
  fi
  if sudo -n true >/dev/null 2>&1; then
    record_ok "sudo" "sudo is available without an immediate password prompt"
  else
    record_warn "sudo" "sudo will likely require interactive authentication during bootstrap"
  fi
}

check_hardware_guidance() {
  info "hardware" "Checking hardware guidance"
  CPU_COUNT="$(read_cpu_count)"
  MEMTOTAL_KB="$(read_memtotal_kb)"
  DISK_AVAILABLE_BYTES="$(read_disk_available_bytes)"

  if [[ "$MODE" == "agent" || "$MODE" == "server" ]]; then
    record_ok "hardware" "base host checks collected for ${MODE} mode: ${CPU_COUNT} CPU, $(kb_to_gib "$MEMTOTAL_KB") GiB RAM, $(bytes_to_gib "$DISK_AVAILABLE_BYTES") GiB free disk"
    return
  fi

  if (( CPU_COUNT < 4 )); then
    record_warn "hardware" "CPU is below the practical minimum for the full stack: ${CPU_COUNT} detected, 4 required"
  elif (( CPU_COUNT < 6 )); then
    record_warn "hardware" "CPU is below the recommended range for the full stack: ${CPU_COUNT} detected, 6-8 recommended"
  else
    record_ok "hardware" "CPU meets the published full-stack guidance"
  fi

  if (( MEMTOTAL_KB < 12582912 )); then
    record_warn "hardware" "memory is below the practical minimum for the full stack: $(kb_to_gib "$MEMTOTAL_KB") GiB detected, 12 GiB required"
  elif (( MEMTOTAL_KB < 16777216 )); then
    record_warn "hardware" "memory is below the recommended guidance for the full stack: $(kb_to_gib "$MEMTOTAL_KB") GiB detected, 16 GiB recommended"
  else
    record_ok "hardware" "memory meets the published full-stack guidance"
  fi

  if (( DISK_AVAILABLE_BYTES < 64424509440 )); then
    record_warn "hardware" "free disk is below the practical minimum for the full stack: $(bytes_to_gib "$DISK_AVAILABLE_BYTES") GiB detected, 60 GiB required"
  elif (( DISK_AVAILABLE_BYTES < 107374182400 )); then
    record_warn "hardware" "free disk is below the recommended guidance for the full stack: $(bytes_to_gib "$DISK_AVAILABLE_BYTES") GiB detected, 100 GiB recommended"
  else
    record_ok "hardware" "free disk meets the published full-stack guidance"
  fi
}

print_summary() {
  local ok_count
  ok_count="$(printf '%s\n' "${CHECK_RESULTS[@]}" | awk 'BEGIN {count=0} /"level":"ok"/ {count++} END {print count+0}')"
  if [[ "$JSON_OUTPUT" == "1" ]]; then
    printf '{'
    printf '"mode":"%s",' "$(json_escape "$MODE")"
    printf '"strict":%s,' "$([[ "$STRICT" == "1" ]] && printf 'true' || printf 'false')"
    printf '"platform":{"os_id":"%s","version_id":"%s","codename":"%s","pretty_name":"%s","support":"%s","architecture":"%s","architecture_support":"%s"},' \
      "$(json_escape "$OS_ID")" \
      "$(json_escape "$OS_VERSION_ID")" \
      "$(json_escape "$OS_CODENAME")" \
      "$(json_escape "$OS_PRETTY_NAME")" \
      "$(json_escape "$PLATFORM_SUPPORT")" \
      "$(json_escape "$ARCHITECTURE")" \
      "$(json_escape "$ARCHITECTURE_SUPPORT")"
    printf '"resources":{"cpu_count":%s,"memory_kb":%s,"disk_available_bytes":%s},' \
      "$CPU_COUNT" "$MEMTOTAL_KB" "$DISK_AVAILABLE_BYTES"
    printf '"summary":{"ok_count":%s,"warn_count":%s,"fail_count":%s},' \
      "$ok_count" "$WARNINGS" "$FAILURES"
    printf '"results":[%s]}' "$(IFS=,; echo "${CHECK_RESULTS[*]}")"
    printf '\n'
  else
    printf '\nSummary: %s ok, %s warnings, %s failures\n' "$ok_count" "$WARNINGS" "$FAILURES"
  fi
}

main() {
  parse_args "$@"
  check_platform
  check_architecture
  check_init_system
  check_required_commands
  check_sudo_posture
  check_hardware_guidance
  print_summary

  if (( FAILURES > 0 )); then
    return 1
  fi

  if [[ "$STRICT" == "1" && "$WARNINGS" -gt 0 ]]; then
    return 1
  fi

  return 0
}

main "$@"
