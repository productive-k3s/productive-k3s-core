# Privacy And Telemetry

`productive-k3s-core` writes a structured run manifest for each bootstrap execution and can emit correlated anonymous telemetry events when telemetry is enabled.

Goals:

- keep local troubleshooting and test evidence useful
- avoid recording personal or environment-specific data in the public run manifest
- keep the public telemetry contract aligned with the public run manifest

## Public Run Manifest

Bootstrap runs write a public manifest under `runs/apply-<run_id>.json`.

That manifest is intentionally limited to anonymous operational data such as:

- bootstrap mode
- supported platform and OS family/version
- component plan and result
- non-sensitive feature flags
- timestamps, exit code, and current step

The public manifest does **not** record:

- hostnames
- usernames
- current working directory
- server URLs
- ingress hostnames
- local filesystem paths
- NFS client networks

## Private Rollback Context

Some rollback operations still need local details such as hostnames, export paths, or Docker trust targets.

For that reason, the bootstrap also writes a paired local-only context file:

- `runs/apply-<run_id>-private.json`

That file is used only to support rollback planning and rollback apply operations on the same machine.

It is not part of the public manifest contract and should not be treated as shareable telemetry.

## Telemetry Direction

When telemetry is enabled, it remains:

- explicit opt-in
- anonymous
- event-driven
- based on the same public manifest contract documented here

Core emits two telemetry families:

- bootstrap manifest delivery through `scripts/send-telemetry.sh`
- command and bootstrap lifecycle events such as `core.command.started`, `core.command.completed`, `core.apply.server.started`, and `core.apply.server.completed`

Examples of safe event categories:

- install
- mode usage
- component enabled
- operation attempt

Interpretation of those events belongs on the receiving side, not in the local bootstrap client.

## Delivery Controls

Telemetry delivery remains explicit opt-in.

Decision rules:

- if `TELEMETRY_ENABLED=true`, telemetry is enabled without prompting
- if `TELEMETRY_ENABLED=false`, telemetry is disabled without prompting
- if a parent layer already resolved telemetry and passed `TELEMETRY_ENABLED`, Core does not ask again
- if `TELEMETRY_ENABLED` is unset and the bootstrap is running interactively, the bootstrap asks once whether to enable anonymous telemetry for that run, with `Yes` as the default answer
- if `TELEMETRY_ENABLED` is unset and the bootstrap is not running interactively, telemetry stays disabled

Environment variables:

- `TELEMETRY_ENABLED`: set to `true` to enable best-effort delivery of the public bootstrap manifest
- `TELEMETRY_ENDPOINT`: destination URL for telemetry delivery
  Default: `https://telemetry.productive-k3s.io/telemetry`
- `TELEMETRY_MARKER`: public header marker for telemetry delivery. Default: `pk3s-public-v1`
- `TELEMETRY_BEARER_TOKEN`: optional Observability bearer token. When set, Core still sends the public marker and additionally sends `Authorization: Bearer <telemetry-token>`
- `TELEMETRY_MAX_RETRIES`: maximum total delivery attempts, including the first try. Default: `3`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`: connect timeout per attempt. Default: `5`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`: full request timeout per attempt. Default: `10`
- `TELEMETRY_OUTBOX_DIR`: local directory used to retain failed delivery payloads. Default: `runs/telemetry-outbox`
- `TELEMETRY_USER_AGENT`: HTTP user agent for delivery requests
- `TELEMETRY_SESSION_ID`: shared correlation ID for the whole command chain
- `TELEMETRY_RUN_ID`: current Core execution identifier
- `TELEMETRY_PARENT_RUN_ID`: parent execution identifier when Core is invoked by CLI or Infra
- `TELEMETRY_COMPONENT`: component label such as `core`

Delivery rules:

- telemetry is best-effort only
- telemetry must never block or fail the bootstrap installation
- failed attempts are retained locally in the telemetry outbox directory
- retries are marked in the payload so the receiver can distinguish original delivery from retry delivery

## Correlation model

Core works in both modes:

- standalone: it generates its own `session_id` and `run_id` when none are provided
- delegated: it reuses the incoming `session_id`, generates its own `run_id`, and preserves the upstream `parent_run_id`

That lets the receiver reconstruct chains such as `cli -> infra -> core` without exposing host-specific identifiers.
