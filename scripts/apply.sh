#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/component-versions.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/runtime-contract.sh"
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

DRY_RUN=0
MODE="server"
PRODUCTIVE_K3S_STACK_NAME="${PRODUCTIVE_K3S_STACK_NAME:-}"
PRODUCTIVE_K3S_DISTRO="${PRODUCTIVE_K3S_DISTRO:-k3s}"
PRODUCTIVE_K3S_ENGINE="${PRODUCTIVE_K3S_ENGINE:-native}"
PRODUCTIVE_K3S_SSH_HOST="${PRODUCTIVE_K3S_SSH_HOST:-}"
PRODUCTIVE_K3S_SSH_USER="${PRODUCTIVE_K3S_SSH_USER:-}"
PRODUCTIVE_K3S_SSH_PORT="${PRODUCTIVE_K3S_SSH_PORT:-22}"
PRODUCTIVE_K3S_SSH_KEY_PATH="${PRODUCTIVE_K3S_SSH_KEY_PATH:-}"
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
MANIFEST_COMPONENT_ORDER=(cluster_runtime k3s helm stack_addons)
PUBLIC_MANIFEST_SETTINGS=(
  host_os_id
  host_os_version_id
  host_os_codename
  host_os_pretty_name
  platform_support
  bootstrap_mode
  cluster_distro
  cluster_installation_engine
  telemetry_enabled
  telemetry_max_retries
  agent_server_url_provided
  agent_cluster_token_provided
  stack_name
)
PRIVATE_MANIFEST_SETTINGS=(agent_server_url)

json_escape() {
  printf '%s' "$1" | sed \
    -e ':a;N;$!ba' \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1" >/dev/null 2>&1; }
can_use_tty() { [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]; }
is_truthy() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}
k3s_server_active() { service_active "$(pk3s_runtime_server_service)"; }
k3s_agent_active() { service_active "$(pk3s_runtime_agent_service)"; }
kubectl_k3s() { pk3s_runtime_kubectl "$@"; }

prompt() {
  local var="$1" default="$2" msg="$3" val
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
  local var="$1" default="$2" msg="$3" val
  if can_use_tty; then
    printf '%s [%s] (y/n): ' "$msg" "$default" > /dev/tty
    IFS= read -r val < /dev/tty || true
  else
    printf '%s [%s] (y/n): ' "$msg" "$default"
    IFS= read -r val || true
  fi
  val="${val:-$default}"
  case "$val" in
    y|Y) printf -v "$var" 'y' ;;
    n|N) printf -v "$var" 'n' ;;
    *) warn "Invalid input, using default: $default"; printf -v "$var" '%s' "$default" ;;
  esac
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

result_for_mode() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'dry-run'
  else
    printf '%s' "$1"
  fi
}

manifest_set_setting() { MANIFEST_SETTINGS["$1"]="$2"; }

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

manifest_record_cluster_runtime_component() {
  local detected_before="$1" planned_action="$2"
  manifest_record_component "cluster_runtime" "$detected_before" "$planned_action"
  manifest_record_component "k3s" "$detected_before" "$planned_action"
}

manifest_complete_cluster_runtime_component() {
  local result="$1" note="${2:-}"
  manifest_complete_component "cluster_runtime" "$result" "$note"
  manifest_complete_component "k3s" "$result" "$note"
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
  local tmp_file first key component
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
    first=1
    for key in "${PUBLIC_MANIFEST_SETTINGS[@]}"; do
      [[ -n "${MANIFEST_SETTINGS[$key]+x}" ]] || continue
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": "%s"' "$(json_escape "$key")" "$(json_escape "${MANIFEST_SETTINGS[$key]}")"
    done
    printf '\n  },\n'
    printf '  "components": {\n'
    first=1
    for component in "${MANIFEST_COMPONENT_ORDER[@]}"; do
      [[ -n "${MANIFEST_PLANNED[$component]+x}" || -n "${MANIFEST_DETECTED[$component]+x}" || -n "${MANIFEST_RESULT[$component]+x}" ]] || continue
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": {' "$(json_escape "$component")"
      printf '"detected_before": "%s", ' "$(json_escape "${MANIFEST_DETECTED[$component]:-unknown}")"
      printf '"planned_action": "%s", ' "$(json_escape "${MANIFEST_PLANNED[$component]:-unknown}")"
      printf '"result": "%s"' "$(json_escape "${MANIFEST_RESULT[$component]:-unknown}")"
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
  local tmp_file first key component
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
    first=1
    for key in "${PRIVATE_MANIFEST_SETTINGS[@]}"; do
      [[ -n "${MANIFEST_SETTINGS[$key]+x}" ]] || continue
      if (( first == 0 )); then printf ',\n'; fi
      first=0
      printf '    "%s": "%s"' "$(json_escape "$key")" "$(json_escape "${MANIFEST_SETTINGS[$key]}")"
    done
    printf '\n  },\n'
    printf '  "components": {\n'
    first=1
    for component in "${MANIFEST_COMPONENT_ORDER[@]}"; do
      [[ -n "${MANIFEST_NOTES[$component]:-}" ]] || continue
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

maybe_send_telemetry() {
  local exit_code="${1:-0}"
  local sender_script="${SCRIPT_DIR}/send-telemetry.sh"
  if ! is_truthy "${TELEMETRY_ENABLED:-false}"; then
    return 0
  fi
  if [[ -z "${TELEMETRY_ENDPOINT:-}" || ! -f "${RUN_MANIFEST:-}" || ! -x "$sender_script" ]]; then
    return 0
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

emit_bootstrap_lifecycle_event() {
  local lifecycle="$1"
  local result="$2"
  local sender_script="${SCRIPT_DIR}/send-telemetry-event.sh"
  local event_file
  local telemetry_run_id="${RUN_ID:-${TELEMETRY_RUN_ID:-unknown-run}}"

  if ! is_truthy "${TELEMETRY_ENABLED:-false}"; then
    return 0
  fi
  if [[ -z "${TELEMETRY_ENDPOINT:-}" || ! -f "${sender_script}" ]]; then
    return 0
  fi

  event_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "event_family": "usage",\n'
    printf '  "event_name": "core.bootstrap.%s.%s",\n' "$(json_escape "${MODE}")" "$(json_escape "${lifecycle}")"
    printf '  "sent_at": "%s",\n' "$(json_escape "$(date -Iseconds)")"
    printf '  "session_id": "%s",\n' "$(json_escape "${TELEMETRY_SESSION_ID:-}")"
    printf '  "run_id": "%s",\n' "$(json_escape "${telemetry_run_id}")"
    printf '  "parent_run_id": "%s",\n' "$(json_escape "${TELEMETRY_PARENT_RUN_ID:-}")"
    printf '  "component": "core",\n'
    printf '  "bootstrap": {\n'
    printf '    "mode": "%s",\n' "$(json_escape "${MODE}")"
    printf '    "result": "%s"\n' "$(json_escape "${result}")"
    printf '  },\n'
    printf '  "client": {\n'
    printf '    "repository": "productive-k3s-core",\n'
    printf '    "script": "scripts/apply.sh",\n'
    printf '    "telemetry_enabled": "%s"\n' "$(json_escape "${TELEMETRY_ENABLED:-false}")"
    printf '  },\n'
    printf '  "telemetry_meta": {\n'
    printf '    "delivery_mode": "best-effort",\n'
    printf '    "anonymous_by_contract": true\n'
    printf '  }\n'
    printf '}\n'
  } > "${event_file}"

  TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT}" \
  TELEMETRY_MARKER="${TELEMETRY_MARKER}" \
  TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES}" \
  TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS}" \
  TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS}" \
  TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR}" \
  TELEMETRY_RUN_ID="${telemetry_run_id}" \
  bash "${sender_script}" "${event_file}" >/dev/null 2>&1 || true
  rm -f "${event_file}"
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
  maybe_send_telemetry "$exit_code" || warn "Telemetry delivery did not complete successfully. Apply result is unchanged."
}

resolve_telemetry_enabled() {
  if [[ -n "${TELEMETRY_ENABLED:-}" ]]; then
    return 0
  fi
  if can_use_tty; then
    local telemetry_consent="y"
    prompt_yesno telemetry_consent "y" "Productive K3S can send anonymous telemetry about this run to help improve the installation flow. It does not include any sensitive information like hostnames or other environment-specific identifiers. Enable anonymous telemetry for this run?"
    [[ "${telemetry_consent}" == "y" ]] && TELEMETRY_ENABLED="true" || TELEMETRY_ENABLED="false"
    return 0
  fi
  TELEMETRY_ENABLED="false"
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
    ubuntu:*|debian:12|debian:13) PLATFORM_SUPPORT="supported" ;;
    *) PLATFORM_SUPPORT="unsupported" ;;
  esac
  manifest_set_setting "host_os_id" "$OS_ID"
  manifest_set_setting "host_os_version_id" "$OS_VERSION_ID"
  manifest_set_setting "host_os_codename" "$OS_CODENAME"
  manifest_set_setting "host_os_pretty_name" "$OS_PRETTY_NAME"
  manifest_set_setting "platform_support" "$PLATFORM_SUPPORT"
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

run_shell() {
  local desc="$1" cmd="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] ${desc}"
    echo "  ${cmd}"
    return 0
  fi
  bash -o pipefail -lc "$cmd" </dev/null
}

run_shell_with_retries() {
  local desc="$1" timeout_secs="$2" sleep_secs="$3" cmd="$4"
  local start_ts now_ts
  if [[ "$DRY_RUN" == "1" ]]; then
    run_shell "$desc" "$cmd"
    return 0
  fi
  start_ts="$(date +%s)"
  while true; do
    if run_shell "$desc" "$cmd"; then
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

ensure_packages() {
  local label="$1"
  shift
  local missing=() pkg install_pkgs
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
  prompt_yesno install_pkgs "y" "Install the missing packages for ${label}?"
  [[ "$install_pkgs" == "y" ]] || { err "Cannot continue with ${label} without those packages."; exit 1; }
  run_cmd "Updating apt indexes for ${label}" sudo apt-get update -y
  run_cmd "Installing packages for ${label}" sudo apt-get install -y "${missing[@]}"
}

validate_runtime_engine() {
  case "$PRODUCTIVE_K3S_ENGINE" in
    native|k3sup) ;;
    *) err "Unsupported cluster installation engine: ${PRODUCTIVE_K3S_ENGINE}"; exit 1 ;;
  esac
  if ! pk3s_runtime_validate_selection; then
    err "Unsupported cluster distro/engine selection: ${PRODUCTIVE_K3S_DISTRO}/${PRODUCTIVE_K3S_ENGINE}"
    exit 1
  fi
}

install_k3sup_if_needed() {
  need_cmd k3sup && return 0
  run_shell "Downloading k3sup installer" "curl -sLS https://get.k3sup.dev | sh"
  run_shell "Installing k3sup into /usr/local/bin" "sudo install k3sup /usr/local/bin/"
}

install_k3s_with_k3sup() {
  local install_cmd=""
  if [[ "$MODE" == "agent" ]]; then
    [[ -n "${AGENT_SERVER_URL:-}" && -n "${AGENT_CLUSTER_TOKEN:-}" ]] || { err "Agent mode requires both server URL and cluster token."; exit 1; }
    [[ -n "$PRODUCTIVE_K3S_SSH_HOST" && -n "$PRODUCTIVE_K3S_SSH_USER" ]] || { err "k3sup agent mode requires PRODUCTIVE_K3S_SSH_HOST and PRODUCTIVE_K3S_SSH_USER."; exit 1; }
    local server_host="${AGENT_SERVER_URL#https://}"
    server_host="${server_host%%:*}"
    printf -v install_cmd 'k3sup join --ip %q --user %q --ssh-port %q --server-ip %q --server-user %q --k3s-version %q' \
      "$PRODUCTIVE_K3S_SSH_HOST" \
      "$PRODUCTIVE_K3S_SSH_USER" \
      "$PRODUCTIVE_K3S_SSH_PORT" \
      "$server_host" \
      "$PRODUCTIVE_K3S_SSH_USER" \
      "${PRODUCTIVE_K3S_K3S_VERSION}"
    run_shell "Joining k3s agent with k3sup" "$install_cmd"
    return
  fi
  run_shell "Creating ${HOME}/.kube for k3sup kubeconfig output" "mkdir -p ${HOME}/.kube"
  printf -v install_cmd 'k3sup install --local --local-path %q --context %q --k3s-version %q' "${HOME}/.kube/k3sup-${MODE}.yaml" "productive-k3s-${MODE}" "${PRODUCTIVE_K3S_K3S_VERSION}"
  run_shell "Installing k3s with k3sup" "$install_cmd"
}

install_k3s_with_native() {
  local install_cmd=""
  if [[ "$MODE" == "agent" ]]; then
    [[ -n "${AGENT_SERVER_URL:-}" && -n "${AGENT_CLUSTER_TOKEN:-}" ]] || { err "Agent mode requires both server URL and cluster token."; exit 1; }
    printf -v install_cmd 'curl -sfL https://get.k3s.io | K3S_URL=%q K3S_TOKEN=%q INSTALL_K3S_EXEC=agent INSTALL_K3S_VERSION=%q sh -' "$AGENT_SERVER_URL" "$AGENT_CLUSTER_TOKEN" "${PRODUCTIVE_K3S_K3S_VERSION}"
    run_shell "Installing k3s agent" "$install_cmd"
    return
  fi
  run_shell "Installing k3s (${PRODUCTIVE_K3S_K3S_VERSION})" "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${PRODUCTIVE_K3S_K3S_VERSION} sh -"
}

install_rke2_with_native() {
  local config_dir="/etc/rancher/rke2"
  local config_path="${config_dir}/config.yaml"
  local install_cmd=""
  if [[ "$MODE" == "agent" ]]; then
    [[ -n "${AGENT_SERVER_URL:-}" && -n "${AGENT_CLUSTER_TOKEN:-}" ]] || { err "Agent mode requires both server URL and cluster token."; exit 1; }
    printf -v install_cmd 'curl -sfL https://get.rke2.io | sudo env INSTALL_RKE2_VERSION=%q INSTALL_RKE2_TYPE=agent sh -' "${PRODUCTIVE_K3S_RKE2_VERSION}"
    run_shell "Installing rke2 agent" "$install_cmd"
    run_shell "Writing rke2 agent config" "sudo mkdir -p ${config_dir} && sudo tee ${config_path} >/dev/null <<'EOF'
server: ${AGENT_SERVER_URL}
token: ${AGENT_CLUSTER_TOKEN}
EOF"
    run_cmd "Enabling rke2-agent" sudo systemctl enable --now rke2-agent
    return
  fi
  printf -v install_cmd 'curl -sfL https://get.rke2.io | sudo env INSTALL_RKE2_VERSION=%q sh -' "${PRODUCTIVE_K3S_RKE2_VERSION}"
  run_shell "Installing rke2 (${PRODUCTIVE_K3S_RKE2_VERSION})" "$install_cmd"
  run_cmd "Enabling rke2-server" sudo systemctl enable --now rke2-server
}

install_cluster_runtime_if_needed() {
  local action="$1"
  [[ "$action" == "reuse" ]] && { manifest_complete_cluster_runtime_component "$(result_for_mode reused)"; return; }
  [[ "$action" == "install" ]] || { err "$(pk3s_runtime_cluster_label) is required."; exit 1; }
  ensure_packages "$(pk3s_runtime_cluster_label) installation" curl ca-certificates
  if [[ "${PRODUCTIVE_K3S_DISTRO}" == "rke2" ]]; then
    install_rke2_with_native
  else
    if [[ "$PRODUCTIVE_K3S_ENGINE" == "k3sup" ]]; then
      install_k3sup_if_needed
      install_k3s_with_k3sup
    else
      install_k3s_with_native
    fi
  fi
  manifest_complete_cluster_runtime_component "$(result_for_mode installed)"
}

install_helm_if_needed() {
  local action="$1"
  [[ "$action" == "skip" ]] && { manifest_complete_component "helm" "skipped"; return; }
  [[ "$action" == "reuse" ]] && { manifest_complete_component "helm" "$(result_for_mode reused)"; return; }
  [[ "$action" == "install" ]] || { err "Helm is required."; exit 1; }
  ensure_packages "Helm installation" curl ca-certificates
  if ! run_shell_with_retries "Installing Helm (${PRODUCTIVE_K3S_HELM_VERSION})" 600 15 "curl --fail --silent --show-error --location --retry 5 --retry-delay 3 --retry-all-errors https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=${PRODUCTIVE_K3S_HELM_VERSION} bash"; then
    err "Helm installation failed."
    exit 1
  fi
  manifest_complete_component "helm" "$(result_for_mode installed)"
}

wait_cluster_ready() {
  local timeout="${1:-180}" start now ready_nodes
  [[ "$MODE" != "agent" && "$DRY_RUN" != "1" ]] || return 0
  log "Waiting for $(pk3s_runtime_distro_label) API and node readiness (timeout ${timeout}s)..."
  start="$(date +%s)"
  while true; do
    if service_active "$(pk3s_runtime_server_service)" && kubectl_k3s get nodes >/dev/null 2>&1; then
      ready_nodes="$(kubectl_k3s get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{count++} END{print count+0}')"
      (( ready_nodes > 0 )) && { log "$(pk3s_runtime_distro_label) API is reachable and at least one node is Ready."; return 0; }
    fi
    now="$(date +%s)"
    if (( now - start > timeout )); then
      err "Timed out waiting for $(pk3s_runtime_distro_label) API readiness."
      sudo systemctl status "$(pk3s_runtime_server_service)" --no-pager || true
      kubectl_k3s get nodes -o wide || true
      return 1
    fi
    sleep 5
  done
}

ensure_user_kubeconfig() {
  local source_kubeconfig target_dir target_kubeconfig
  [[ "$MODE" != "agent" ]] || return 0
  source_kubeconfig="$(pk3s_runtime_system_kubeconfig_path)"
  target_dir="${HOME}/.kube"
  target_kubeconfig="$(pk3s_runtime_default_user_kubeconfig_path)"
  [[ "$DRY_RUN" == "1" ]] && { log "[dry-run] Preparing user kubeconfig at ${target_kubeconfig}"; return 0; }
  [[ -f "$source_kubeconfig" ]] || { err "$(pk3s_runtime_distro_label) kubeconfig was not found at ${source_kubeconfig}."; exit 1; }
  mkdir -p "$target_dir"
  sudo cp "$source_kubeconfig" "$target_kubeconfig"
  sudo chown "$(id -u):$(id -g)" "$target_kubeconfig"
  chmod 600 "$target_kubeconfig"
  export KUBECONFIG="$target_kubeconfig"
}

resolve_default_stack_name() {
  [[ -n "${PRODUCTIVE_K3S_STACK_NAME}" ]] && return 0
  if [[ "$MODE" == "stack" || "$MODE" == "single-node" ]]; then
    PRODUCTIVE_K3S_STACK_NAME="base"
  fi
}

stack_addon_record_source_value() {
  printf '%s\n' "$1" | awk -F '\t' '{for (i=1;i<=NF;i++) if ($i ~ /^source=/) {sub(/^source=/,"",$i); print $i; exit}}'
}

stack_addon_record_name_value() {
  printf '%s\n' "$1" | awk -F '\t' '{for (i=1;i<=NF;i++) if ($i ~ /^name=/) {sub(/^name=/,"",$i); print $i; exit}}'
}

install_stack_addon_record() {
  local addon_record="$1" addon_name addon_source bundled_path
  addon_name="$(stack_addon_record_name_value "${addon_record}")"
  addon_source="$(stack_addon_record_source_value "${addon_record}")"
  [[ -n "${addon_name}" ]] || { err "Stack '${PRODUCTIVE_K3S_STACK_NAME}' contains an add-on entry without a name."; exit 1; }
  CURRENT_STEP="stack-addons"
  log "Installing stack add-on '${addon_name}' from stack '${PRODUCTIVE_K3S_STACK_NAME}'"
  if [[ -n "${addon_source}" && -n "${PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR:-}" ]]; then
    bundled_path="${PRODUCTIVE_K3S_STACK_BUNDLED_ADDONS_DIR}/${addon_source#addons/}"
    [[ -f "${bundled_path}" ]] || { err "Bundled add-on package not found: ${addon_source}"; exit 1; }
    [[ "$DRY_RUN" == "1" ]] && { log "[dry-run] Would install bundled add-on package '${addon_source}'"; return 0; }
    "${SCRIPT_DIR}/../productive-k3s-core.sh" addon install --tgz "${bundled_path}"
    return
  fi
  if addon_source_script_exists "${addon_name}" install.sh; then
    [[ "$DRY_RUN" == "1" ]] && { log "[dry-run] Would run source add-on installer for '${addon_name}'"; return 0; }
    run_addon_source_script "${addon_name}" install.sh
    return
  fi
  err "Add-on '${addon_name}' is not bundled and does not provide scripts/install.sh in the configured add-ons source."
  exit 1
}

install_stack_addons() {
  [[ "$MODE" == "stack" || "$MODE" == "single-node" ]] || {
    manifest_record_component "stack_addons" "not-requested" "skip"
    manifest_complete_component "stack_addons" "skipped"
    return 0
  }
  resolve_default_stack_name
  if ! stack_source_addon_records "${PRODUCTIVE_K3S_STACK_NAME}" >/dev/null 2>&1; then
    err "Stack source '${PRODUCTIVE_K3S_STACK_NAME}' was not found. Set PRODUCTIVE_K3S_ADDONS_REPO_DIR or install from a stack package."
    exit 1
  fi
  local addon_record count=0
  manifest_record_component "stack_addons" "unknown" "install"
  while IFS= read -r addon_record; do
    [[ -n "${addon_record}" ]] || continue
    install_stack_addon_record "${addon_record}"
    count=$((count + 1))
  done < <(stack_source_addon_records "${PRODUCTIVE_K3S_STACK_NAME}")
  manifest_complete_component "stack_addons" "$(result_for_mode installed)" "${count} add-on(s)"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --mode) MODE="${2:-}"; shift ;;
      -h|--help)
        cat <<EOF
Usage: $0 [--dry-run] [--mode <single-node|server|agent|stack>]
EOF
        exit 0
        ;;
      *) err "Unknown argument: $1"; exit 1 ;;
    esac
    shift
  done
  case "$MODE" in
    single-node|server|agent|stack) ;;
    *) err "Unsupported mode: ${MODE}"; exit 1 ;;
  esac
}

print_plan_summary() {
  local runtime_action="$1" helm_action="$2"
  log "Planned actions"
  line "  - $(pk3s_runtime_cluster_label): ${runtime_action}"
  line "  - helm: ${helm_action}"
  if [[ "$MODE" == "stack" || "$MODE" == "single-node" ]]; then
    line "  - stack add-ons: install from '${PRODUCTIVE_K3S_STACK_NAME}'"
  fi
}

main() {
  parse_args "$@"
  validate_runtime_engine
  resolve_telemetry_enabled
  init_run_manifest
  trap cleanup_exit EXIT
  bind_stdin_to_tty
  detect_host_platform
  resolve_default_stack_name

  manifest_set_setting "bootstrap_mode" "$MODE"
  manifest_set_setting "cluster_distro" "$PRODUCTIVE_K3S_DISTRO"
  manifest_set_setting "cluster_installation_engine" "$PRODUCTIVE_K3S_ENGINE"
  manifest_set_setting "telemetry_enabled" "${TELEMETRY_ENABLED}"
  manifest_set_setting "telemetry_max_retries" "${TELEMETRY_MAX_RETRIES}"
  manifest_set_setting "stack_name" "${PRODUCTIVE_K3S_STACK_NAME}"

  local runtime_present="missing" runtime_action="reuse" helm_present="missing" helm_action="reuse"
  if [[ "$MODE" == "agent" ]]; then
    if k3s_agent_active; then
      runtime_present="present"
      prompt_yesno CONTINUE_AGENT "y" "Existing $(pk3s_runtime_cluster_label) agent installation detected. Continue using it without changes? [required]"
      [[ "$CONTINUE_AGENT" == "y" ]] || { err "$(pk3s_runtime_cluster_label) agent is required."; exit 1; }
      runtime_action="reuse"
    else
      prompt_yesno INSTALL_AGENT "y" "$(pk3s_runtime_cluster_label) agent was not detected. Install it now? [required]"
      [[ "$INSTALL_AGENT" == "y" ]] || { err "Cannot continue without $(pk3s_runtime_cluster_label) agent."; exit 1; }
      runtime_action="install"
      prompt AGENT_SERVER_URL "https://server.example.local:6443" "Agent server URL"
      prompt AGENT_CLUSTER_TOKEN "change-me-token" "Agent cluster token"
    fi
    helm_present="not-required"
    helm_action="skip"
  else
    if k3s_server_active; then
      runtime_present="present"
      prompt_yesno CONTINUE_RUNTIME "y" "Existing $(pk3s_runtime_cluster_label) installation detected. Continue using it without changes? [required]"
      [[ "$CONTINUE_RUNTIME" == "y" ]] || { err "$(pk3s_runtime_cluster_label) is required."; exit 1; }
      runtime_action="reuse"
    else
      prompt_yesno INSTALL_RUNTIME "y" "$(pk3s_runtime_cluster_label) was not detected. Install it now? [required]"
      [[ "$INSTALL_RUNTIME" == "y" ]] || { err "Cannot continue without $(pk3s_runtime_cluster_label)."; exit 1; }
      runtime_action="install"
    fi
    if need_cmd helm; then
      helm_present="present"
      prompt_yesno CONTINUE_HELM "y" "Helm is already installed. Continue using it without changes? [required]"
      [[ "$CONTINUE_HELM" == "y" ]] || { err "Helm is required."; exit 1; }
      helm_action="reuse"
    else
      prompt_yesno INSTALL_HELM "y" "Helm was not detected. Install it now? [required]"
      [[ "$INSTALL_HELM" == "y" ]] || { err "Cannot continue without Helm."; exit 1; }
      helm_action="install"
    fi
  fi

  manifest_set_setting "agent_server_url" "$AGENT_SERVER_URL"
  manifest_set_setting "agent_server_url_provided" "$( [[ -n "$AGENT_SERVER_URL" ]] && echo y || echo n )"
  manifest_set_setting "agent_cluster_token_provided" "$( [[ -n "$AGENT_CLUSTER_TOKEN" ]] && echo y || echo n )"
  manifest_record_cluster_runtime_component "$runtime_present" "$runtime_action"
  manifest_record_component "helm" "$helm_present" "$helm_action"

  print_plan_summary "$runtime_action" "$helm_action"
  local proceed="y"
  if is_truthy "${PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN:-false}"; then
    log "Auto-approving apply plan from PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN=true"
  else
    prompt_yesno proceed "y" "Proceed with this plan?"
  fi
  [[ "$proceed" == "y" ]] || { RUN_STATUS="cancelled"; warn "Apply cancelled before applying changes."; exit 0; }
  exec </dev/null

  CURRENT_STEP="cluster-runtime"
  install_cluster_runtime_if_needed "$runtime_action"
  CURRENT_STEP="helm"
  install_helm_if_needed "$helm_action"
  wait_cluster_ready 180
  ensure_user_kubeconfig
  if [[ "$MODE" != "agent" && "$DRY_RUN" != "1" ]]; then
    log "Inspecting $(pk3s_runtime_cluster_label) node..."
    kubectl_k3s get nodes -o wide
  fi
  install_stack_addons
  CURRENT_STEP="completed"
  log "DONE. Quick checks:"
  if [[ "$MODE" == "agent" ]]; then
    line "  agent status:  sudo systemctl status $(pk3s_runtime_agent_service) --no-pager"
  else
    line "  cluster nodes: $(pk3s_runtime_kubectl_hint) get nodes"
  fi
  line "  Run manifest:  ${RUN_MANIFEST}"
  nl
}

if [[ "${PRODUCTIVE_K3S_LIB_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
