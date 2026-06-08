# Parámetros De Scripts

Esta página resume las principales opciones CLI y parámetros respaldados por entorno que exponen los scripts del repositorio.

## `scripts/preflight-host.sh`

### Opciones CLI

| Opción | Significado |
| --- | --- |
| `--mode <single-node|server|agent|stack>` | Evaluar el host contra el perfil de runtime seleccionado |
| `--strict` | Terminar con código no cero también ante warnings |
| `--json-output` | Emitir JSON machine-readable en lugar de salida legible para humanos |
| `-h`, `--help` | Mostrar ayuda CLI |

### Qué chequea

El preflight del host valida:

- OS y versión soportados
- arquitectura de CPU soportada
- `systemd` como PID 1
- comandos requeridos para el bootstrap o para el camino de instalación vía release
- postura de `sudo`
- guía publicada de hardware para `single-node` y `stack`

Para `server` y `agent`, igual captura el snapshot de recursos del host, pero no aplica la misma guía de dimensionamiento del stack completo.

Por ahora, la baseline pública soportada incluye `amd64`/`x86_64` y Ubuntu `24.04` sobre `arm64`/`aarch64`. El preflight acepta ambas familias para los targets Ubuntu y Debian actualmente soportados, mientras que la evidencia ARM retenida hoy es específica de Ubuntu `24.04`.

## `scripts/apply.sh`

### Opciones CLI

| Opción | Significado |
| --- | --- |
| `--dry-run` | Planificar el bootstrap sin aplicar cambios |
| `--mode <single-node|server|agent|stack>` | Elegir el modo de ejecución |
| `-h`, `--help` | Mostrar ayuda CLI |

### Inputs sensibles al modo

El bootstrap es mayormente interactivo. El script pregunta distintos valores según el estado detectado y el modo seleccionado.

Valores preguntados habitualmente:

- `Agent server URL`
- `Agent cluster token`
- `Base domain`
- `Rancher hostname`
- `Rancher bootstrap password`
- `Registry hostname`
- `Registry PVC size`
- `Registry StorageClass`
- `Registry auth enabled`, username y password
- elección de TLS: `Let's Encrypt` o `Self-signed`
- `Let's Encrypt email`
- `Let's Encrypt environment`
- `Longhorn data mount path`
- `Longhorn default replica count`
- `Longhorn storage minimal available percentage`
- `NFS export path`
- `NFS allowed client network/CIDR`
- si el add-on `rancher` puede administrar `/etc/hosts` local
- si el add-on `registry` puede administrar `/etc/hosts` local
- si el add-on `registry` puede instalar confianza self-signed en Docker local

### Variables de entorno relacionadas con telemetría

El script de bootstrap lee estas variables de entorno:

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

### Variables de entorno relacionadas con el engine

El script de bootstrap también lee:

- `PRODUCTIVE_K3S_ENGINE`: `native` o `k3sup`. Default: `native`.

Cuando se usa el engine experimental `k3sup` en flujos orquestados con modos separados, la capa wrapper también puede proveer:

- `PRODUCTIVE_K3S_SSH_HOST`
- `PRODUCTIVE_K3S_SSH_USER`
- `PRODUCTIVE_K3S_SSH_PORT`
- `PRODUCTIVE_K3S_SSH_KEY_PATH`
- `PRODUCTIVE_K3S_SSH_EXTRA_OPTS`

### Settings persistidos en el manifest

El manifest de bootstrap registra settings como:

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

### Opciones CLI

| Opción | Significado |
| --- | --- |
| `--strict` | Terminar con código no cero también ante warnings |
| `--json` | Emitir JSON machine-readable |
| `--docker-registry-test` | Ejecutar validación docker push/pull contra `registry.home.arpa` |
| `-h`, `--help` | Mostrar ayuda CLI |

### Variables de entorno relacionadas

El validador sigue aceptando `--docker-registry-test`, pero la validación real de push/pull del registry ahora vive en el hook de validación del add-on `registry`. Para el camino opcional de Docker login, el validador puede consumir:

- `REGISTRY_USER`
- `REGISTRY_PASSWORD`

## `scripts/cleanup.sh`

### Opciones CLI

| Opción | Significado |
| --- | --- |
| `--plan` | Mostrar sólo el plan de limpieza |
| `--apply` | Aplicar la limpieza destructiva |
| `--yes` | Auto-aprobar el prompt yes/no |
| `--confirm-clean` | Auto-aprobar la confirmación tipeada `CLEAN` |
| `-h`, `--help` | Mostrar ayuda CLI |

## `scripts/rollback.sh`

### Opciones CLI

| Opción | Significado |
| --- | --- |
| `--to <file>` | Manifest JSON de una corrida de bootstrap a evaluar |
| `--plan` | Mostrar sólo el plan de rollback |
| `--apply` | Ejecutar acciones seguras de rollback derivadas del manifest |
| `--yes` | Auto-aprobar el apply sin prompting |
| `-h`, `--help` | Mostrar ayuda CLI |

## `scripts/send-telemetry.sh`

Este helper consume:

- `MANIFEST_PATH` posicional
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

Este helper consume:

- `PAYLOAD_PATH` posicional
- `TELEMETRY_ENDPOINT`
  Default: `https://telemetry.productive-k3s.io/telemetry`
- `TELEMETRY_MARKER`
- `TELEMETRY_BEARER_TOKEN`
- `TELEMETRY_MAX_RETRIES`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`
- `TELEMETRY_OUTBOX_DIR`
- `TELEMETRY_RUN_ID`

## Notas

!!! note
    El script de bootstrap es intencionalmente interactivo. La mayoría de las decisiones de instalación se piden en runtime en lugar de exponerse como una superficie enorme de flags.

!!! note
    El preflight del host es un chequeo de compatibilidad, no un instalador. Sirve para ver si el destino parece alineado con los supuestos de plataforma soportada antes de que el bootstrap empiece a cambiar cosas.

!!! note
    Si necesitás orquestación automatizada, la separación por modos más los settings registrados en el manifest son hoy los puntos de integración más estables.
