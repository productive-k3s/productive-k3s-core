# Plataforma soportada Debian 12

Este documento registra el baseline de validación soportado para Debian 12.

Debian 12 está soportado para este repositorio junto con Ubuntu 22.04, Ubuntu 24.04 y Debian 13.

## Estado actual

Estado: soportado

Release objetivo:

- Debian 12 `bookworm`

Evidencia de validación retenida:

- `smoke`: pasó con artefacto `status: "success"`
- `core`: pasó con artefacto `status: "success"`
- `full`: pasó con artefacto `status: "success"`
- `full-rollback`: pasó con artefacto `status: "success"`
- `full-clean`: pasó con artefacto `status: "success"`

Interpretación:

- Debian 12 está validado para bootstrap, convergencia de validación estricta, rollback y limpieza destructiva
- Debian 12 debe tratarse como una plataforma soportada, no como candidata

## Alcance

El modelo validado es:

- host: cualquier máquina capaz de ejecutar Multipass
- guest VM: imagen cloud de Debian 12
- scripts: ejecutados dentro de la VM Debian 12

## Defaults del harness

El harness de VM soporta:

```bash
./tests/test-in-vm.sh --platform debian12
```

Cuando se usa `--platform debian12`, el harness deja por defecto:

- image: `https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2`
- remote user: `ubuntu`
- remote directory: `/home/ubuntu/productive-k3s-core`

Estos valores pueden overridearse:

```bash
./tests/test-in-vm.sh --platform debian12 --image <image-or-url> --remote-user <user> --remote-dir <path>
```

El bootstrap detecta el OS del host mediante `/etc/os-release`.

Comportamiento actual:

- Ubuntu: soportado
- Debian 12: soportado
- Debian 13: soportado
- cualquier otro: no soportado

## Secuencia de validación soportada

Comandos de referencia:

### 1. Smoke

```bash
./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile smoke
```

### 2. Core

```bash
./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile core
```

### 3. Full

```bash
./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile full
```

### 4. Full rollback

```bash
./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile full-rollback
```

### 5. Full clean

```bash
./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile full-clean
```

## Revisión de artefactos

Revisar artefactos Debian 12:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*debian12*.json' ! -name '*-bootstrap-manifest.json' | sort | tail
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*debian12*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, platform, image, remote_user, remote_dir, vm_name}'
```

Criterios de aprobación:

- cada perfil soportado tiene `status: "success"`
- cada perfil soportado tiene `platform: "debian12"`

Usá el artefacto `test-in-vm-*.json` como señal autoritativa de pass/fail.
