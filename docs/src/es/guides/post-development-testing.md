# Guía de pruebas después de cambios

Esta guía define la secuencia recomendada de validación después de hacer cambios en este repositorio.

El objetivo es mantener un camino de pruebas consistente para que cambios en bootstrap, validación, rollback, cleanup, documentación o scripts auxiliares se revisen en un orden predecible.

## Alcance

Usá esta guía después de cambios en:

- `scripts/bootstrap-k3s-stack.sh`
- `scripts/validate-k3s-stack.sh`
- `scripts/rollback-k3s-stack.sh`
- `scripts/clean-k3s-stack.sh`
- `tests/test-in-vm.sh`
- `tests/test-in-docker.sh`
- `utils/`
- `docs/`
- `Makefile`

## Secuencia recomendada

Ejecutá los checks en este orden.

### 1. Smoke test en Docker

Chequeo rápido de sanidad para el harness de bootstrap y el empaquetado del repositorio.

```bash
make test-smoke
```

Qué cubre:

- contexto de build en Docker
- harness de smoke containerizado
- camino de dry-run del bootstrap

### 2. Test core en VM

Valida el camino mínimo de instalación con `k3s` y `helm`, sin forzar el stack opcional completo.

```bash
make test-core
```

Qué cubre:

- provisión de la VM
- copia del repositorio dentro de la VM
- camino mínimo de instalación del bootstrap
- validación no estricta del perfil core

Resultado esperado:

- éxito con posibles warnings por componentes opcionales omitidos

### 3. Test full en VM

Valida el camino de instalación del stack completo.

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
```

Qué cubre:

- `k3s`
- `helm`
- `cert-manager`
- `Longhorn`
- `Rancher`
- registry interno
- configuración de NFS
- convergencia de validación estricta

Resultado esperado:

- éxito con `Failures: 0`
- la validación estricta converge limpiamente

### 4. Test full-rollback

Valida el rollback guiado por manifiesto después de una instalación full.

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
```

Qué cubre:

- camino completo de bootstrap
- generación del plan de rollback
- aplicación del flujo de rollback
- remoción de componentes del stack instalados por la corrida de prueba

Resultado esperado:

- el rollback completa
- los namespaces y recursos cluster-scoped objetivo se eliminan como corresponde
- el artefacto de prueba termina con `status: "success"`
- los checks post-rollback confirman la remoción de:
  - `cert-manager`
  - `longhorn-system`
  - `cattle-system`
  - `registry`
  - `selfsigned` `ClusterIssuer`
  - export NFS administrado por el bootstrap
  - entradas `/etc/hosts` administradas por el bootstrap

### 5. Test full-clean

Valida la limpieza destructiva después de una instalación full.

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

Qué cubre:

- camino completo de bootstrap
- flujo de cleanup destructivo
- camino de uninstall/cleanup de `k3s`

Resultado esperado:

- el cleanup completa
- `k3s` ya no está activo en la VM

### 6. Limpieza de VMs

Si quedan VMs de prueba, eliminarlas explícitamente.

```bash
./tests/test-in-vm-cleanup.sh
```

Checks de seguimiento útiles:

```bash
ls -1 test-artifacts
multipass list
```

## Referencia rápida de Multipass

Este repositorio usa `multipass` sólo como harness de VM del lado host para pruebas de integración.

Los comandos mínimos que suelen necesitar los contribuidores son estos.

### Verificar que Multipass está disponible

```bash
multipass version
multipass list
multipass find --force-update
```

Usalo antes de arrancar pruebas basadas en VM.

`multipass find --force-update` es especialmente útil cuando Multipass falla al refrescar metadata de imágenes o al descargar una imagen de VM.

### Ejecutar un perfil de prueba en VM

Perfil core:

```bash
make test-core
```

Perfiles full:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

### Preservar una VM para inspección manual

Si querés que la VM de prueba quede viva después de la corrida:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --keep-vm
```

Esto es útil cuando una prueba falla y querés inspeccionar la máquina manualmente.

### Abrir una shell en una VM preservada

```bash
multipass shell <vm-name>
```

Checks típicos dentro de la VM:

```bash
cd /home/ubuntu/productive-k3s
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
```

### Eliminar una VM preservada

```bash
./tests/test-in-vm-cleanup.sh --name <vm-name>
```

Comando directo equivalente de `multipass`:

```bash
multipass delete <vm-name>
```

### Eliminar todas las VMs de prueba creadas por este repositorio

```bash
./tests/test-in-vm-cleanup.sh --all
```

## Criterios de aprobación

Un cambio se considera validado cuando:

- la secuencia de pruebas relevante termina con éxito
- la validación del perfil full converge limpiamente
- las pruebas de rollback o clean pasan cuando el cambio toca la lógica de teardown
- la validación local sigue comportándose como se espera para cambios del lado host

## Documentación relacionada

- [Resumen de guías](index.md)
- [Verificaciones de k3s](../reference/k3s-checks.md)
- [Verificaciones de ingress](../reference/ingress-checks.md)
- [Verificaciones de Rancher](../reference/rancher-checks.md)
- [Verificaciones del registry](../reference/registry-checks.md)
- [Verificaciones de Longhorn](../reference/longhorn-checks.md)
- [Verificaciones de certificados](../reference/certificate-checks.md)
