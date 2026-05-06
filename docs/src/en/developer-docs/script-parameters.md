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

At the moment, the public support baseline is `amd64`/`x86_64`. The preflight reports `arm64`/`aarch64` as unsupported until those targets are explicitly added to the supported matrix.

## `scripts/bootstrap-k3s-stack.sh`

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
- whether to manage local `/etc/hosts`
- whether to trust the self-signed registry in local Docker

### Telemetry-related environment variables

The bootstrap script reads these environment variables:

- `TELEMETRY_ENABLED`
- `TELEMETRY_ENDPOINT`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_USER_AGENT`

### Persisted run settings

The bootstrap manifest records settings such as:

- `bootstrap_mode`
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
- `manage_local_hosts`
- `trust_registry_in_docker`

## `scripts/validate-k3s-stack.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--strict` | Exit non-zero on warnings as well as failures |
| `--json` | Emit machine-readable JSON |
| `--docker-registry-test` | Run docker push/pull validation against `registry.home.arpa` |
| `-h`, `--help` | Show CLI help |

### Related environment variables

For the optional Docker login path, the validator can consume:

- `REGISTRY_USER`
- `REGISTRY_PASSWORD`

## `scripts/clean-k3s-stack.sh`

### CLI options

| Option | Meaning |
| --- | --- |
| `--plan` | Show the cleanup plan only |
| `--apply` | Apply the destructive cleanup |
| `--yes` | Auto-approve the yes/no prompt |
| `--confirm-clean` | Auto-approve the typed `CLEAN` confirmation |
| `-h`, `--help` | Show CLI help |

## `scripts/rollback-k3s-stack.sh`

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
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_USER_AGENT`
- `TELEMETRY_ENABLED`
- `TELEMETRY_RUN_ID`
- `TELEMETRY_SOURCE_REPOSITORY`
- `TELEMETRY_SOURCE_SCRIPT`
- `TELEMETRY_EXIT_CODE`

## Notes

!!! note
    The bootstrap script is intentionally interactive. Most installation choices are prompted at runtime rather than passed as a large flag surface.

!!! note
    The host preflight is a compatibility check, not an installer. It tells you whether the target looks aligned with the supported platform assumptions before bootstrap starts making changes.

!!! note
    If you need machine-driven orchestration, the mode split plus the recorded manifest settings are the most stable integration points today.
