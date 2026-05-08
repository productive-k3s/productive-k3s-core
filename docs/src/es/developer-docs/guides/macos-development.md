# Guía de desarrollo en macOS

Esta guía explica cómo puede trabajar sobre este repositorio un desarrollador que usa macOS y cómo ejecutar el flujo de validación basado en VM.

El modelo importante es:

- macOS es la estación de trabajo del desarrollador y el host de Multipass
- el harness de pruebas del repositorio lanza una VM Linux soportada mediante Multipass
- los scripts del stack corren dentro de esa VM Linux
- los scripts no están pensados para ejecutarse directamente sobre macOS

## Declaración de soporte

Esta herramienta fue desarrollada y validada sobre hosts Linux y VMs Linux soportadas por Multipass.

Para desarrolladores macOS, el modelo objetivo soportado es:

- usar macOS sólo como sistema operativo host
- usar Multipass para lanzar VMs Linux soportadas
- ejecutar los scripts del repositorio desde el shell de macOS mediante `tests/test-in-vm.sh`

No trates esto como soporte nativo de macOS.

Podés colaborar en el desarrollo de la herramienta desde macOS, pero eso no significa que la herramienta corra de forma nativa en macOS. El camino soportado es usar macOS sólo como host de desarrollo y validar la herramienta dentro de VMs Linux soportadas.

La ejecución nativa en macOS queda fuera de alcance porque los scripts asumen comportamiento de host Linux, como por ejemplo:

- `bash`
- `sudo`
- `systemd`
- networking Linux
- filesystems Linux
- `/etc/hosts`
- `/etc/exports`
- `k3s`
- `containerd`

## Configuración recomendada para macOS

Componentes recomendados:

- macOS `13.3` o posterior
- Multipass para macOS
- Terminal o iTerm2
- Git
- `make` si querés usar targets del `Makefile`

Opcionales pero útiles:

- VS Code
- VirtualBox sólo si querés usarlo de forma intencional en lugar del backend por defecto de Multipass

Referencias oficiales:

- Instalación de Multipass: https://documentation.ubuntu.com/multipass/en/latest/how-to-guides/install-multipass
- Drivers de Multipass: https://documentation.ubuntu.com/multipass/latest/explanation/driver/
- Configuración del driver: https://documentation.ubuntu.com/multipass/latest/how-to-guides/customise-multipass/set-up-the-driver

## Por qué se recomienda este modelo

El harness de pruebas está escrito en Bash y espera comportamiento estilo Linux en la máquina de destino.

En macOS, la forma limpia de trabajar con este repositorio es:

1. instalar Multipass en macOS
2. clonar este repositorio localmente
3. ejecutar `tests/test-in-vm.sh` desde el shell de macOS
4. dejar que Multipass cree y destruya VMs Linux soportadas

Esto mantiene separado el host de desarrollo del runtime soportado.

## Flujo base de validación desde macOS

Empezá con checks baratos antes de correr el stack completo.

### 1. Confirmar que Multipass es alcanzable

Desde Terminal:

```bash
multipass version
multipass list
```

A diferencia de Windows, acá no existe un path estilo `multipass.exe`. La CLI normal `multipass` debería estar disponible directamente en el shell de macOS.

### 2. Ejecutar el perfil smoke en VM

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke
```

Éste es el primer check a correr desde macOS. Valida que:

- el harness Bash de pruebas corre desde el shell de macOS
- Multipass es alcanzable
- se puede lanzar una VM
- el repositorio se puede transferir a la VM
- funciona el camino de bootstrap dry-run

### 3. Ejecutar el perfil core en VM

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core
```

Esto valida el camino mínimo de instalación:

- lanzamiento de VM
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

## Selección de la imagen Ubuntu de la VM

La imagen de VM por defecto es Ubuntu `24.04`.

Para probar Ubuntu `22.04`:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile core
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile full
```

Usá esto cuando quieras validar compatibilidad con el baseline actual de host real.

## Conservar una VM fallida

Por defecto, el harness de pruebas borra la VM al terminar.

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

Borrar una VM:

```bash
./tests/test-in-vm-cleanup.sh --name <vm-name>
```

Borrar todas las VMs de prueba creadas por el repositorio:

```bash
./tests/test-in-vm-cleanup.sh --all
```

Borrar y purgar instancias eliminadas:

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

Las pruebas en VM escriben artefactos bajo:

```bash
test-artifacts/
```

La fuente de verdad de pass/fail es el artefacto de resultado de prueba:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json'
```

Revisar resultados recientes:

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

## Troubleshooting común

### `multipass: command not found`

Chequeá:

- Multipass está instalado en macOS
- abriste un shell nuevo después de instalarlo
- el binario `multipass` está en el `PATH` de tu shell

Si hace falta:

```bash
which multipass
```

### Multipass no puede lanzar una VM

Chequeá:

- hay CPU, RAM y disco suficientes
- las capacidades de virtualización de macOS están disponibles
- Multipass tiene los permisos que necesita
- herramientas corporativas de seguridad no están bloqueando la creación de VMs

Según la documentación oficial de Multipass, macOS usa `qemu` como driver por defecto. VirtualBox es opcional si querés elegirlo de forma intencional.

Si el lanzamiento falla al recuperar metadata de imágenes o descargar una imagen, refrescá la metadata de Multipass y probá de nuevo:

```bash
multipass find --force-update
```

Después reintentá el comando de prueba.

### La VM levanta pero la red falla

Síntomas:

- fallan instalaciones de paquetes
- fallan descargas de charts
- fallan checks de endpoints
- no funciona DNS dentro de la VM

Chequeá:

- software VPN
- proxy corporativo
- firewall de macOS o herramientas de filtrado de red
- configuración DNS
- si la VM puede llegar a internet:

```bash
multipass exec <vm-name> -- ping -c 3 1.1.1.1
multipass exec <vm-name> -- getent hosts github.com
```

### `multipass transfer` falla

Chequeá:

- paths con espacios
- permisos restrictivos
- problemas de quoting del shell
- paths demasiado largos

Ejemplo recomendado de path del repositorio:

```bash
~/src/productive-k3s-core
```

### Los perfiles full son lentos

Esperable.

Los perfiles full instalan:

- `k3s`
- `helm`
- `cert-manager`
- `Longhorn`
- `Rancher`
- registry interno
- servidor NFS

Corré primero `smoke` y `core`. Corré los perfiles full sólo cuando pasen los checks más baratos.

### El disco de la VM se llena

Aumentá el tamaño de disco:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --disk 60G
```

Para pruebas repetidas del stack completo, usá al menos:

- CPU: `4`
- memory: `8G`
- disk: `40G`

Más margen es mejor para `full`, `full-rollback` y `full-clean`.

### La prueba falla pero la VM fue borrada

Relanzá con:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile <profile> --keep-vm
```

Después inspeccioná con:

```bash
multipass shell <vm-name>
```

## Qué no hacer

No ejecutes el bootstrap de producción directamente sobre macOS.

No intentes instalar `k3s`, Longhorn, Rancher o NFS directamente sobre macOS mediante estos scripts.

No asumas que la validación hosteada desde macOS con Multipass está completa hasta que los mismos artefactos de perfiles de VM reporten `status: "success"`.

## Checklist recomendado para contribuidores

Para un contribuidor de macOS validando cambios:

1. Instalar Multipass en macOS.
2. Clonar el repositorio localmente.
3. Confirmar que `multipass version` funcione.
4. Correr `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke`.
5. Correr `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core`.
6. Correr `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full` cuando haga falta.
7. Correr `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback` para cambios de rollback.
8. Correr `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean` para cambios de cleanup.
9. Confirmar que los JSON de artefactos relevantes reporten `status: "success"`.
10. Limpiar con `./tests/test-in-vm-cleanup.sh --all --purge`.

## Estado de la documentación

Esta guía describe el flujo esperado para contribuidores desde macOS.

El repositorio sigue siendo Ubuntu-first en sus ejemplos y en CI hosteado. macOS debe considerarse sólo como host de desarrollo soportado para disparar pruebas basadas en VMs Linux soportadas mediante Multipass, no como target nativo de runtime para los scripts del stack.
