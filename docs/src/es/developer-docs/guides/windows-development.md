# Guía de desarrollo en Windows

Esta guía explica cómo puede trabajar sobre este repositorio un desarrollador que usa Windows y cómo ejecutar el flujo de validación basado en VM.

El modelo importante es:

- Windows es la estación de trabajo del desarrollador y el host de Multipass.
- El harness de pruebas del repositorio lanza una VM Linux soportada mediante Multipass.
- Los scripts del stack corren dentro de esa VM Linux.
- Los scripts no están pensados para ejecutarse directamente sobre Windows.

## Declaración de soporte

Esta herramienta fue desarrollada y validada sobre hosts Linux y VMs Linux soportadas por Multipass.

Para desarrolladores Windows, el modelo objetivo soportado es:

- usar Windows sólo como sistema operativo host
- usar Multipass para lanzar VMs Linux soportadas
- ejecutar los scripts del repositorio dentro de esas VMs Linux mediante `tests/test-in-vm.sh`

No trates esto como soporte nativo de Windows.

El mismo modelo práctico aplica a macOS: podés colaborar en el desarrollo de la herramienta desde macOS, pero eso no significa que la herramienta corra de forma nativa en macOS. El camino soportado es usar macOS sólo como host de desarrollo y validar la herramienta dentro de VMs Linux soportadas.

La ejecución nativa en Windows queda fuera de alcance porque los scripts asumen comportamiento de host Linux, como por ejemplo:

- `bash`
- `sudo`
- `systemd`
- networking Linux
- filesystems Linux
- `/etc/hosts`
- `/etc/exports`
- `k3s`
- `containerd`

## Configuración recomendada para Windows

Componentes recomendados:

- Windows 11 o una build actual de Windows 10 con virtualización habilitada
- Multipass para Windows
- WSL 2 con Ubuntu, usado como entorno shell para este repositorio
- Git dentro de WSL
- `make` dentro de WSL si querés usar targets del `Makefile`

Opcionales pero útiles:

- Windows Terminal
- VS Code con la extensión Remote - WSL

Referencias oficiales:

- Instalación de Multipass: https://documentation.ubuntu.com/multipass/en/latest/how-to-guides/install-multipass/
- Drivers de Multipass: https://documentation.ubuntu.com/multipass/latest/explanation/driver/
- Instalación de WSL: https://learn.microsoft.com/windows/wsl/install

## Por qué se recomienda WSL

El harness de pruebas está escrito en Bash y usa paths estilo Linux.

Usar WSL ofrece la experiencia de desarrollo más cercana al flujo Ubuntu/Linux que ya usa este repositorio.

Flujo recomendado:

1. Instalar Multipass en Windows.
2. Instalar WSL 2 con Ubuntu.
3. Clonar este repositorio dentro del filesystem de WSL.
4. Ejecutar `tests/test-in-vm.sh` desde WSL.
5. Dejar que Multipass cree y destruya las VMs Ubuntu.

Evitá clonar el repositorio bajo `/mnt/c/...` salvo que tengas una razón específica.

Preferí un path nativo de WSL, por ejemplo:

```bash
mkdir -p ~/src
cd ~/src
git clone <repo-url> productive-k3s-core
cd productive-k3s
```

Esto evita problemas comunes de paths, permisos, performance y finales de línea.

## Flujo base de validación desde Windows

Empezá con checks baratos antes de correr el stack completo.

### 1. Confirmar que Multipass es alcanzable

Desde WSL:

```bash
multipass version
multipass list
```

Si `multipass` no aparece desde WSL, probá:

```bash
multipass.exe version
multipass.exe list
```

Si sólo funciona `multipass.exe`, agregá un alias de shell en WSL:

```bash
alias multipass=multipass.exe
```

Para hacerlo persistente, agregalo a `~/.bashrc`.

### 2. Ejecutar el perfil smoke en VM

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke
```

Éste es el primer check a correr desde Windows. Valida que:

- WSL puede ejecutar el harness Bash de pruebas
- Multipass es alcanzable
- se puede lanzar una VM
- el repositorio puede transferirse a la VM
- funciona el camino de bootstrap dry-run

### 3. Ejecutar el perfil core en VM

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core
```

Esto valida el camino mínimo de instalación:

- lanzamiento de la VM
- transferencia del repositorio
- `k3s`
- `helm`
- validación básica

### 4. Ejecutar los perfiles full

Después de que `smoke` y `core` pasen:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

Estos perfiles son más lentos y pesados. Instalan y validan el stack completo dentro de una VM Linux soportada.

Los ejemplos base de esta guía usan Ubuntu `24.04`, pero el harness también soporta:

- Ubuntu `22.04`
- Debian `12`
- Debian `13`

## Selección de la imagen Ubuntu

La imagen de VM por defecto es Ubuntu `24.04`.

Para probar Ubuntu `22.04`:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile core
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile full
```

Usalo cuando quieras validar compatibilidad con el baseline actual de host real.

## Preservar una VM fallida

Por defecto, el harness elimina la VM al final de la corrida.

Para conservar la VM para troubleshooting:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --keep-vm
```

Después inspeccionala:

```bash
multipass shell <vm-name>
```

Dentro de la VM:

```bash
cd /home/ubuntu/productive-k3s-core
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl get ingress -A
sudo k3s kubectl get sc
```

## Limpieza de VMs de prueba

Eliminar una VM:

```bash
./tests/test-in-vm-cleanup.sh --name <vm-name>
```

Eliminar todas las VMs creadas por el repositorio:

```bash
./tests/test-in-vm-cleanup.sh --all
```

Eliminar y purgar instancias ya borradas:

```bash
./tests/test-in-vm-cleanup.sh --all --purge
```

Comandos directos de Multipass:

```bash
multipass list
multipass delete <vm-name>
multipass purge
```

El helper de cleanup sólo apunta a VMs cuyos nombres empiezan con:

```text
productive-k3s-core-test-
```

## Lectura de resultados de prueba

Las pruebas de VM escriben artefactos bajo:

```bash
test-artifacts/
```

La fuente de verdad de pass/fail es el artefacto de resultado:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json'
```

Para ver resultados recientes:

```bash
ls -1t test-artifacts/*.json | head
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, image, vm_name}'
```

Las corridas exitosas deberían mostrar:

```json
"status": "success"
```

No uses `*-bootstrap-manifest.json` como indicador principal de pass/fail. Esos archivos describen la corrida del bootstrap, no el perfil completo de prueba en VM.
