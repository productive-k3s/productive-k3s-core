# Scripts Parameters

This page summarizes the main operator-facing CLI options and environment-backed parameters exposed by the repository scripts.

## `scripts/preflight-host.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--mode <single-node|server|agent|stack>` | Evaluate the host against the selected runtime profile |
| `--strict` | Exit non-zero on warnings as well as failures |
| `--json-output` | Emit machine-readable JSON instead of human-readable output |
| `-h`, `--help` | Show CLI help |

### What it checks

The host preflight validates:

- supported OS and version
- supported CPU architecture
- `systemd` as PID 1
- required commands for the bootstrap or release install path
- sudo posture
- published hardware guidance for `single-node` and `stack`

For `server` and `agent`, it still captures the host resource snapshot, but it does not enforce the same full-stack sizing guidance.

At the moment, the public support baseline includes `amd64`/`x86_64` and Ubuntu `24.04` on `arm64`/`aarch64`. The preflight accepts both families for the currently supported Ubuntu and Debian targets, while the retained ARM validation evidence is specific to Ubuntu `24.04`.

## `scripts/apply.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--dry-run` | Plan the bootstrap without applying changes |
| `--mode <single-node|server|agent|stack>` | Select the execution mode |
| `-h`, `--help` | Show CLI help |

### Mode-sensitive inputs

The bootstrap is mostly interactive. The script prompts for values depending on detected state and selected mode.

Common prompted values include:

- `Agent server URL`
- `Agent cluster token`
- `Base domain`
- `Rancher hostname`
- `Rancher bootstrap password`
- `Registry hostname`
- `Registry PVC size`
- `Registry StorageClass`
- `Registry auth enabled`, username, and password
- TLS choice: `Let's Encrypt` or `Self-signed`
- `Let's Encrypt email`
- `Let's Encrypt environment`
- `Longhorn data mount path`
- `Longhorn default replica count`
- `Longhorn storage minimal available percentage`
- `NFS export path`
- `NFS allowed client network/CIDR`
- whether the `rancher` add-on may manage local `/etc/hosts`
- whether the `registry` add-on may manage local `/etc/hosts`
- whether the `registry` add-on may install self-signed trust into local Docker

### Telemetry-related environment variables

The bootstrap script reads these environment variables:

- `TELEMETRY_ENABLED`
- `TELEMETRY_ENDPOINT`
  Default: `https://telemetry.productive-k3s.io/telemetry`
- `TELEMETRY_MARKER`
- `TELEMETRY_BEARER_TOKEN`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_USER_AGENT`
- `TELEMETRY_SESSION_ID`
- `TELEMETRY_RUN_ID`
- `TELEMETRY_PARENT_RUN_ID`
- `TELEMETRY_COMPONENT`

### Engine-related environment variables

The bootstrap script also reads:

- `PRODUCTIVE_K3S_ENGINE`: `native` or `k3sup`. Default: `native`.

When the experimental `k3sup` engine is used in orchestrated split-mode flows, the wrapper layer may also provide:

- `PRODUCTIVE_K3S_SSH_HOST`
- `PRODUCTIVE_K3S_SSH_USER`
- `PRODUCTIVE_K3S_SSH_PORT`
- `PRODUCTIVE_K3S_SSH_KEY_PATH`
- `PRODUCTIVE_K3S_SSH_EXTRA_OPTS`

### Persisted run settings

The bootstrap manifest records settings such as:

- `bootstrap_mode`
- `k3s_installation_engine`
- `agent_server_url_provided`
- `agent_cluster_token_provided`
- `base_domain`
- `rancher_host`
- `registry_host`
- `tls_mode`
- `letsencrypt_environment`
- `longhorn_data_path`
- `longhorn_replica_count`
- `longhorn_minimal_available_percentage`
- `longhorn_single_node_mode`
- `registry_pvc_size`
- `registry_storage_class`
- `registry_auth_enabled`
- `nfs_manage`
- `nfs_export_path`
- `nfs_allowed_network`
- `rancher_manage_local_hosts`
- `registry_manage_local_hosts`
- `registry_trust_docker`

## `scripts/validate.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--strict` | Exit non-zero on warnings as well as failures |
| `--json` | Emit machine-readable JSON |
| `--docker-registry-test` | Run docker push/pull validation against `registry.home.arpa` |
| `-h`, `--help` | Show CLI help |

### Related environment variables

The validator still accepts `--docker-registry-test`, but the actual registry push/pull check now lives in the `registry` add-on validation hook. For that optional Docker login path, the validator can consume:

- `REGISTRY_USER`
- `REGISTRY_PASSWORD`

## `scripts/cleanup.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--plan` | Show the cleanup plan only |
| `--apply` | Apply the destructive cleanup |
| `--yes` | Auto-approve the yes/no prompt |
| `--confirm-clean` | Auto-approve the typed `CLEAN` confirmation |
| `-h`, `--help` | Show CLI help |

## `scripts/rollback.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--to <file>` | Bootstrap run manifest JSON to evaluate |
| `--plan` | Show the rollback plan only |
| `--apply` | Execute the safe rollback actions derived from the manifest |
| `--yes` | Auto-approve apply without prompting |
| `-h`, `--help` | Show CLI help |

## `scripts/send-telemetry.sh`

This helper consumes:

- positional `MANIFEST_PATH`
- `TELEMETRY_ENDPOINT`
  Default: `https://telemetry.productive-k3s.io/telemetry`
- `TELEMETRY_MARKER`
- `TELEMETRY_BEARER_TOKEN`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_USER_AGENT`
- `TELEMETRY_ENABLED`
- `TELEMETRY_SESSION_ID`
- `TELEMETRY_RUN_ID`
- `TELEMETRY_PARENT_RUN_ID`
- `TELEMETRY_COMPONENT`
- `TELEMETRY_SOURCE_REPOSITORY`
- `TELEMETRY_SOURCE_SCRIPT`
- `TELEMETRY_EXIT_CODE`

## `scripts/send-telemetry-event.sh`

This helper consumes:

- positional `PAYLOAD_PATH`
- `TELEMETRY_ENDPOINT`
  Default: `https://telemetry.productive-k3s.io/telemetry`
- `TELEMETRY_MARKER`
- `TELEMETRY_BEARER_TOKEN`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_RUN_ID`

## Notes

!!! note
    The bootstrap script is intentionally interactive. Most installation choices are prompted at runtime rather than passed as a large flag surface.

!!! note
    The host preflight is a compatibility check, not an installer. It tells you whether the target looks aligned with the supported platform assumptions before bootstrap starts making changes.

!!! note
    If you need machine-driven orchestration, the mode split plus the recorded manifest settings are the most stable integration points today.
