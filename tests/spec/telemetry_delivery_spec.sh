# shellcheck shell=bash disable=SC2016
Describe 'telemetry delivery scripts'
  SEND_SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/send-telemetry.sh"
  EVENT_SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/send-telemetry-event.sh"

  It 'builds an install payload with sent_at and authorization metadata'
    manifest="$(mktemp)"
    cat >"${manifest}" <<'EOF'
{"status":"success","run_id":"run-123"}
EOF

    When run bash -lc '
      script="$1"
      manifest="$2"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      logdir="${tmpdir}/logs"
      mkdir -p "${mockdir}" "${logdir}"
      cat >"${mockdir}/curl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -eu
attempt_file="${MOCK_LOG_DIR}/attempt"
attempt=1
if [[ -f "${attempt_file}" ]]; then
  attempt=$(( $(cat "${attempt_file}") + 1 ))
fi
printf "%s" "${attempt}" >"${attempt_file}"
printf "%s\n" "$@" >"${MOCK_LOG_DIR}/args-${attempt}.txt"
for arg in "$@"; do
  if [[ "${arg}" == @* ]]; then
    cp "${arg#@}" "${MOCK_LOG_DIR}/payload-${attempt}.json"
  fi
done
exit 0
EOF
      chmod +x "${mockdir}/curl"
      export PATH="${mockdir}:$PATH"
      export MOCK_LOG_DIR="${logdir}"
      export TELEMETRY_RUN_ID="run-123"
      export TELEMETRY_SESSION_ID="session-abc"
      export TELEMETRY_PARENT_RUN_ID="parent-456"
      export TELEMETRY_COMPONENT="core"
      export TELEMETRY_BEARER_TOKEN="pk3s_live_test"
      export TELEMETRY_USER_AGENT="productive-k3s/test"
      /usr/bin/bash "${script}" "${manifest}"
      rc=$?
      printf "\n__ARGS__\n"
      cat "${logdir}/args-1.txt"
      printf "\n__PAYLOAD__\n"
      cat "${logdir}/payload-1.json"
      exit "${rc}"
    ' bash "$SEND_SCRIPT" "$manifest"
    The status should equal 0
    The output should include '__ARGS__'
    The output should include 'Authorization: Bearer pk3s_live_test'
    The output should include 'User-Agent: productive-k3s/test'
    The output should include '__PAYLOAD__'
    The output should include '"sent_at":'
    The output should include '"run_id": "run-123"'
    The output should include '"session_id": "session-abc"'
    The output should include '"event_name": "apply.completed"'

    rm -f "${manifest}"
  End

  It 'falls back to three attempts when TELEMETRY_MAX_RETRIES is invalid'
    manifest="$(mktemp)"
    cat >"${manifest}" <<'EOF'
{"status":"failed","run_id":"retry-run"}
EOF

    When run bash -lc '
      script="$1"
      manifest="$2"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      logdir="${tmpdir}/logs"
      outbox="${tmpdir}/outbox"
      mkdir -p "${mockdir}" "${logdir}" "${outbox}"
      cat >"${mockdir}/curl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -eu
attempt_file="${MOCK_LOG_DIR}/attempt"
attempt=1
if [[ -f "${attempt_file}" ]]; then
  attempt=$(( $(cat "${attempt_file}") + 1 ))
fi
printf "%s" "${attempt}" >"${attempt_file}"
exit 22
EOF
      chmod +x "${mockdir}/curl"
      export PATH="${mockdir}:$PATH"
      export MOCK_LOG_DIR="${logdir}"
      export TELEMETRY_RUN_ID="retry-run"
      export TELEMETRY_MAX_RETRIES="bogus"
      export TELEMETRY_OUTBOX_DIR="${outbox}"
      /usr/bin/bash "${script}" "${manifest}"
      rc=$?
      printf "\n__ATTEMPTS__\n"
      cat "${logdir}/attempt"
      printf "\n__STATUS__\n"
      cat "${outbox}/bootstrap-retry-run-attempt-3.status"
      exit "${rc}"
    ' bash "$SEND_SCRIPT" "$manifest"
    The status should equal 1
    The stderr should include "Invalid TELEMETRY_MAX_RETRIES value 'bogus'"
    The output should include '__ATTEMPTS__'
    The output should include $'__ATTEMPTS__\n3'
    The output should include '__STATUS__'
    The output should include 'attempt=3'
    The output should include 'curl_exit=22'
    The output should include 'recorded_at='

    rm -f "${manifest}"
  End

  It 'records failed event payload attempts in the outbox'
    event_file="$(mktemp)"
    cat >"${event_file}" <<'EOF'
{"event_name":"core.command.started","sent_at":"2026-01-01T00:00:00Z"}
EOF

    When run bash -lc '
      script="$1"
      event_file="$2"
      tmpdir="$(mktemp -d)"
      mockdir="${tmpdir}/bin"
      outbox="${tmpdir}/outbox"
      mkdir -p "${mockdir}" "${outbox}"
      cat >"${mockdir}/curl" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 7
EOF
      chmod +x "${mockdir}/curl"
      export PATH="${mockdir}:$PATH"
      export TELEMETRY_RUN_ID="event-run"
      export TELEMETRY_MAX_RETRIES="1"
      export TELEMETRY_OUTBOX_DIR="${outbox}"
      /usr/bin/bash "${script}" "${event_file}"
      rc=$?
      printf "\n__EVENT_STATUS__\n"
      cat "${outbox}/event-event-run-attempt-1.status"
      printf "\n__EVENT_PAYLOAD__\n"
      cat "${outbox}/event-event-run-attempt-1.json"
      exit "${rc}"
    ' bash "$EVENT_SCRIPT" "$event_file"
    The status should equal 1
    The stderr should include 'Telemetry event delivery exhausted 1 attempt(s).'
    The output should include '__EVENT_STATUS__'
    The output should include 'attempt=1'
    The output should include 'curl_exit=7'
    The output should include '__EVENT_PAYLOAD__'
    The output should include '"event_name":"core.command.started"'
    The output should include '"sent_at":"2026-01-01T00:00:00Z"'

    rm -f "${event_file}"
  End
End
