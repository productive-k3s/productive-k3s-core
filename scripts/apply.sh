#!/usr/bin/env bash
set -euo pipefail

# Incremental k3s stack apply flow for Ubuntu and supported Debian targets
# - Detects existing installations first
# - Prompts before each change
# - Leaves existing cluster components untouched by default

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/component-versions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/addons-runtime.sh"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_GREEN=$'\033[1;32m'
  COLOR_YELLOW=$'\033[1;33m'
  COLOR_RED=$'\033[1;31m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_RESET=""
fi

nl() { printf '\r\n'; }
line() { printf '%s\r\n' "$*"; }

log(){ printf "\r\n%s[INFO]%s %s\r\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
warn(){ printf "\r\n%s[WARN]%s %s\r\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }
err(){ printf "\r\n%s[ERROR]%s %s\r\n" "$COLOR_RED" "$COLOR_RESET" "$*"; }

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e ':a;N;$!ba;s/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

DRY_RUN=0
MODE="single-node"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-base}"
PRODUCTIVE_K3S_ENGINE="${PRODUCTIVE_K3S_ENGINE:-native}"
PRODUCTIVE_K3S_SSH_HOST="${PRODUCTIVE_K3S_SSH_HOST:-}"
PRODUCTIVE_K3S_SSH_USER="${PRODUCTIVE_K3S_SSH_USER:-}"
PRODUCTIVE_K3S_SSH_PORT="${PRODUCTIVE_K3S_SSH_PORT:-22}"
PRODUCTIVE_K3S_SSH_KEY_PATH="${PRODUCTIVE_K3S_SSH_KEY_PATH:-}"
PRODUCTIVE_K3S_SSH_EXTRA_OPTS="${PRODUCTIVE_K3S_SSH_EXTRA_OPTS:-}"
DRY_RUN_REUSE=()
DRY_RUN_INSTALL=()
DRY_RUN_SKIP=()
DRY_RUN_WARNINGS=()
RUNS_DIR="runs"
RUN_ID=""
RUN_MANIFEST=""
RUN_PRIVATE_CONTEXT=""
RUN_STARTED_AT=""
RUN_STATUS="running"
CURRENT_STEP=""
MANIFEST_INITIALIZED=0
SUDO_KA_PID=""
OS_ID="unknown"
OS_VERSION_ID="unknown"
OS_CODENAME="unknown"
OS_PRETTY_NAME="unknown"
PLATFORM_SUPPORT="unsupported"
AGENT_SERVER_URL=""
AGENT_CLUSTER_TOKEN=""
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-}"
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT-https://telemetry.productive-k3s.io/telemetry}"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"
TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES:-3}"
TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-5}"
TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-10}"
TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR:-${RUNS_DIR}/telemetry-outbox}"
TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT:-productive-k3s/dev}"
TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-}"
TELEMETRY_PARENT_RUN_ID="${TELEMETRY_PARENT_RUN_ID:-}"
TELEMETRY_COMPONENT="${TELEMETRY_COMPONENT:-core}"
declare -A MANIFEST_SETTINGS=()
declare -A MANIFEST_DETECTED=()
declare -A MANIFEST_PLANNED=()
declare -A MANIFEST_RESULT=()
declare -A MANIFEST_NOTES=()
MANIFEST_COMPONENT_ORDER=(k3s helm cert_manager clusterissuer longhorn rancher registry nfs local_hosts docker_registry_trust)
PUBLIC_MANIFEST_SETTINGS=(
  host_os_id
  host_os_version_id
  host_os_codename
  host_os_pretty_name
  platform_support
  bootstrap_mode
  k3s_installation_engine
  agent_server_url_provided
  agent_cluster_token_provided
  tls_mode
  letsencrypt_environment
  longhorn_replica_count
  longhorn_minimal_available_percentage
  longhorn_single_node_mode
  registry_pvc_size
  registry_storage_class_configured
  registry_auth_enabled
  nfs_manage
  manage_local_hosts
  trust_registry_in_docker
  telemetry_enabled
  telemetry_max_retries
)
PRIVATE_MANIFEST_SETTINGS=(
  agent_server_url
  base_domain
  rancher_host
  registry_host
  longhorn_data_path
  registry_storage_class
  nfs_export_path
  nfs_allowed_network
)

need_cmd() { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1" >/dev/null 2>&1; }
mount_exists() { mountpoint -q "$1"; }
can_use_tty() { [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]; }
is_truthy() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

bootstrap_event_mode_name() {
  printf '%s' "${MODE}" | tr '-' '_'
}

emit_bootstrap_lifecycle_event() {
  local phase="$1"
  local result="$2"
  local sender_script="${SCRIPT_DIR}/send-telemetry-event.sh"
  local event_file event_name

  if ! is_truthy "${TELEMETRY_ENABLED:-false}"; then
    return 0
  fi
  if [[ -z "${TELEMETRY_ENDPOINT:-}" || ! -f "${sender_script}" ]]; then
    return 0
  fi

  event_name="core.apply.$(bootstrap_event_mode_name).${phase}"
  event_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "event_family": "usage",\n'
    printf '  "event_name": "%s",\n' "$(json_escape "${event_name}")"
    printf '  "sent_at": "%s",\n' "$(json_escape "$(date -Iseconds)")"
    printf '  "session_id": "%s",\n' "$(json_escape "${TELEMETRY_SESSION_ID}")"
    printf '  "run_id": "%s",\n' "$(json_escape "${RUN_ID}")"
    printf '  "parent_run_id": "%s",\n' "$(json_escape "${TELEMETRY_PARENT_RUN_ID:-}")"
    printf '  "component": "core",\n'
    printf '  "command": {\n'
    printf '    "name": "apply",\n'
    printf '    "mode": "%s",\n' "$(json_escape "${MODE}")"
    printf '    "result": "%s"\n' "$(json_escape "${result}")"
    printf '  },\n'
    printf '  "client": {\n'
    printf '    "repository": "productive-k3s-core",\n'
    printf '    "script": "scripts/apply.sh",\n'
    printf '    "telemetry_enabled": "%s"\n' "$(json_escape "${TELEMETRY_ENABLED}")"
    printf '  },\n'
    printf '  "telemetry_meta": {\n'
    printf '    "delivery_mode": "best-effort",\n'
    printf '    "anonymous_by_contract": true\n'
    printf '  }\n'
    printf '}\n'
  } > "${event_file}"

  TELEMETRY_RUN_ID="${RUN_ID}" TELEMETRY_MARKER="${TELEMETRY_MARKER}" bash "${sender_script}" "${event_file}" >/dev/null 2>&1 || true
  rm -f "${event_file}"
}
k3s_server_active() { service_active k3s; }
k3s_agent_active() { service_active k3s-agent; }

k3s_component_active() {
  if [[ "$MODE" == "agent" ]]; then
    k3s_agent_active
  else
    k3s_server_active
  fi
}

mode_runs_base() {
  [[ "$MODE" == "single-node" || "$MODE" == "server" ]]
}

mode_runs_stack() {
  [[ "$MODE" == "single-node" || "$MODE" == "stack" ]]
}

mode_runs_host_local() {
  [[ "$MODE" == "single-node" ]]
}

mode_uses_single_node_defaults() {
  [[ "$MODE" == "single-node" || "$MODE" == "stack" ]]
}

mode_description() {
  case "$MODE" in
    single-node)
      printf '%s' "single-node installation"
      ;;
    server)
      printf '%s' "server apply installation"
      ;;
    agent)
      printf '%s' "agent join installation"
      ;;
    stack)
      printf '%s' "cluster stack installation"
      ;;
  esac
}

result_for_mode() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run'
  else
    printf '%s' "$1"
  fi
}

validate_k3s_engine() {
  case "$PRODUCTIVE_K3S_ENGINE" in
    native|k3sup)
      ;;
    *)
      err "Unsupported k3s installation engine: ${PRODUCTIVE_K3S_ENGINE}"
      exit 1
      ;;
  esac
}

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e ':a;N;$!ba;s/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

manifest_set_setting() {
  MANIFEST_SETTINGS["$1"]="$2"
}

detect_host_platform() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    OS_CODENAME="${VERSION_CODENAME:-unknown}"
    OS_PRETTY_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
  fi

  case "$OS_ID:$OS_VERSION_ID" in
    ubuntu:*)
      PLATFORM_SUPPORT="supported"
      ;;
    debian:12|debian:13)
      PLATFORM_SUPPORT="supported"
      ;;
    *)
      PLATFORM_SUPPORT="unsupported"
      ;;
  esac

  manifest_set_setting "host_os_id" "$OS_ID"
  manifest_set_setting "host_os_version_id" "$OS_VERSION_ID"
  manifest_set_setting "host_os_codename" "$OS_CODENAME"
  manifest_set_setting "host_os_pretty_name" "$OS_PRETTY_NAME"
  manifest_set_setting "platform_support" "$PLATFORM_SUPPORT"
}

manifest_record_component() {
  local component="$1" detected_before="$2" planned_action="$3"
  MANIFEST_DETECTED["$component"]="$detected_before"
  MANIFEST_PLANNED["$component"]="$planned_action"
  if [[ -z "${MANIFEST_RESULT[$component]+x}" ]]; then
    MANIFEST_RESULT["$component"]="pending"
  fi
}

manifest_complete_component() {
  local component="$1" result="$2" note="${3:-}"
  MANIFEST_RESULT["$component"]="$result"
  if [[ -n "$note" ]]; then
    MANIFEST_NOTES["$component"]="$note"
  fi
}

init_run_manifest() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  RUN_ID="${ts}-$$-${RANDOM}${RANDOM}"
  RUN_STARTED_AT="$(date -Iseconds)"
  mkdir -p "$RUNS_DIR"
  RUN_MANIFEST="${RUNS_DIR}/apply-${RUN_ID}.json"
  RUN_PRIVATE_CONTEXT="${RUNS_DIR}/apply-${RUN_ID}.private-context"
  MANIFEST_INITIALIZED=1
}

write_run_manifest() {
  local exit_code="${1:-0}"
  [[ "$MANIFEST_INITIALIZED" == "1" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "script": "scripts/apply.sh",\n'
    printf '  "mode": "%s",\n' "$( [[ "$DRY_RUN" == "1" ]] && printf 'dry-run' || printf 'apply' )"
    printf '  "status": "%s",\n' "$(json_escape "$RUN_STATUS")"
    printf '  "exit_code": %s,\n' "$exit_code"
    printf '  "started_at": "%s",\n' "$(json_escape "$RUN_STARTED_AT")"
    printf '  "finished_at": "%s",\n' "$(date -Iseconds)"
    printf '  "current_step": "%s",\n' "$(json_escape "${CURRENT_STEP:-}")"

    printf '  "settings": {\n'
    local first=1 key
    for key in "${PUBLIC_MANIFEST_SETTINGS[@]}"; do
      [[ -n "${MANIFEST_SETTINGS[$key]+x}" ]] || continue
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": "%s"' "$(json_escape "$key")" "$(json_escape "${MANIFEST_SETTINGS[$key]}")"
    done
    printf '\n  },\n'

    printf '  "components": {\n'
    first=1
    local component
    for component in "${MANIFEST_COMPONENT_ORDER[@]}"; do
      [[ -n "${MANIFEST_PLANNED[$component]+x}" || -n "${MANIFEST_DETECTED[$component]+x}" || -n "${MANIFEST_RESULT[$component]+x}" ]] || continue
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": {' "$(json_escape "$component")"
      printf '"detected_before": "%s", ' "$(json_escape "${MANIFEST_DETECTED[$component]:-unknown}")"
      printf '"planned_action": "%s", ' "$(json_escape "${MANIFEST_PLANNED[$component]:-unknown}")"
      printf '"result": "%s"' "$(json_escape "${MANIFEST_RESULT[$component]:-unknown}")"
      if [[ "$component" == "clusterissuer" && -n "${MANIFEST_NOTES[$component]:-}" ]]; then
        printf ', "note": "%s"' "$(json_escape "${MANIFEST_NOTES[$component]}")"
      fi
      printf '}'
    done
    printf '\n  }\n'
    printf '}\n'
  } > "$tmp_file"
  mv "$tmp_file" "$RUN_MANIFEST"
}

write_private_run_context() {
  local exit_code="${1:-0}"
  [[ "$MANIFEST_INITIALIZED" == "1" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "script": "scripts/apply.sh",\n'
    printf '  "mode": "%s",\n' "$( [[ "$DRY_RUN" == "1" ]] && printf 'dry-run' || printf 'apply' )"
    printf '  "status": "%s",\n' "$(json_escape "$RUN_STATUS")"
    printf '  "exit_code": %s,\n' "$exit_code"
    printf '  "started_at": "%s",\n' "$(json_escape "$RUN_STARTED_AT")"
    printf '  "finished_at": "%s",\n' "$(date -Iseconds)"
    printf '  "settings": {\n'
    local first=1 key
    for key in "${PRIVATE_MANIFEST_SETTINGS[@]}"; do
      [[ -n "${MANIFEST_SETTINGS[$key]+x}" ]] || continue
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": "%s"' "$(json_escape "$key")" "$(json_escape "${MANIFEST_SETTINGS[$key]}")"
    done
    printf '\n  },\n'
    printf '  "components": {\n'
    first=1
    local component
    for component in "${MANIFEST_COMPONENT_ORDER[@]}"; do
      [[ -n "${MANIFEST_NOTES[$component]:-}" ]] || continue
      if [[ "$component" == "clusterissuer" ]]; then
        continue
      fi
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": {' "$(json_escape "$component")"
      printf '"note": "%s"' "$(json_escape "${MANIFEST_NOTES[$component]}")"
      printf '}'
    done
    printf '\n  }\n'
    printf '}\n'
  } > "$tmp_file"
  mv "$tmp_file" "$RUN_PRIVATE_CONTEXT"
}

cleanup_exit() {
  local exit_code=$?
  if [[ -n "${SUDO_KA_PID:-}" ]]; then
    kill "${SUDO_KA_PID}" >/dev/null 2>&1 || true
  fi
  if [[ "$exit_code" -eq 0 ]]; then
    RUN_STATUS="success"
  else
    RUN_STATUS="failed"
  fi
  write_run_manifest "$exit_code"
  write_private_run_context "$exit_code"
  emit_bootstrap_lifecycle_event "completed" "$([[ "$exit_code" -eq 0 ]] && printf 'success' || printf 'failed')"
  if ! maybe_send_telemetry "$exit_code"; then
    warn "Telemetry delivery did not complete successfully. Installation result is unchanged."
  fi
}

maybe_send_telemetry() {
  local exit_code="${1:-0}"
  local sender_script="${SCRIPT_DIR}/send-telemetry.sh"

  if ! is_truthy "${TELEMETRY_ENABLED:-false}"; then
    return 0
  fi

  if [[ -z "${TELEMETRY_ENDPOINT:-}" ]]; then
    warn "Telemetry is enabled but TELEMETRY_ENDPOINT is not set. Skipping telemetry delivery."
    return 0
  fi

  if [[ ! -f "${RUN_MANIFEST:-}" ]]; then
    warn "Telemetry is enabled but the public run manifest is unavailable. Skipping telemetry delivery."
    return 1
  fi

  if [[ ! -x "$sender_script" ]]; then
    warn "Telemetry sender script is missing or not executable: $sender_script"
    return 1
  fi

  TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT}" \
  TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES}" \
  TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS}" \
  TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS}" \
  TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR}" \
  TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT}" \
  TELEMETRY_ENABLED="${TELEMETRY_ENABLED}" \
  TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID}" \
  TELEMETRY_RUN_ID="${RUN_ID}" \
  TELEMETRY_PARENT_RUN_ID="${TELEMETRY_PARENT_RUN_ID}" \
  TELEMETRY_COMPONENT="core" \
  TELEMETRY_MARKER="${TELEMETRY_MARKER}" \
  TELEMETRY_SOURCE_REPOSITORY="productive-k3s" \
  TELEMETRY_SOURCE_SCRIPT="scripts/apply.sh" \
  TELEMETRY_EXIT_CODE="${exit_code}" \
  bash "$sender_script" "$RUN_MANIFEST"
}

prompt() {
  local var="$1" default="$2" msg="$3"
  local val
  if can_use_tty; then
    printf '%s [%s]: ' "$msg" "$default" > /dev/tty
    IFS= read -r val < /dev/tty || true
  else
    printf '%s [%s]: ' "$msg" "$default"
    IFS= read -r val || true
  fi
  val="${val:-$default}"
  printf -v "$var" '%s' "$val"
}

prompt_yesno() {
  local var="$1" default="$2" msg="$3"
  local val
  local d="$default"
  if can_use_tty; then
    printf '%s [%s] (y/n): ' "$msg" "$d" > /dev/tty
    IFS= read -r val < /dev/tty || true
  else
    printf '%s [%s] (y/n): ' "$msg" "$d"
    IFS= read -r val || true
  fi
  val="${val:-$d}"
  case "$val" in
    y|Y) printf -v "$var" 'y' ;;
    n|N) printf -v "$var" 'n' ;;
    *) warn "Invalid input, using default: $d"; printf -v "$var" '%s' "$d" ;;
  esac
}

resolve_telemetry_enabled() {
  if [[ -n "${TELEMETRY_ENABLED:-}" ]]; then
    return 0
  fi

  if can_use_tty; then
    local telemetry_consent="y"
    prompt_yesno telemetry_consent "y" "Productive K3S can send anonymous telemetry about this run to help improve the installation flow. It does not include any sensitive information like hostnames or other environment-specific identifiers. Enable anonymous telemetry for this run?"
    if [[ "${telemetry_consent}" == "y" ]]; then
      TELEMETRY_ENABLED="true"
    else
      TELEMETRY_ENABLED="false"
    fi
    return 0
  fi

  TELEMETRY_ENABLED="false"
}

bind_stdin_to_tty() {
  if can_use_tty; then
    exec </dev/tty
  fi
}

sudo_keepalive() {
  if ! sudo -n true 2>/dev/null; then
    log "Requesting sudo..."
    sudo -v
  fi
  ( while true; do sudo -n true; sleep 30; done ) </dev/null >/dev/null 2>&1 &
  SUDO_KA_PID=$!
}

kubectl_k3s() { sudo k3s kubectl "$@"; }

namespace_exists() { kubectl_k3s get namespace "$1" >/dev/null 2>&1; }
deployment_exists() { kubectl_k3s get deployment "$2" -n "$1" >/dev/null 2>&1; }
secret_exists() { kubectl_k3s get secret "$2" -n "$1" >/dev/null 2>&1; }
storageclass_exists() { kubectl_k3s get storageclass "$1" >/dev/null 2>&1; }
clusterissuer_exists() { kubectl_k3s get clusterissuer "$1" >/dev/null 2>&1; }

cluster_node_count() {
  if k3s_server_active; then
    kubectl_k3s get nodes --no-headers 2>/dev/null | awk 'END {print NR+0}'
  else
    printf '0'
  fi
}
helm_release_exists() {
  need_cmd helm || return 1
  helm status "$1" -n "$2" >/dev/null 2>&1
}

get_primary_node_ip() {
  local ip=""

  if k3s_server_active; then
    ip="$(kubectl_k3s get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
  fi

  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi

  printf '%s' "$ip"
}

nfs_path_looks_valid() {
  local path="$1"
  [[ "$path" == /* ]] && [[ "$path" != "y" ]] && [[ "$path" != "n" ]]
}

nfs_network_looks_valid() {
  local network="$1"
  [[ "$network" =~ ^[^[:space:]]+(/[0-9]{1,2})?$ ]] && [[ "$network" != "y" ]] && [[ "$network" != "n" ]]
}
nfs_export_exists() {
  local path="$1"
  grep -qE "^[[:space:]]*${path//\//\\/}[[:space:]]" /etc/exports 2>/dev/null
}

nfs_service_name() {
  if systemctl list-unit-files nfs-server.service >/dev/null 2>&1; then
    echo "nfs-server"
  else
    echo "nfs-kernel-server"
  fi
}

nfs_server_active() {
  local service_name
  service_name="$(nfs_service_name)"
  service_active "$service_name"
}

get_first_ingress_host() {
  local ns="$1" name="$2"
  kubectl_k3s get ingress "$name" -n "$ns" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true
}

run_cmd() {
  local desc="$1"
  shift

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] ${desc}"
    printf '  '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}


run_cmd_with_retries() {
  local desc="$1"
  local timeout_secs="$2"
  local sleep_secs="$3"
  shift 3

  if [[ "$DRY_RUN" == "1" ]]; then
    run_cmd "$desc" "$@"
    return 0
  fi

  local start_ts now_ts
  start_ts="$(date +%s)"

  while true; do
    if "$@"; then
      return 0
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_secs )); then
      return 1
    fi

    warn "${desc} did not succeed yet. Waiting ${sleep_secs}s before retrying."
    sleep "$sleep_secs"
  done
}

run_shell() {
  local desc="$1" cmd="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] ${desc}"
    echo "  ${cmd}"
    return 0
  fi

  bash -lc "$cmd" </dev/null
}

apply_manifest() {
  local desc="$1" manifest="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] ${desc}"
    printf '%s\n' "$manifest"
    return 0
  fi

  printf '%s\n' "$manifest" | kubectl_k3s apply -f -
}

apply_manifest_with_retries() {
  local desc="$1" manifest="$2"
  local timeout_secs="${3:-120}"
  local sleep_secs="${4:-5}"
  local start_ts now_ts
  start_ts="$(date +%s)"

  while true; do
    if apply_manifest "$desc" "$manifest"; then
      return 0
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_secs )); then
      return 1
    fi

    warn "${desc} did not succeed yet. Waiting ${sleep_secs}s before retrying."
    sleep "$sleep_secs"
  done
}

wait_for_secret() {
  local ns="$1" name="$2" timeout="${3:-120}"
  local start now

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Skipping wait for secret ${ns}/${name}."
    return 0
  fi

  start="$(date +%s)"
  while true; do
    if secret_exists "$ns" "$name"; then
      return 0
    fi

    now="$(date +%s)"
    if (( now - start > timeout )); then
      return 1
    fi
    sleep 2
  done
}

wait_for_certificate_ready() {
  local ns="$1" name="$2" timeout="${3:-180}"
  local start now ready

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Skipping wait for certificate ${ns}/${name}."
    return 0
  fi

  start="$(date +%s)"
  while true; do
    ready="$(kubectl_k3s get certificate "$name" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "$ready" == "True" ]]; then
      return 0
    fi

    now="$(date +%s)"
    if (( now - start > timeout )); then
      return 1
    fi
    sleep 2
  done
}

ensure_rancher_private_ca_secret() {
  local source_secret_ns="cattle-system"
  local source_secret_name="rancher-tls"
  local target_secret_name="tls-ca"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Creating Rancher CA secret ${source_secret_ns}/${target_secret_name} from ${source_secret_name}"
    echo "  sudo k3s kubectl create secret generic ${target_secret_name} --from-literal=cacerts.pem=<ca.crt from ${source_secret_name}>"
    return 0
  fi

  local ca_crt
  ca_crt="$(kubectl_k3s get secret "$source_secret_name" -n "$source_secret_ns" -o jsonpath='{.data.ca\.crt}' | base64 -d)"
  if [[ -z "$ca_crt" ]]; then
    err "Secret ${source_secret_ns}/${source_secret_name} does not contain ca.crt; Rancher private CA cannot be configured."
    exit 1
  fi

  kubectl_k3s delete secret "$target_secret_name" -n "$source_secret_ns" >/dev/null 2>&1 || true
  kubectl_k3s create secret generic "$target_secret_name" -n "$source_secret_ns" --from-literal=cacerts.pem="$ca_crt" >/dev/null
}

ensure_local_hosts_entries() {
  local target_ip="$1"
  shift
  local hosts=("$@")

  if [[ -z "$target_ip" || ${#hosts[@]} -eq 0 ]]; then
    warn "Skipping /etc/hosts update because the target IP or hostnames are missing."
    return
  fi

  local hosts_regex
  hosts_regex="$(printf '%s\n' "${hosts[@]}" | sed 's/[.[\\*^$()+?{|]/\\\\&/g' | paste -sd'|' -)"
  local host_line="${target_ip} ${hosts[*]}"
  local cmd="tmp=\$(mktemp); grep -vE '(^|[[:space:]])(${hosts_regex})([[:space:]]|$)' /etc/hosts > \"\$tmp\" || true; printf '%s\\n' '${host_line}' >> \"\$tmp\"; cat \"\$tmp\" > /etc/hosts; rm -f \"\$tmp\""

  if [[ "$DRY_RUN" == "1" ]]; then
    track_install "local /etc/hosts entries"
    log "[dry-run] Adding/updating local /etc/hosts entries"
    line "  ${host_line}"
    manifest_complete_component "local_hosts" "dry-run" "$host_line"
    return
  fi

  run_cmd "Adding/updating local /etc/hosts entries" sudo bash -lc "$cmd"
  manifest_complete_component "local_hosts" "configured" "$host_line"
}

ensure_local_docker_registry_trust() {
  local registry_host="$1"

  if [[ -z "$registry_host" ]]; then
    warn "Skipping Docker trust setup because the registry hostname is missing."
    return
  fi

  if ! need_cmd docker; then
    warn "Skipping Docker trust setup because docker is not installed on this machine."
    return
  fi

  if ! secret_exists registry registry-tls; then
    warn "Skipping Docker trust setup because registry/registry-tls does not exist."
    return
  fi

  local cert_dir="/etc/docker/certs.d/${registry_host}"
  local cert_file="${cert_dir}/ca.crt"

  if [[ "$DRY_RUN" == "1" ]]; then
    track_install "Docker registry trust for ${registry_host}"
    log "[dry-run] Installing Docker trust for ${registry_host}"
    line "  sudo mkdir -p ${cert_dir}"
    line "  sudo k3s kubectl get secret registry-tls -n registry -o jsonpath='{.data.tls\\.crt}' | base64 -d | sudo tee ${cert_file}"
    line "  sudo systemctl restart docker"
    manifest_complete_component "docker_registry_trust" "dry-run" "$registry_host"
    return
  fi

  run_cmd "Creating Docker cert directory ${cert_dir}" sudo mkdir -p "$cert_dir"
  kubectl_k3s get secret registry-tls -n registry -o jsonpath='{.data.tls\.crt}' | base64 -d | sudo tee "$cert_file" >/dev/null

  if systemctl list-unit-files docker.service >/dev/null 2>&1; then
    run_cmd "Restarting Docker" sudo systemctl restart docker
  else
    warn "Docker certificate installed for ${registry_host}, but docker.service was not found for automatic restart."
  fi
  manifest_complete_component "docker_registry_trust" "configured" "$registry_host"
}

ensure_user_kubeconfig() {
  local source_kubeconfig="/etc/rancher/k3s/k3s.yaml"
  local target_dir="${HOME}/.kube"
  local target_kubeconfig="${target_dir}/k3s.yaml"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Preparing user kubeconfig at ${target_kubeconfig}"
    echo "  sudo cp ${source_kubeconfig} ${target_kubeconfig}"
    echo "  sudo chown $(id -u):$(id -g) ${target_kubeconfig}"
    echo "  chmod 600 ${target_kubeconfig}"
    export KUBECONFIG="$target_kubeconfig"
    return 0
  fi

  if [[ ! -f "$source_kubeconfig" ]]; then
    err "k3s kubeconfig was not found at ${source_kubeconfig}."
    exit 1
  fi

  if [[ ! -d "$target_dir" ]]; then
    run_cmd "Creating ${target_dir}" mkdir -p "$target_dir"
  fi

  sudo cp "$source_kubeconfig" "$target_kubeconfig"
  sudo chown "$(id -u):$(id -g)" "$target_kubeconfig"
  chmod 600 "$target_kubeconfig"

  export KUBECONFIG="$target_kubeconfig"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --mode)
        MODE="${2:-}"
        shift
        ;;
      -h|--help)
        cat <<EOF
Usage: $0 [--dry-run] [--mode <single-node|server|agent|stack>]

Modes:
  single-node  Default. Bootstraps a single-node installation and can install the local stack.
  server       Bootstraps only the base server node components.
  agent        Reserved for future agent node join support.
  stack        Installs or reuses stack components on top of an existing cluster.

Environment:
  PRODUCTIVE_K3S_ENGINE=native|k3sup  Select the base k3s installation engine (default: native).
EOF
        exit 0
        ;;
      *)
        err "Unknown argument: $1"
        exit 1
        ;;
    esac
    shift
  done

  case "$MODE" in
    single-node|server|agent|stack)
      ;;
    *)
      err "Unsupported mode: ${MODE}"
      exit 1
      ;;
  esac
}

track_reuse() {
  [[ "$DRY_RUN" == "1" ]] || return 0
  DRY_RUN_REUSE+=("$1")
}

track_install() {
  [[ "$DRY_RUN" == "1" ]] || return 0
  DRY_RUN_INSTALL+=("$1")
}

track_skip() {
  [[ "$DRY_RUN" == "1" ]] || return 0
  DRY_RUN_SKIP+=("$1")
}

track_warning() {
  [[ "$DRY_RUN" == "1" ]] || return 0
  DRY_RUN_WARNINGS+=("$1")
}

print_dry_run_summary() {
  [[ "$DRY_RUN" == "1" ]] || return 0

  log "Dry-run summary"

  line "  Reuse existing:"
  if (( ${#DRY_RUN_REUSE[@]} == 0 )); then
    line "    - none"
  else
    printf '    - %s\r\n' "${DRY_RUN_REUSE[@]}"
  fi

  line "  Would install/configure:"
  if (( ${#DRY_RUN_INSTALL[@]} == 0 )); then
    line "    - none"
  else
    printf '    - %s\r\n' "${DRY_RUN_INSTALL[@]}"
  fi

  line "  Skipped by choice/preflight:"
  if (( ${#DRY_RUN_SKIP[@]} == 0 )); then
    line "    - none"
  else
    printf '    - %s\r\n' "${DRY_RUN_SKIP[@]}"
  fi

  line "  Warnings:"
  if (( ${#DRY_RUN_WARNINGS[@]} == 0 )); then
    line "    - none"
  else
    printf '    - %s\r\n' "${DRY_RUN_WARNINGS[@]}"
  fi
}

wait_pods_ready() {
  local ns="$1" timeout="${2:-300}"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Skipping wait for namespace '${ns}'."
    return
  fi

  log "Waiting for pods in namespace '$ns' to be Ready (timeout ${timeout}s)..."
  local start now
  start="$(date +%s)"
  while true; do
    if kubectl_k3s get pods -n "$ns" >/dev/null 2>&1; then
      local not_ready
      not_ready="$(kubectl_k3s get pods -n "$ns" --no-headers 2>/dev/null | awk '
        {status=$3}
        status!="Running" && status!="Completed" {print; next}
      ')"
      local bad_ready
      bad_ready="$(kubectl_k3s get pods -n "$ns" --no-headers 2>/dev/null | awk '
        $3=="Running" {
          split($2,a,"/");
          if (a[1]!=a[2]) print
        }
      ')"
      if [[ -z "$not_ready" && -z "$bad_ready" ]]; then
        log "Namespace '$ns' looks Ready."
        break
      fi
    fi
    now="$(date +%s)"
    if (( now - start > timeout )); then
      warn "Timeout waiting for namespace '$ns'. Showing pods:"
      kubectl_k3s get pods -n "$ns" -o wide || true
      break
    fi
    sleep 5
  done
}

wait_service_endpoints() {
  local ns="$1" svc="$2" timeout="${3:-180}"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Skipping wait for service endpoints '${ns}/${svc}'."
    return
  fi

  log "Waiting for service '${svc}' in namespace '${ns}' to have endpoints (timeout ${timeout}s)..."
  local start now subsets
  start="$(date +%s)"
  while true; do
    subsets="$(kubectl_k3s get endpoints -n "$ns" "$svc" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
    if [[ -n "$subsets" ]]; then
      log "Service '${svc}' in namespace '${ns}' has endpoints."
      return
    fi

    now="$(date +%s)"
    if (( now - start > timeout )); then
      warn "Timeout waiting for service '${svc}' in namespace '${ns}' to gain endpoints."
      kubectl_k3s get endpoints -n "$ns" "$svc" -o wide || true
      return
    fi
    sleep 5
  done
}

wait_k3s_ready() {
  local timeout="${1:-180}"
  local start now ready_nodes
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Skipping wait for k3s API readiness."
    return 0
  fi

  log "Waiting for k3s API and node readiness (timeout ${timeout}s)..."
  start="$(date +%s)"
  while true; do
    if service_active k3s && kubectl_k3s get nodes >/dev/null 2>&1; then
      ready_nodes="$(kubectl_k3s get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{count++} END{print count+0}')"
      if (( ready_nodes > 0 )); then
        log "k3s API is reachable and at least one node is Ready."
        return 0
      fi
    fi

    now="$(date +%s)"
    if (( now - start > timeout )); then
      err "Timed out waiting for k3s API readiness."
      sudo systemctl status k3s --no-pager || true
      kubectl_k3s get nodes -o wide || true
      return 1
    fi
    sleep 5
  done
}

ensure_namespace() {
  local ns="$1"
  if ! namespace_exists "$ns"; then
    run_cmd "Creating namespace ${ns}" kubectl_k3s create namespace "$ns"
  fi
}

ensure_helm_repo() {
  local name="$1" url="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] Adding Helm repo ${name}"
    echo "  helm repo add ${name} ${url}"
    return
  fi

  if helm repo list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$name"; then
    return
  fi

  if run_cmd_with_retries "Adding Helm repo ${name}" 120 5 helm repo add "$name" "$url" >/dev/null 2>&1; then
    return
  fi

  err "Failed to add Helm repo '${name}' (${url})."
  exit 1
}

print_detection_summary() {
  local k3s_state="$1" helm_state="$2" cert_state="$3" longhorn_state="$4" rancher_state="$5" registry_state="$6" nfs_state="$7"
  log "Detected environment"
  printf '  - k3s: %s\r\n' "$k3s_state"
  printf '  - helm: %s\r\n' "$helm_state"
  printf '  - cert-manager: %s\r\n' "$cert_state"
  printf '  - Longhorn: %s\r\n' "$longhorn_state"
  printf '  - Rancher: %s\r\n' "$rancher_state"
  printf '  - Registry: %s\r\n' "$registry_state"
  printf '  - NFS server: %s\r\n' "$nfs_state"
}

print_diagnosis_summary() {
  local k3s_state="$1" helm_state="$2" cert_state="$3" longhorn_state="$4" rancher_state="$5" registry_state="$6" nfs_state="$7"
  log "Diagnosis"
  if [[ "$k3s_state" == "missing" ]]; then
    line "  - k3s is missing."
  fi
  if [[ "$helm_state" == "missing" ]]; then
    line "  - helm is missing."
  fi
  if [[ "$cert_state" == "missing" ]]; then
    line "  - cert-manager is missing."
  fi
  if [[ "$longhorn_state" == "missing" ]]; then
    line "  - Longhorn is missing."
    line "    Prepare and mount dedicated storage yourself if you want it; this script will not format disks."
  fi
  if [[ "$rancher_state" == "missing" ]]; then
    line "  - Rancher is missing."
  fi
  if [[ "$registry_state" == "missing" ]]; then
    line "  - Internal registry is missing."
  fi
  if [[ "$nfs_state" == "missing" ]]; then
    line "  - NFS server is missing."
  fi
  if [[ "$k3s_state" == "present" && "$helm_state" == "present" && "$cert_state" == "present" && "$longhorn_state" == "present" && "$rancher_state" == "present" && "$registry_state" == "present" && "$nfs_state" == "present" ]]; then
    line "  - Core stack components are already present."
  fi
}

print_plan_summary() {
  local k3s_action="$1" helm_action="$2" cert_action="$3" longhorn_action="$4" rancher_action="$5" registry_action="$6" nfs_manage="$7" hosts_manage="$8" docker_trust_manage="$9"
  log "Planned actions"
  line "  Cluster:"
  printf '    - k3s: %s\r\n' "$k3s_action"
  printf '    - helm: %s\r\n' "$helm_action"
  printf '    - cert-manager: %s\r\n' "$cert_action"
  printf '    - Longhorn: %s\r\n' "$longhorn_action"
  printf '    - Rancher: %s\r\n' "$rancher_action"
  printf '    - Registry: %s\r\n' "$registry_action"
  line "  Host:"
  printf '    - NFS management: %s\r\n' "$nfs_manage"
  printf '    - /etc/hosts: %s\r\n' "$hosts_manage"
  printf '    - Docker registry trust: %s\r\n' "$docker_trust_manage"
}

ensure_packages() {
  local label="$1"
  shift

  local missing=()
  local pkg
  for pkg in "$@"; do
    if ! pkg_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    log "Required packages for ${label} are already installed."
    return
  fi

  warn "Missing OS packages for ${label}: ${missing[*]}"
  local install_pkgs="y"
  prompt_yesno install_pkgs "y" "Install the missing packages for ${label}?"
  if [[ "$install_pkgs" != "y" ]]; then
    err "Cannot continue with ${label} without those packages."
    exit 1
  fi

  log "Installing packages for ${label}..."
  run_cmd "Updating apt indexes for ${label}" sudo apt-get update -y
  run_cmd "Installing packages for ${label}" sudo apt-get install -y "${missing[@]}"
}

ensure_iscsid() {
  if service_active iscsid; then
    log "Service 'iscsid' already active."
    return
  fi

  local enable_iscsid="y"
  prompt_yesno enable_iscsid "y" "Enable and start 'iscsid' now?"
  if [[ "$enable_iscsid" == "y" ]]; then
    run_cmd "Enabling and starting iscsid" sudo systemctl enable --now iscsid
  else
    warn "Longhorn requires 'iscsid'. Skipping it may break Longhorn volumes."
  fi
}

namespace_has_user_resources() {
  local ns="$1"
  kubectl_k3s get deploy,statefulset,daemonset,job,cronjob,ingress,pvc -n "$ns" --ignore-not-found --no-headers 2>/dev/null | grep -q .
}

find_ingress_host_conflicts() {
  local host="$1" expected_ns="$2" expected_name="$3"
  kubectl_k3s get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' 2>/dev/null | \
    awk -F'|' -v host="$host" -v expected_ns="$expected_ns" -v expected_name="$expected_name" '
      $3 == host && !($1 == expected_ns && $2 == expected_name) { print $1 "/" $2 }
    '
}

count_default_storageclasses() {
  kubectl_k3s get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | \
    awk -F'|' '$2 == "true" {count++} END {print count+0}'
}

confirm_preflight() {
  local component="$1" warnings_found="$2"

  if (( warnings_found == 0 )); then
    log "Preflight checks for ${component} passed."
    return 0
  fi

  local continue_anyway="n"
  if is_truthy "${PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS:-false}"; then
    continue_anyway="y"
  else
    prompt_yesno continue_anyway "n" "${component} preflight found warnings. Continue anyway?"
  fi
  if [[ "$continue_anyway" != "y" ]]; then
    warn "${component} installation cancelled."
    track_skip "${component}: cancelled after preflight warnings"
    return 1
  fi

  return 0
}

preflight_cert_manager_install() {
  local warnings_found=0

  if ! service_active k3s; then
    warn "k3s is not active, so cert-manager preflight can only be partial."
    track_warning "cert-manager: k3s is not active, preflight is partial"
    ((warnings_found+=1))
    confirm_preflight "cert-manager" "$warnings_found"
    return
  fi

  if namespace_exists cert-manager && namespace_has_user_resources cert-manager; then
    warn "Namespace 'cert-manager' already contains resources, but cert-manager was not detected as installed."
    track_warning "cert-manager: namespace already has resources"
    ((warnings_found+=1))
  fi

  confirm_preflight "cert-manager" "$warnings_found"
}

preflight_longhorn_install() {
  local data_path="$1"
  local warnings_found=0
  local default_sc_count=0

  if ! service_active k3s; then
    warn "k3s is not active, so Longhorn preflight can only be partial."
    track_warning "Longhorn: k3s is not active, preflight is partial"
    ((warnings_found+=1))
    confirm_preflight "Longhorn" "$warnings_found"
    return
  fi

  if namespace_exists longhorn-system && namespace_has_user_resources longhorn-system; then
    warn "Namespace 'longhorn-system' already contains resources, but Longhorn release was not detected."
    track_warning "Longhorn: longhorn-system namespace already has resources"
    ((warnings_found+=1))
  fi

  if storageclass_exists longhorn; then
    warn "StorageClass 'longhorn' already exists."
    track_warning "Longhorn: storageclass 'longhorn' already exists"
    ((warnings_found+=1))
  fi

  if [[ -e "$data_path" && ! -d "$data_path" ]]; then
    warn "Longhorn data path '${data_path}' exists and is not a directory."
    track_warning "Longhorn: data path '${data_path}' exists and is not a directory"
    ((warnings_found+=1))
  fi

  if [[ -d "$data_path" ]] && ! mount_exists "$data_path"; then
    warn "Longhorn data path '${data_path}' exists but is not a mount point."
    track_warning "Longhorn: data path '${data_path}' exists but is not a mount point"
    ((warnings_found+=1))
  fi

  default_sc_count="$(count_default_storageclasses)"
  if (( default_sc_count > 0 )); then
    warn "The cluster already has ${default_sc_count} default StorageClass(es)."
    track_warning "Longhorn: cluster already has ${default_sc_count} default StorageClass(es)"
    ((warnings_found+=1))
  fi

  confirm_preflight "Longhorn" "$warnings_found"
}

preflight_rancher_install() {
  local rancher_host="$1"
  local conflicts=""
  local warnings_found=0

  if ! service_active k3s; then
    warn "k3s is not active, so Rancher preflight can only be partial."
    track_warning "Rancher: k3s is not active, preflight is partial"
    ((warnings_found+=1))
    confirm_preflight "Rancher" "$warnings_found"
    return
  fi

  if namespace_exists cattle-system && namespace_has_user_resources cattle-system; then
    warn "Namespace 'cattle-system' already contains resources, but Rancher release was not detected."
    track_warning "Rancher: cattle-system namespace already has resources"
    ((warnings_found+=1))
  fi

  conflicts="$(find_ingress_host_conflicts "$rancher_host" "cattle-system" "rancher")"
  if [[ -n "$conflicts" ]]; then
    warn "Hostname '${rancher_host}' is already used by these ingress resources:"
    printf '%s\n' "$conflicts"
    track_warning "Rancher: hostname '${rancher_host}' already used by other ingress resources"
    ((warnings_found+=1))
  fi

  confirm_preflight "Rancher" "$warnings_found"
}

preflight_registry_install() {
  local registry_host="$1"
  local registry_storage_class="$2"
  local conflicts=""
  local warnings_found=0

  if ! service_active k3s; then
    warn "k3s is not active, so registry preflight can only be partial."
    track_warning "Registry: k3s is not active, preflight is partial"
    ((warnings_found+=1))
    confirm_preflight "Registry" "$warnings_found"
    return
  fi

  if namespace_exists registry && namespace_has_user_resources registry; then
    warn "Namespace 'registry' already contains resources, but the registry release was not detected."
    track_warning "Registry: registry namespace already has resources"
    ((warnings_found+=1))
  fi

  conflicts="$(find_ingress_host_conflicts "$registry_host" "registry" "registry")"
  if [[ -n "$conflicts" ]]; then
    warn "Hostname '${registry_host}' is already used by these ingress resources:"
    printf '%s\n' "$conflicts"
    track_warning "Registry: hostname '${registry_host}' already used by other ingress resources"
    ((warnings_found+=1))
  fi

  if [[ -n "$registry_storage_class" ]] && ! storageclass_exists "$registry_storage_class"; then
    warn "Requested StorageClass '${registry_storage_class}' does not exist."
    track_warning "Registry: storageclass '${registry_storage_class}' does not exist"
    ((warnings_found+=1))
  fi

  confirm_preflight "Registry" "$warnings_found"
}

preflight_nfs_install() {
  local export_path="$1"
  local allowed_network="$2"
  local warnings_found=0

  if [[ -e "$export_path" && ! -d "$export_path" ]]; then
    warn "NFS export path '${export_path}' exists and is not a directory."
    track_warning "NFS: export path '${export_path}' exists and is not a directory"
    ((warnings_found+=1))
  fi

  if nfs_export_exists "$export_path"; then
    warn "NFS export path '${export_path}' is already present in /etc/exports."
    track_warning "NFS: export path '${export_path}' already exists in /etc/exports"
    ((warnings_found+=1))
  fi

  if ! nfs_network_looks_valid "$allowed_network"; then
    warn "Allowed network '${allowed_network}' contains spaces or is malformed."
    track_warning "NFS: allowed network '${allowed_network}' looks malformed"
    ((warnings_found+=1))
  fi

  confirm_preflight "NFS" "$warnings_found"
}

install_k3s_if_needed() {
  local action="$1"
  if [[ "$action" == "reuse" ]]; then
    if [[ "$MODE" == "agent" ]]; then
      track_reuse "k3s agent"
    else
      track_reuse "k3s"
    fi
    manifest_complete_component "k3s" "$(result_for_mode reused)"
    return
  fi
  if [[ "$action" != "install" ]]; then
    err "k3s is required for the remaining steps."
    exit 1
  fi

  local install_label="k3s"
  if [[ "$MODE" == "agent" ]]; then
    install_label="k3s agent"
  fi

  track_install "$install_label"
  ensure_packages "k3s installation" curl ca-certificates
  if [[ "$PRODUCTIVE_K3S_ENGINE" == "k3sup" ]]; then
    install_k3sup_if_needed
    install_k3s_with_k3sup
  else
    install_k3s_with_native
  fi
  manifest_complete_component "k3s" "$(result_for_mode installed)"
}

install_k3sup_if_needed() {
  if need_cmd k3sup; then
    return 0
  fi

  log "Installing k3sup..."
  run_shell "Downloading k3sup installer" "curl -sLS https://get.k3sup.dev | sh"
  run_shell "Installing k3sup into /usr/local/bin" "sudo install k3sup /usr/local/bin/"
}

install_k3s_with_native() {
  if [[ "$MODE" == "agent" ]]; then
    if [[ -z "${AGENT_SERVER_URL:-}" || -z "${AGENT_CLUSTER_TOKEN:-}" ]]; then
      err "Agent mode requires both the server URL and cluster token."
      exit 1
    fi
    local install_cmd=""
    printf -v install_cmd 'curl -sfL https://get.k3s.io | K3S_URL=%q K3S_TOKEN=%q INSTALL_K3S_EXEC=agent INSTALL_K3S_VERSION=%q sh -' "$AGENT_SERVER_URL" "$AGENT_CLUSTER_TOKEN" "${PRODUCTIVE_K3S_K3S_VERSION}"
    log "Installing k3s agent..."
    run_shell "Installing k3s agent" "$install_cmd"
    return
  fi

  log "Installing k3s (${PRODUCTIVE_K3S_K3S_VERSION})..."
  run_shell "Installing k3s (${PRODUCTIVE_K3S_K3S_VERSION})" "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${PRODUCTIVE_K3S_K3S_VERSION} sh -"
}

k3sup_ssh_args() {
  local args=()

  if [[ -n "$PRODUCTIVE_K3S_SSH_KEY_PATH" ]]; then
    args+=("--ssh-key" "$PRODUCTIVE_K3S_SSH_KEY_PATH")
  fi
  if [[ -n "$PRODUCTIVE_K3S_SSH_PORT" ]]; then
    args+=("--ssh-port" "$PRODUCTIVE_K3S_SSH_PORT")
  fi

  printf '%s\0' "${args[@]}"
}

k3sup_remote_target_args() {
  local target_flag="${1:---host}"
  local host="${2:-$PRODUCTIVE_K3S_SSH_HOST}"
  local user="${3:-$PRODUCTIVE_K3S_SSH_USER}"
  local -a args=()

  [[ -n "$host" ]] || {
    err "k3sup engine requires PRODUCTIVE_K3S_SSH_HOST for remote apply modes."
    exit 1
  }
  [[ -n "$user" ]] || {
    err "k3sup engine requires PRODUCTIVE_K3S_SSH_USER for remote apply modes."
    exit 1
  }

  args+=("$target_flag" "$host" "--user" "$user")
  while IFS= read -r -d '' arg; do
    args+=("$arg")
  done < <(k3sup_ssh_args)

  printf '%q ' "${args[@]}"
}

install_k3s_with_k3sup() {
  local install_cmd=""

  case "$MODE" in
    single-node|server)
      log "Installing k3s with k3sup..."
      run_shell "Creating ${HOME}/.kube for k3sup kubeconfig output" "mkdir -p ${HOME}/.kube"
      printf -v install_cmd 'k3sup install --local --local-path %q --context %q --k3s-version %q' "${HOME}/.kube/k3sup-${MODE}.yaml" "productive-k3s-${MODE}" "${PRODUCTIVE_K3S_K3S_VERSION}"
      run_shell "Installing k3s with k3sup" "$install_cmd"
      ;;
    agent)
      [[ -n "${AGENT_SERVER_URL:-}" ]] || {
        err "Agent mode requires both the server URL and cluster token."
        exit 1
      }
      [[ -n "${AGENT_CLUSTER_TOKEN:-}" ]] || {
        err "Agent mode requires both the server URL and cluster token."
        exit 1
      }
      local server_host="${AGENT_SERVER_URL#https://}"
      server_host="${server_host%%:*}"
      [[ -n "$server_host" ]] || {
        err "Could not derive a server host from AGENT_SERVER_URL for k3sup."
        exit 1
      }

      printf -v install_cmd 'k3sup join %s --server-ip %q --server-user %q --k3s-version %q' \
        "$(k3sup_remote_target_args --ip "$PRODUCTIVE_K3S_SSH_HOST" "$PRODUCTIVE_K3S_SSH_USER")" \
        "$server_host" \
        "${PRODUCTIVE_K3S_SSH_USER}" \
        "${PRODUCTIVE_K3S_K3S_VERSION}"
      log "Joining k3s agent with k3sup..."
      run_shell "Joining k3s agent with k3sup" "$install_cmd"
      ;;
    *)
      err "k3sup engine is not supported for mode '${MODE}'."
      exit 1
      ;;
  esac
}

install_helm_if_needed() {
  local action="$1"
  if [[ "$action" == "reuse" ]]; then
    track_reuse "helm"
    manifest_complete_component "helm" "$(result_for_mode reused)"
    return
  fi
  if [[ "$action" != "install" ]]; then
    err "Cannot continue without Helm."
    exit 1
  fi

  track_install "helm"
  ensure_packages "Helm installation" curl ca-certificates
  log "Installing Helm (${PRODUCTIVE_K3S_HELM_VERSION})..."
  run_shell "Installing Helm (${PRODUCTIVE_K3S_HELM_VERSION})" "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=${PRODUCTIVE_K3S_HELM_VERSION} bash"
  manifest_complete_component "helm" "$(result_for_mode installed)"
}

clusterissuer_action() {
  if [[ "${MANIFEST_PLANNED["clusterissuer"]:-skip}" != "ensure" ]]; then
    printf '%s\n' "skip"
  elif [[ "${MANIFEST_DETECTED["clusterissuer"]:-missing}" == "present" ]]; then
    printf '%s\n' "reuse"
  else
    printf '%s\n' "install"
  fi
}

stack_install_order_addons() {
  if ! stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    err "Stack source '${PRODUCTIVE_K3S_STACK_NAME}' was not found. Set PRODUCTIVE_K3S_ADDONS_REPO_DIR or place productive-k3s-addons beside productive-k3s-core."
    exit 1
  fi

  stack_source_addon_names "${PRODUCTIVE_K3S_STACK_NAME}"
}

write_addon_config_var() {
  local output_file="$1"
  local key="$2"
  local value="$3"
  printf '%s=%q\n' "${key}" "${value}" >> "${output_file}"
}

apply_addon_config_file() {
  local config_file="$1"
  [[ -s "${config_file}" ]] || return 0
  # shellcheck source=/dev/null
  source "${config_file}"
}

run_addon_source_configure_hook() {
  local addon_name="$1"
  local phase="$2"
  local output_file="$3"

  if ! addon_source_script_exists "${addon_name}" configure.sh; then
    err "Addon '${addon_name}' does not provide scripts/configure.sh"
    exit 1
  fi

  : > "${output_file}"
  if ! run_addon_source_hook "${addon_name}" configure.sh pk3s_addon_configure "${phase}" "${output_file}"; then
    err "Addon '${addon_name}' configure hook 'pk3s_addon_configure' is missing."
    exit 1
  fi
}

install_stack_addon_by_name() {
  local addon_name="$1"
  local component_key
  component_key="$(addon_component_key "${addon_name}")"
  CURRENT_STEP="${component_key}"
  log "Processing stack addon '${addon_name}' from stack '${PRODUCTIVE_K3S_STACK_NAME}'"

  case "${addon_name}" in
    cert-manager)
      ensure_cert_manager \
        "$cert_manager_present" \
        "$CERT_MANAGER_ACTION" \
        "$(clusterissuer_action)" \
        "$TLS_CHOICE" \
        "$ISSUER_NAME" \
        "$LE_EMAIL" \
        "$LE_ENV"
      ;;
    longhorn)
      install_longhorn_if_needed \
        "$longhorn_present" \
        "$LONGHORN_ACTION" \
        "$LONGHORN_DATA_PATH" \
        "$LONGHORN_REPLICA_COUNT" \
        "$LONGHORN_MINIMAL_AVAILABLE_PERCENTAGE" \
        "$SINGLE_NODE_LONGHORN_MODE"
      ;;
    rancher)
      install_rancher_if_needed \
        "$rancher_present" \
        "$RANCHER_ACTION" \
        "$TLS_CHOICE" \
        "$ISSUER_NAME" \
        "$RANCHER_HOST" \
        "$ADMIN_PASS" \
        "$LE_EMAIL" \
        "$LE_ENV"
      ;;
    registry)
      install_registry_if_needed \
        "$registry_present" \
        "$REGISTRY_ACTION" \
        "$TLS_CHOICE" \
        "$ISSUER_NAME" \
        "$REGISTRY_HOST" \
        "$REGISTRY_SIZE" \
        "$REGISTRY_STORAGE_CLASS" \
        "$REGISTRY_AUTH_ENABLED" \
        "$REGISTRY_AUTH_USER" \
        "$REGISTRY_AUTH_PASSWORD"
      ;;
    *)
      warn "Stack '${PRODUCTIVE_K3S_STACK_NAME}' references unsupported addon '${addon_name}'. Skipping."
      ;;
  esac
}

ensure_cert_manager() {
  local cert_manager_present="$1"
  local action="$2"
  local issuer_action="$3"
  local tls_choice="$4"
  local issuer_name="$5"
  local le_email="$6"
  local le_env="$7"

  if [[ "$action" == "reuse" && "$cert_manager_present" == "y" ]]; then
    track_reuse "cert-manager"
    manifest_complete_component "cert_manager" "$(result_for_mode reused)"
  elif [[ "$action" != "install" ]]; then
    if [[ "$issuer_action" == "install" ]]; then
      err "Skipping cert-manager would leave TLS-dependent installs unsupported."
      exit 1
    fi
    track_skip "cert-manager: user chose not to install"
    manifest_complete_component "cert_manager" "skipped"
  else
    track_install "cert-manager"
    preflight_cert_manager_install || exit 1
    if ! addon_source_script_exists cert-manager install.sh; then
      err "Addon source for cert-manager is required but scripts/install.sh was not found."
      exit 1
    fi
    log "Installing cert-manager from addon source..."
    if ! PK3S_KUBECTL_MODE="k3s" \
      PK3S_CERT_MANAGER_VERSION="${PRODUCTIVE_K3S_CERT_MANAGER_VERSION}" \
      PK3S_CLUSTER_ISSUER_ACTION="${issuer_action}" \
      PK3S_TLS_SOURCE="$( [[ "${tls_choice}" == "1" ]] && echo letsencrypt || echo secret )" \
      PK3S_CLUSTER_ISSUER="${issuer_name}" \
      PK3S_LETSENCRYPT_EMAIL="${le_email}" \
      PK3S_LETSENCRYPT_ENVIRONMENT="${le_env}" \
      run_addon_source_hook cert-manager install.sh pk3s_addon_install; then
      err "Addon source for cert-manager must define pk3s_addon_install."
      exit 1
    fi
    manifest_complete_component "cert_manager" "$(result_for_mode installed)"
  fi

  case "${issuer_action}" in
    reuse)
      track_reuse "clusterissuer/${issuer_name}"
      manifest_complete_component "clusterissuer" "$(result_for_mode reused)" "$issuer_name"
      ;;
    install)
      track_install "clusterissuer/${issuer_name}"
      manifest_complete_component "clusterissuer" "$(result_for_mode installed)" "$issuer_name"
      ;;
    *)
      manifest_complete_component "clusterissuer" "skipped"
      ;;
  esac
}

install_longhorn_if_needed() {
  local longhorn_present="$1"
  local action="$2"
  local longhorn_data_path="$3"
  local replica_count="$4"
  local minimal_available_pct="$5"
  local single_node_mode="$6"

  if [[ "$action" == "reuse" && "$longhorn_present" == "y" ]]; then
    track_reuse "Longhorn"
    manifest_complete_component "longhorn" "$(result_for_mode reused)"
    return
  fi

  if [[ "$action" != "install" ]]; then
    warn "Longhorn will not be installed."
    track_skip "Longhorn: user chose not to install"
    manifest_complete_component "longhorn" "skipped"
    return
  fi

  track_install "Longhorn"
  preflight_longhorn_install "$longhorn_data_path" || return
  ensure_packages "Longhorn" open-iscsi jq
  ensure_iscsid
  warn "Longhorn storage path '${longhorn_data_path}' will be created if missing."
  warn "This script will not format or mount disks. Prepare dedicated mounted storage yourself if you need it."
  run_cmd "Ensuring directory ${longhorn_data_path} exists" sudo mkdir -p "$longhorn_data_path"

  if ! addon_source_script_exists longhorn install.sh; then
    err "Addon source for longhorn is required but scripts/install.sh was not found."
    exit 1
  fi
  log "Installing Longhorn from addon source..."
  if ! PK3S_KUBECTL_MODE="k3s" \
    PK3S_HELM_BIN="helm" \
    PK3S_LONGHORN_VERSION="${PRODUCTIVE_K3S_LONGHORN_VERSION}" \
    PK3S_LONGHORN_DATA_PATH="${longhorn_data_path}" \
    PK3S_LONGHORN_REPLICA_COUNT="${replica_count}" \
    PK3S_LONGHORN_SINGLE_NODE_MODE="${single_node_mode}" \
    PK3S_LONGHORN_MINIMAL_AVAILABLE_PERCENTAGE="${minimal_available_pct}" \
    PK3S_LONGHORN_MAKE_DEFAULT="${LONGHORN_MAKE_DEFAULT:-n}" \
    run_addon_source_hook longhorn install.sh pk3s_addon_install; then
    err "Addon source for longhorn must define pk3s_addon_install."
    exit 1
  fi
  manifest_complete_component "longhorn" "$(result_for_mode installed)"
}

install_rancher_if_needed() {
  local rancher_present="$1"
  local action="$2"
  local tls_choice="$3"
  local issuer_name="$4"
  local rancher_host="$5"
  local admin_pass="$6"
  local le_email="$7"
  local le_env="$8"

  if [[ "$action" == "reuse" && "$rancher_present" == "y" ]]; then
    track_reuse "Rancher"
    manifest_complete_component "rancher" "$(result_for_mode reused)"
    return
  fi

  if [[ "$action" != "install" ]]; then
    warn "Rancher will not be installed."
    track_skip "Rancher: user chose not to install"
    manifest_complete_component "rancher" "skipped"
    return
  fi

  track_install "Rancher"
  preflight_rancher_install "$rancher_host" || return
  if ! addon_source_script_exists rancher install.sh; then
    err "Addon source for rancher is required but scripts/install.sh was not found."
    exit 1
  fi
  log "Installing Rancher from addon source..."
  if ! PK3S_KUBECTL_MODE="k3s" \
    PK3S_HELM_BIN="helm" \
    PK3S_RANCHER_VERSION="${PRODUCTIVE_K3S_RANCHER_VERSION}" \
    PK3S_RANCHER_HOST="${rancher_host}" \
    PK3S_RANCHER_BOOTSTRAP_PASSWORD="${admin_pass}" \
    PK3S_TLS_SOURCE="$( [[ "${tls_choice}" == "1" ]] && echo letsencrypt || echo secret )" \
    PK3S_CLUSTER_ISSUER="${issuer_name}" \
    PK3S_LETSENCRYPT_EMAIL="${le_email}" \
    PK3S_LETSENCRYPT_ENVIRONMENT="${le_env}" \
    run_addon_source_hook rancher install.sh pk3s_addon_install; then
    err "Addon source for rancher must define pk3s_addon_install."
    exit 1
  fi
  manifest_complete_component "rancher" "$(result_for_mode installed)"
}

install_registry_if_needed() {
  local registry_present="$1"
  local action="$2"
  local tls_choice="$3"
  local issuer_name="$4"
  local registry_host="$5"
  local registry_size="$6"
  local registry_storage_class="$7"
  local registry_auth_enabled="$8"
  local registry_auth_user="$9"
  local registry_auth_password="${10}"

  if [[ "$action" == "reuse" && "$registry_present" == "y" ]]; then
    track_reuse "Registry"
    manifest_complete_component "registry" "$(result_for_mode reused)"
    return
  fi

  if [[ "$action" != "install" ]]; then
    warn "Registry will not be installed."
    track_skip "Registry: user chose not to install"
    manifest_complete_component "registry" "skipped"
    return
  fi

  track_install "Registry"
  preflight_registry_install "$registry_host" "$registry_storage_class" || return
  if ! addon_source_script_exists registry install.sh; then
    err "Addon source for registry is required but scripts/install.sh was not found."
    exit 1
  fi
  log "Installing Registry from addon source..."
  if ! PK3S_KUBECTL_MODE="k3s" \
    PK3S_REGISTRY_IMAGE="${PRODUCTIVE_K3S_REGISTRY_IMAGE}" \
    PK3S_REGISTRY_HOST="${registry_host}" \
    PK3S_REGISTRY_PVC_SIZE="${registry_size}" \
    PK3S_REGISTRY_STORAGE_CLASS="${registry_storage_class}" \
    PK3S_TLS_SOURCE="$( [[ "${tls_choice}" == "1" ]] && echo letsencrypt || echo secret )" \
    PK3S_CLUSTER_ISSUER="${issuer_name}" \
    PK3S_REGISTRY_AUTH_ENABLED="${registry_auth_enabled}" \
    PK3S_REGISTRY_AUTH_USER="${registry_auth_user}" \
    PK3S_REGISTRY_AUTH_PASSWORD="${registry_auth_password}" \
    run_addon_source_hook registry install.sh pk3s_addon_install; then
    err "Addon source for registry must define pk3s_addon_install."
    exit 1
  fi
  manifest_complete_component "registry" "$(result_for_mode installed)"
}

install_nfs_if_needed() {
  local nfs_present="$1"
  local nfs_export_present="$2"
  local action="$3"
  local export_path="$4"
  local allowed_network="$5"
  local service_name
  service_name="$(nfs_service_name)"

  if ! nfs_path_looks_valid "$export_path"; then
    err "NFS export path '${export_path}' is invalid. It must be an absolute path."
    exit 1
  fi

  if ! nfs_network_looks_valid "$allowed_network"; then
    err "Allowed client network '${allowed_network}' is invalid."
    exit 1
  fi

  if [[ "$action" == "reuse" && "$nfs_present" == "y" && "$nfs_export_present" == "y" ]]; then
      track_reuse "NFS server"
      track_reuse "NFS export ${export_path}"
      manifest_complete_component "nfs" "$(result_for_mode reused)" "${export_path} ${allowed_network}"
      return
  fi

  if [[ "$action" == "add-export" && "$nfs_present" == "y" && "$nfs_export_present" != "y" ]]; then
    track_reuse "NFS server"
    track_install "NFS export ${export_path} (${allowed_network})"
    preflight_nfs_install "$export_path" "$allowed_network" || return
  elif [[ "$action" == "install" ]]; then
    track_install "NFS server"
    track_install "NFS export ${export_path} (${allowed_network})"
    preflight_nfs_install "$export_path" "$allowed_network" || return
    ensure_packages "NFS server" nfs-kernel-server
    run_cmd "Enabling and starting ${service_name}" sudo systemctl enable --now "$service_name"
  else
    track_skip "NFS: user chose not to manage NFS"
    manifest_complete_component "nfs" "skipped"
    return
  fi

  run_cmd "Creating NFS export directory ${export_path}" sudo mkdir -p "$export_path"

  if nfs_export_exists "$export_path"; then
    log "NFS export for ${export_path} already exists in /etc/exports. Leaving it untouched."
  else
    local export_line="${export_path} ${allowed_network}(rw,sync,no_subtree_check)"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[dry-run] Adding NFS export to /etc/exports"
      echo "  ${export_line}"
    else
      log "Adding NFS export to /etc/exports..."
      echo "${export_line}" | sudo tee -a /etc/exports >/dev/null
    fi
  fi

  run_cmd "Reloading NFS exports" sudo exportfs -ra
  manifest_complete_component "nfs" "$(result_for_mode configured)" "${export_path} ${allowed_network}"
}

main() {
  validate_k3s_engine
  parse_args "$@"
  init_run_manifest
  trap cleanup_exit EXIT
  detect_host_platform
  bind_stdin_to_tty
  resolve_telemetry_enabled
  TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-${RUN_ID}}"
  sudo_keepalive
  emit_bootstrap_lifecycle_event "started" "started"

  log "Detected host platform: ${OS_PRETTY_NAME}"
  case "$PLATFORM_SUPPORT" in
    supported)
      ;;
    *)
      warn "Platform support: unsupported. Supported platforms are Ubuntu, Debian 12, and Debian 13."
      ;;
  esac

  local mode_label
  mode_label="$(mode_description)"
  if [[ "$DRY_RUN" == "1" ]]; then
    mode_label="dry-run ${mode_label}"
  fi

  log "Incremental apply: k3s + Rancher + Longhorn + Registry (${OS_PRETTY_NAME})"
  log "Mode: ${MODE} (${mode_label})"
  log "k3s installation engine: ${PRODUCTIVE_K3S_ENGINE}"
  line "  Run manifest: ${RUN_MANIFEST}"
  if [[ "$DRY_RUN" == "1" ]]; then
    warn "Running in dry-run mode. No changes will be applied."
  fi
  manifest_set_setting "bootstrap_mode" "$MODE"
  manifest_set_setting "k3s_installation_engine" "$PRODUCTIVE_K3S_ENGINE"
  manifest_set_setting "telemetry_enabled" "$(is_truthy "${TELEMETRY_ENABLED:-false}" && printf 'y' || printf 'n')"
  manifest_set_setting "telemetry_max_retries" "${TELEMETRY_MAX_RETRIES}"
  local k3s_detected_state="missing"
  local helm_detected_state="missing"

  if k3s_component_active; then
    k3s_detected_state="present"
  fi
  if need_cmd helm; then
    helm_detected_state="present"
  elif [[ "$MODE" == "agent" ]]; then
    helm_detected_state="not-needed"
  fi

  if [[ "$MODE" == "agent" ]] && k3s_server_active; then
    err "Agent mode cannot be used on a node where the k3s server service is already active."
    exit 1
  fi

  local cert_manager_present="n"
  local longhorn_present="n"
  local rancher_present="n"
  local registry_present="n"
  local nfs_present="n"
  local nfs_export_present="n"

  if deployment_exists cert-manager cert-manager; then
    cert_manager_present="y"
  fi
  if helm_release_exists longhorn longhorn-system || deployment_exists longhorn-system longhorn-driver-deployer; then
    longhorn_present="y"
  fi
  if helm_release_exists rancher cattle-system || deployment_exists cattle-system rancher; then
    rancher_present="y"
  fi
  if helm_release_exists registry registry || deployment_exists registry registry || secret_exists registry registry-tls || get_first_ingress_host registry registry | grep -q .; then
    registry_present="y"
  fi
  if pkg_installed nfs-kernel-server || nfs_server_active; then
    nfs_present="y"
  fi

  local rancher_existing_host=""
  local registry_existing_host=""
  rancher_existing_host="$(get_first_ingress_host cattle-system rancher)"
  registry_existing_host="$(get_first_ingress_host registry registry)"

  manifest_record_component "k3s" "$k3s_detected_state" "pending"
  manifest_record_component "helm" "$helm_detected_state" "pending"
  manifest_record_component "cert_manager" "$( [[ "$cert_manager_present" == "y" ]] && echo present || echo missing )" "pending"
  manifest_record_component "longhorn" "$( [[ "$longhorn_present" == "y" ]] && echo present || echo missing )" "pending"
  manifest_record_component "rancher" "$( [[ "$rancher_present" == "y" ]] && echo present || echo missing )" "pending"
  manifest_record_component "registry" "$( [[ "$registry_present" == "y" ]] && echo present || echo missing )" "pending"

  print_detection_summary \
    "$k3s_detected_state" \
    "$helm_detected_state" \
    "$( [[ "$cert_manager_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$longhorn_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$rancher_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$registry_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$nfs_present" == "y" ]] && echo present || echo missing )"
  if need_cmd kubectl; then
    log "Standalone kubectl detected. The managed workflow in this repository still uses 'sudo k3s kubectl' by default."
  else
    log "Standalone kubectl was not detected. That is fine: this repository uses 'sudo k3s kubectl' for managed operations."
  fi
  print_diagnosis_summary \
    "$k3s_detected_state" \
    "$helm_detected_state" \
    "$( [[ "$cert_manager_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$longhorn_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$rancher_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$registry_present" == "y" ]] && echo present || echo missing )" \
    "$( [[ "$nfs_present" == "y" ]] && echo present || echo missing )"

  local DEFAULT_DOMAIN="example.local"
  local DOMAIN="$DEFAULT_DOMAIN"
  local RANCHER_HOST="${rancher_existing_host:-rancher.${DEFAULT_DOMAIN}}"
  local REGISTRY_HOST="${registry_existing_host:-registry.${DEFAULT_DOMAIN}}"
  local ADMIN_PASS="admin"
  local REGISTRY_SIZE="20Gi"
  local LONGHORN_REPLICA_COUNT="1"
  local LONGHORN_MINIMAL_AVAILABLE_PERCENTAGE="10"
  local LONGHORN_DATA_PATH="/data"
  local LONGHORN_MAKE_DEFAULT="n"
  local REGISTRY_STORAGE_CLASS=""
  local TLS_CHOICE="2"
  local LE_EMAIL="you@example.com"
  local LE_ENV="staging"
  local ISSUER_NAME="selfsigned"
  local NFS_EXPORT_PATH="/srv/nfs/k8s-share"
  local NFS_ALLOWED_NETWORK="192.168.0.0/24"
  local MANAGE_LOCAL_HOSTS="y"
  local TRUST_REGISTRY_IN_DOCKER="n"
  local REGISTRY_AUTH_ENABLED="n"
  local REGISTRY_AUTH_USER="registry"
  local REGISTRY_AUTH_PASSWORD="change-me"
  local NODE_IP
  NODE_IP="$(get_primary_node_ip)"
  local CLUSTER_NODE_COUNT
  CLUSTER_NODE_COUNT="$(cluster_node_count)"
  local SINGLE_NODE_LONGHORN_MODE="n"
  if mode_uses_single_node_defaults && [[ "$CLUSTER_NODE_COUNT" == "1" || "$CLUSTER_NODE_COUNT" == "0" ]]; then
    SINGLE_NODE_LONGHORN_MODE="y"
  fi

  local K3S_ACTION="reuse"
  local HELM_ACTION="reuse"
  local CERT_MANAGER_ACTION="skip"
  local LONGHORN_ACTION="reuse"
  local RANCHER_ACTION="reuse"
  local REGISTRY_ACTION="reuse"
  local NFS_ACTION="skip"

  if mode_runs_base || [[ "$MODE" == "agent" ]]; then
    if [[ "$MODE" == "agent" ]]; then
      if k3s_agent_active; then
        prompt_yesno CONTINUE_K3S_AGENT "y" "Existing k3s agent installation detected. Continue using it without changes? [required]"
        [[ "$CONTINUE_K3S_AGENT" == "y" ]] || { err "k3s agent is required for agent mode."; exit 1; }
        K3S_ACTION="reuse"
      else
        prompt_yesno INSTALL_K3S_AGENT "y" "k3s agent was not detected. Install it now? [required]"
        [[ "$INSTALL_K3S_AGENT" == "y" ]] || { err "Cannot continue without k3s agent."; exit 1; }
        K3S_ACTION="install"
        prompt AGENT_SERVER_URL "https://server.example.local:6443" "Agent server URL"
        prompt AGENT_CLUSTER_TOKEN "change-me-token" "Agent cluster token"
        [[ -n "$AGENT_SERVER_URL" ]] || { err "Agent server URL cannot be empty."; exit 1; }
        [[ -n "$AGENT_CLUSTER_TOKEN" ]] || { err "Agent cluster token cannot be empty."; exit 1; }
      fi
      HELM_ACTION="skip"
      MANIFEST_RESULT["helm"]="skipped"
    else
      if k3s_server_active; then
        prompt_yesno CONTINUE_K3S "y" "Existing k3s installation detected. Continue using it without changes? [required]"
        [[ "$CONTINUE_K3S" == "y" ]] || { err "k3s is required for the remaining steps."; exit 1; }
        K3S_ACTION="reuse"
      else
        prompt_yesno INSTALL_K3S "y" "k3s was not detected. Install it now? [required]"
        [[ "$INSTALL_K3S" == "y" ]] || { err "Cannot continue without k3s."; exit 1; }
        K3S_ACTION="install"
      fi

      if need_cmd helm; then
        prompt_yesno CONTINUE_HELM "y" "Helm is already installed. Continue using it without changes? [required]"
        [[ "$CONTINUE_HELM" == "y" ]] || { err "Helm is required for chart-based installs."; exit 1; }
        HELM_ACTION="reuse"
      else
        prompt_yesno INSTALL_HELM "y" "Helm was not detected. Install it now? [required]"
        [[ "$INSTALL_HELM" == "y" ]] || { err "Cannot continue without Helm."; exit 1; }
        HELM_ACTION="install"
      fi
    fi
  else
    if ! k3s_server_active; then
      err "Mode '${MODE}' requires an existing k3s cluster."
      exit 1
    fi
    if ! need_cmd helm; then
      err "Mode '${MODE}' requires Helm to be installed already."
      exit 1
    fi
    K3S_ACTION="reuse"
    HELM_ACTION="reuse"
  fi

  local addon_config_file
  addon_config_file="$(mktemp)"

  if mode_runs_stack; then
    PK3S_ADDON_PRESENT="$longhorn_present" run_addon_source_configure_hook "longhorn" "action" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"

    PK3S_ADDON_PRESENT="$rancher_present" run_addon_source_configure_hook "rancher" "action" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"

    PK3S_ADDON_PRESENT="$registry_present" run_addon_source_configure_hook "registry" "action" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"

    PK3S_ADDON_PRESENT="$cert_manager_present" PK3S_CERT_MANAGER_REQUIRED="$( [[ "$RANCHER_ACTION" == "install" || "$REGISTRY_ACTION" == "install" ]] && echo y || echo n )" \
      run_addon_source_configure_hook "cert-manager" "action" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"
    [[ "${CERT_MANAGER_ACTION}" != "skip" ]] || MANIFEST_RESULT["cert_manager"]="skipped"
  else
    CERT_MANAGER_ACTION="skip"
    LONGHORN_ACTION="skip"
    RANCHER_ACTION="skip"
    REGISTRY_ACTION="skip"
    MANIFEST_RESULT["cert_manager"]="skipped"
    MANIFEST_RESULT["longhorn"]="skipped"
    MANIFEST_RESULT["rancher"]="skipped"
    MANIFEST_RESULT["registry"]="skipped"
  fi

  local ENABLE_NFS="n"
  if mode_runs_host_local; then
    prompt_yesno ENABLE_NFS "y" "Do you want to ensure a local NFS server is available for host-to-cluster shared files? [optional]"
    if [[ "$ENABLE_NFS" == "y" ]]; then
      if nfs_export_exists "$NFS_EXPORT_PATH"; then
        nfs_export_present="y"
      fi

      if [[ "$nfs_present" == "y" && "$nfs_export_present" == "y" ]]; then
        prompt_yesno REUSE_EXISTING_NFS "y" "NFS server and export are already present. Leave them unchanged and continue?"
        if [[ "$REUSE_EXISTING_NFS" == "y" ]]; then
          NFS_ACTION="reuse"
        else
          prompt NFS_EXPORT_PATH "$NFS_EXPORT_PATH" "NFS export path on the host"
          prompt NFS_ALLOWED_NETWORK "$NFS_ALLOWED_NETWORK" "Allowed client network/CIDR for the NFS export"
          if nfs_export_exists "$NFS_EXPORT_PATH"; then
            nfs_export_present="y"
            NFS_ACTION="reuse"
          else
            nfs_export_present="n"
            NFS_ACTION="add-export"
          fi
        fi
      else
        prompt NFS_EXPORT_PATH "$NFS_EXPORT_PATH" "NFS export path on the host"
        prompt NFS_ALLOWED_NETWORK "$NFS_ALLOWED_NETWORK" "Allowed client network/CIDR for the NFS export"
        if nfs_export_exists "$NFS_EXPORT_PATH"; then
          nfs_export_present="y"
        fi
        if [[ "$nfs_present" == "y" && "$nfs_export_present" == "y" ]]; then
          NFS_ACTION="reuse"
        elif [[ "$nfs_present" == "y" ]]; then
          NFS_ACTION="add-export"
        else
          NFS_ACTION="install"
        fi
      fi
    else
      track_skip "NFS: user chose not to manage NFS"
    fi
  else
    NFS_ACTION="skip"
    MANIFEST_RESULT["nfs"]="skipped"
  fi

  if [[ "$nfs_present" == "y" && "$nfs_export_present" == "y" ]]; then
    manifest_record_component "nfs" "present-with-export" "$NFS_ACTION"
  elif [[ "$nfs_present" == "y" ]]; then
    manifest_record_component "nfs" "present-without-export" "$NFS_ACTION"
  else
    manifest_record_component "nfs" "missing" "$NFS_ACTION"
  fi

  if mode_runs_host_local; then
    prompt_yesno MANAGE_LOCAL_HOSTS "y" "Do you want this script to add/update local /etc/hosts entries for Rancher and Registry on this machine? [optional]"
  else
    MANAGE_LOCAL_HOSTS="n"
  fi

  if mode_runs_stack && [[ "$RANCHER_ACTION" == "install" || "$REGISTRY_ACTION" == "install" ]]; then
    prompt DOMAIN "$DOMAIN" "Base domain (used to build hostnames)"

    echo
    echo "TLS options:"
    echo "  1) Let's Encrypt (requires public DNS + inbound 80/443)"
    echo "  2) Self-signed (works anywhere; you'll need to trust certs in browser/docker)"
    prompt TLS_CHOICE "$TLS_CHOICE" "Choose TLS mode (1/2)"
    if [[ "$TLS_CHOICE" == "1" ]]; then
      prompt LE_EMAIL "$LE_EMAIL" "Let's Encrypt email"
      prompt LE_ENV "$LE_ENV" "Let's Encrypt environment (staging/production)"
      ISSUER_NAME="letsencrypt-${LE_ENV}"
    fi
  fi

  if mode_runs_stack && [[ "$LONGHORN_ACTION" == "install" ]]; then
    if mode_uses_single_node_defaults && [[ "$SINGLE_NODE_LONGHORN_MODE" == "y" ]]; then
      LONGHORN_MAKE_DEFAULT="y"
    fi
    PK3S_SINGLE_NODE_LONGHORN_MODE="${SINGLE_NODE_LONGHORN_MODE}" run_addon_source_configure_hook "longhorn" "details" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"
  fi

  if mode_runs_stack && [[ "$RANCHER_ACTION" == "install" ]]; then
    RANCHER_HOST="${rancher_existing_host:-rancher.${DOMAIN}}"
    run_addon_source_configure_hook "rancher" "details" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"
  fi

  if mode_runs_stack && [[ "$REGISTRY_ACTION" == "install" ]]; then
    REGISTRY_HOST="${registry_existing_host:-registry.${DOMAIN}}"
    if mode_uses_single_node_defaults && [[ "$SINGLE_NODE_LONGHORN_MODE" == "y" ]]; then
      REGISTRY_STORAGE_CLASS="longhorn-single"
    elif storageclass_exists longhorn; then
      REGISTRY_STORAGE_CLASS="longhorn"
    fi
    run_addon_source_configure_hook "registry" "details" "${addon_config_file}"
    apply_addon_config_file "${addon_config_file}"
  fi

  if mode_runs_host_local && [[ "$TLS_CHOICE" == "2" ]]; then
    prompt_yesno TRUST_REGISTRY_IN_DOCKER "y" "Do you want this script to trust the registry certificate in local Docker on this machine? [optional]"
  fi

  manifest_set_setting "agent_server_url" "$AGENT_SERVER_URL"
  manifest_set_setting "agent_server_url_provided" "$( [[ -n "$AGENT_SERVER_URL" ]] && echo y || echo n )"
  manifest_set_setting "agent_cluster_token_provided" "$( [[ -n "$AGENT_CLUSTER_TOKEN" ]] && echo y || echo n )"
  manifest_set_setting "base_domain" "$DOMAIN"
  manifest_set_setting "rancher_host" "$RANCHER_HOST"
  manifest_set_setting "registry_host" "$REGISTRY_HOST"
  manifest_set_setting "tls_mode" "$( [[ "$TLS_CHOICE" == "1" ]] && echo letsencrypt || echo self-signed )"
  manifest_set_setting "letsencrypt_environment" "$LE_ENV"
  manifest_set_setting "longhorn_data_path" "$LONGHORN_DATA_PATH"
  manifest_set_setting "longhorn_replica_count" "$LONGHORN_REPLICA_COUNT"
  manifest_set_setting "longhorn_minimal_available_percentage" "$LONGHORN_MINIMAL_AVAILABLE_PERCENTAGE"
  manifest_set_setting "longhorn_single_node_mode" "$SINGLE_NODE_LONGHORN_MODE"
  manifest_set_setting "registry_pvc_size" "$REGISTRY_SIZE"
  manifest_set_setting "registry_storage_class" "$REGISTRY_STORAGE_CLASS"
  manifest_set_setting "registry_storage_class_configured" "$( [[ -n "$REGISTRY_STORAGE_CLASS" ]] && echo y || echo n )"
  manifest_set_setting "registry_auth_enabled" "$REGISTRY_AUTH_ENABLED"
  manifest_set_setting "nfs_manage" "$ENABLE_NFS"
  manifest_set_setting "nfs_export_path" "$NFS_EXPORT_PATH"
  manifest_set_setting "nfs_allowed_network" "$NFS_ALLOWED_NETWORK"
  manifest_set_setting "manage_local_hosts" "$MANAGE_LOCAL_HOSTS"
  manifest_set_setting "trust_registry_in_docker" "$TRUST_REGISTRY_IN_DOCKER"

  MANIFEST_PLANNED["k3s"]="$K3S_ACTION"
  MANIFEST_PLANNED["helm"]="$HELM_ACTION"
  MANIFEST_PLANNED["cert_manager"]="$CERT_MANAGER_ACTION"
  MANIFEST_PLANNED["longhorn"]="$LONGHORN_ACTION"
  MANIFEST_PLANNED["rancher"]="$RANCHER_ACTION"
  MANIFEST_PLANNED["registry"]="$REGISTRY_ACTION"
  MANIFEST_PLANNED["nfs"]="$NFS_ACTION"
  MANIFEST_DETECTED["local_hosts"]="unknown"
  MANIFEST_PLANNED["local_hosts"]="$( [[ "$MANAGE_LOCAL_HOSTS" == "y" ]] && echo update || echo skip )"
  MANIFEST_DETECTED["docker_registry_trust"]="unknown"
  MANIFEST_PLANNED["docker_registry_trust"]="$( [[ "$TLS_CHOICE" == "2" && "$TRUST_REGISTRY_IN_DOCKER" == "y" ]] && echo install || echo skip )"
  if mode_runs_stack && [[ "$RANCHER_ACTION" == "install" || "$REGISTRY_ACTION" == "install" ]]; then
    MANIFEST_DETECTED["clusterissuer"]="$( clusterissuer_exists "$ISSUER_NAME" && echo present || echo missing )"
    MANIFEST_PLANNED["clusterissuer"]="ensure"
  else
    MANIFEST_DETECTED["clusterissuer"]="not-needed"
    MANIFEST_PLANNED["clusterissuer"]="skip"
    MANIFEST_RESULT["clusterissuer"]="skipped"
  fi

  print_plan_summary \
    "$K3S_ACTION" \
    "$HELM_ACTION" \
    "$CERT_MANAGER_ACTION" \
    "$LONGHORN_ACTION" \
    "$RANCHER_ACTION" \
    "$REGISTRY_ACTION" \
    "$NFS_ACTION" \
    "$( [[ "$MANAGE_LOCAL_HOSTS" == "y" ]] && echo update || echo skip )" \
    "$( [[ "$TLS_CHOICE" == "2" && "$TRUST_REGISTRY_IN_DOCKER" == "y" ]] && echo install || echo skip )"

  prompt_yesno PROCEED_WITH_PLAN "y" "Proceed with this plan?"
  rm -f "${addon_config_file}"
  [[ "$PROCEED_WITH_PLAN" == "y" ]] || { RUN_STATUS="cancelled"; warn "Apply cancelled before applying changes."; exit 0; }
  exec </dev/null

  CURRENT_STEP="k3s"
  install_k3s_if_needed "$K3S_ACTION"
  if [[ "$MODE" != "agent" ]]; then
    CURRENT_STEP="helm"
    install_helm_if_needed "$HELM_ACTION"
  fi
  if [[ "$MODE" == "agent" ]]; then
    if k3s_agent_active; then
      log "k3s agent service is active."
    else
      warn "k3s agent is not active yet. Agent-level checks will be partial until it is installed for real."
    fi
  elif k3s_server_active; then
    wait_k3s_ready 180
    CURRENT_STEP="cluster-inspection"
    log "Inspecting k3s node..."
    kubectl_k3s get nodes -o wide
    ensure_user_kubeconfig
  else
    warn "k3s is not active yet. Cluster-level checks will be partial until it is installed for real."
  fi
  if mode_runs_stack; then
    local stack_addon_name
    local -a stack_addons=()
    mapfile -t stack_addons < <(stack_install_order_addons)
    for stack_addon_name in "${stack_addons[@]}"; do
      [[ -n "${stack_addon_name}" ]] || continue
      install_stack_addon_by_name "${stack_addon_name}"
    done
  fi
  if mode_runs_host_local && [[ "$ENABLE_NFS" == "y" ]]; then
    CURRENT_STEP="nfs"
    install_nfs_if_needed "$nfs_present" "$nfs_export_present" "$NFS_ACTION" "$NFS_EXPORT_PATH" "$NFS_ALLOWED_NETWORK"
  fi
  if mode_runs_host_local && [[ "$MANAGE_LOCAL_HOSTS" == "y" ]]; then
    CURRENT_STEP="local_hosts"
    ensure_local_hosts_entries "$NODE_IP" "$RANCHER_HOST" "$REGISTRY_HOST"
  elif mode_runs_host_local; then
    track_skip "/etc/hosts: user chose not to manage local host entries"
    manifest_complete_component "local_hosts" "skipped"
  else
    manifest_complete_component "local_hosts" "skipped"
  fi
  if mode_runs_host_local && [[ "$TLS_CHOICE" == "2" && "$TRUST_REGISTRY_IN_DOCKER" == "y" ]]; then
    CURRENT_STEP="docker_registry_trust"
    ensure_local_docker_registry_trust "$REGISTRY_HOST"
  elif mode_runs_host_local && [[ "$TLS_CHOICE" == "2" ]]; then
    track_skip "Docker trust: user chose not to install local registry certificate trust"
    manifest_complete_component "docker_registry_trust" "skipped"
  else
    manifest_complete_component "docker_registry_trust" "skipped"
  fi
  CURRENT_STEP="completed"

  log "DONE. Quick checks:"
  if [[ "$MODE" == "agent" ]]; then
    line "  k3s agent status:     sudo systemctl status k3s-agent --no-pager"
    line "  k3s agent logs:       sudo journalctl -u k3s-agent -n 100 --no-pager"
  else
    line "  k3s nodes:            sudo k3s kubectl get nodes"
  fi
  if mode_runs_stack; then
    line "  cert-manager pods:    sudo k3s kubectl get pods -n cert-manager"
    line "  longhorn pods:        sudo k3s kubectl get pods -n longhorn-system"
    line "  rancher pods:         sudo k3s kubectl get pods -n cattle-system"
    line "  registry pods:        sudo k3s kubectl get pods -n registry"
  fi
  if mode_runs_host_local; then
    line "  nfs exports:          sudo exportfs -v"
  fi
  nl

  if mode_runs_stack; then
    warn "DNS/Hosts:"
    line "  Ensure these resolve to your VM IP:"
    line "    ${RANCHER_HOST}"
    line "    ${REGISTRY_HOST}"
    if mode_runs_host_local && [[ "$MANAGE_LOCAL_HOSTS" == "y" ]]; then
      if [[ "$DRY_RUN" == "1" ]]; then
        line "  Local /etc/hosts entries would be updated on this machine:"
      else
        line "  Local /etc/hosts entries were updated on this machine:"
      fi
      line "    ${NODE_IP} ${RANCHER_HOST} ${REGISTRY_HOST}"
    else
      line "  For local testing on the VM itself, you can add to /etc/hosts:"
      line "    <VM-IP> ${RANCHER_HOST} ${REGISTRY_HOST}"
    fi
    nl
  fi

  if mode_runs_stack && [[ "$TLS_CHOICE" == "2" ]]; then
    warn "Self-signed TLS:"
    line "  - Your browser and Docker clients may not trust the cert by default."
    if mode_runs_host_local && [[ "$TRUST_REGISTRY_IN_DOCKER" == "y" ]]; then
      if [[ "$DRY_RUN" == "1" ]]; then
        line "  - Local Docker trust would be installed for ${REGISTRY_HOST} on this machine."
      else
        line "  - Local Docker trust was installed for ${REGISTRY_HOST} on this machine."
      fi
    else
      line "  - To use the registry with docker push/pull from a machine, you typically need to trust the CA/cert."
    fi
  elif mode_runs_stack; then
    log "Let's Encrypt TLS:"
    line "  - Make sure ports 80/443 are reachable from the internet and DNS points to this VM."
    line "  - If cert issuance fails, check: sudo k3s kubectl describe certificate -A"
  fi

  nl
  if [[ "$MODE" == "agent" ]]; then
    line "  Agent server URL: ${AGENT_SERVER_URL:-<existing agent configuration>}"
    line "  Join token:       <configured>"
  fi
  if mode_runs_stack; then
    line "  Rancher URL:  https://${RANCHER_HOST}"
    line "  Registry URL: https://${REGISTRY_HOST}"
    if [[ "$registry_present" != "y" && "$REGISTRY_AUTH_ENABLED" == "y" ]]; then
      line "  Registry auth: ${REGISTRY_AUTH_USER} / <configured password>"
    fi
  fi
  if mode_runs_host_local && [[ "$ENABLE_NFS" == "y" ]]; then
    line "  NFS export:    $(hostname -I 2>/dev/null | awk '{print $1}'):${NFS_EXPORT_PATH}"
    line "  NFS clients:   ${NFS_ALLOWED_NETWORK}"
  fi
  line "  Run manifest:  ${RUN_MANIFEST}"
  print_dry_run_summary
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
