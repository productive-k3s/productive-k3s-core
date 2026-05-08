# Plataforma soportada Ubuntu 22.04

Este documento registra el baseline de validación soportado para Ubuntu 22.04.

Ubuntu 22.04 está soportado para este repositorio junto con Ubuntu 24.04, Debian 12 y Debian 13.

## Estado actual

Estado: soportado

Release objetivo:

- Ubuntu `22.04` LTS

Evidencia de validación retenida:

- `smoke`: pasó con artefacto `status: "success"`
- `core`: pasó con artefacto `status: "success"`
- `full`: pasó con artefacto `status: "success"`
- `full-rollback`: pasó con artefacto `status: "success"`
- `full-clean`: pasó con artefacto `status: "success"`

Interpretación:

- Ubuntu 22.04 está validado para bootstrap, convergencia de validación estricta, rollback y limpieza destructiva
- Ubuntu 22.04 debe tratarse como una plataforma soportada, no como candidata

## Alcance

El modelo validado es:

- host: cualquier máquina capaz de ejecutar Multipass
- guest VM: imagen Ubuntu 22.04
- scripts: ejecutados dentro de la VM Ubuntu 22.04

## Defaults del harness

El harness de VM soporta:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04
```

Cuando se usa `--platform ubuntu`, el harness deja por defecto:

- image: `24.04`
- remote user: `ubuntu`
- remote directory: `/home/ubuntu/productive-k3s-core`

Para validar Ubuntu 22.04 específicamente, overrideá la image:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --remote-user ubuntu --remote-dir /home/ubuntu/productive-k3s-core
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
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile smoke
```

### 2. Core

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile core
```

### 3. Full

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile full
```

### 4. Full rollback

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile full-rollback
```

### 5. Full clean

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile full-clean
```

## Revisión de artefactos

Revisar artefactos Ubuntu 22.04:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*ubuntu*.json' ! -name '*-bootstrap-manifest.json' | sort | tail
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*ubuntu*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, platform, image, remote_user, remote_dir, vm_name}'
```

Criterios de aprobación:

- cada perfil soportado tiene `status: "success"`
- cada perfil soportado tiene `platform: "ubuntu"`
- `image` debería coincidir con `22.04`

Usá el artefacto `test-in-vm-*.json` como señal autoritativa de pass/fail.
