# Guía de pruebas después de cambios

Esta página define el workflow local por default para correr tests después de hacer cambios en `productive-k3s-core`.

La idea es simple:

1. arrancar desde un estado local limpio de tests
2. correr el target de test que te interese
3. pedirle al repositorio un resumen de qué tests pasaron y cuáles fallaron

## Workflow local recomendado

Para el desarrollo diario, usá esta secuencia desde la raíz del repositorio:

```bash
make test-clean
make <test-target>
make test-checkstatus
```

Ejemplo:

```bash
make test-clean
make test-matrix-all
make test-checkstatus
```

## Qué hace cada target

### `make test-clean`

Elimina los archivos locales que este repositorio usa como estado de tests:

- `test-artifacts/`
- `runs/apply-*.json` locales
- `runs/telemetry-outbox/bootstrap-*.json` locales
- `runs/telemetry-outbox/bootstrap-*.status` locales

Usalo antes de empezar un nuevo ciclo de validación cuando querés que `make test-checkstatus` describa sólo la corrida actual.

### `make test-checkstatus`

Recorre los artifacts de resultados actuales bajo `test-artifacts/` e imprime un resumen corto de los estados registrados.

Reporta entradas como:

- resultados de tests en VM escritos por `tests/test-in-vm.sh`
- resultados de resumen hosted escritos por `tests/test-on-gh-hosted.sh`

Ignora a propósito archivos que no son el resultado top-level real del test:

- manifests copiados de bootstrap como `*-apply-manifest.json`
- artifacts públicos saneados como `*-public.json`

Si al menos un resultado registrado está en fallo, `make test-checkstatus` termina con exit code no cero.

Si no hay artifacts de resultado, también termina con exit code no cero e indica que no pudo determinar el estado.

## Targets de test más comunes

Estos son los targets root que más suelen usarse:

| Target | Propósito |
| --- | --- |
| `make test-smoke` | Validación rápida smoke basada en Docker |
| `make test-core` | Validación VM del perfil core sobre Ubuntu `24.04` |
| `make test-core-debian12` | Validación VM del perfil core sobre Debian `12` |
| `make test-core-debian13` | Validación VM del perfil core sobre Debian `13` |
| `make test-matrix-smoke` | Matriz smoke sobre Ubuntu y Debian |
| `make test-matrix-core` | Matriz core sobre Ubuntu y Debian |
| `make test-matrix-full` | Matriz full stack sobre Ubuntu y Debian |
| `make test-matrix-full-rollback` | Matriz full rollback sobre Ubuntu y Debian |
| `make test-matrix-full-clean` | Matriz full cleanup sobre Ubuntu y Debian |
| `make test-matrix-all` | Ejecuta todos los perfiles de matriz en secuencia y conserva todos los artifacts de resultado para revisar el estado final |

## Por qué `test-matrix-all` es especial

Los perfiles de matriz bajo `tests/Makefile` siguen validando cada perfil por separado, pero el camino agregado `run-all-tests` ahora limpia sólo una vez al principio.

Eso permite que este workflow funcione como esperás:

```bash
make test-clean
make test-matrix-all
make test-checkstatus
```

Al final de esa secuencia, `test-checkstatus` todavía puede ver los artifacts acumulados de la corrida completa de matriz, en lugar de quedarse sólo con el último perfil.

## Cuando un test falla

Arrancá por:

```bash
make test-checkstatus
```

Después inspeccioná los archivos de artifact correspondientes en `test-artifacts/`.

Comandos útiles de seguimiento:

```bash
ls -1 test-artifacts
jq . test-artifacts/<artifact>.json
```

Para fallos en VM, podés preservar la VM cuando haga falta:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --keep-vm
```

Y después inspeccionarla:

```bash
multipass shell <vm-name>
cd /home/ubuntu/productive-k3s-core
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
```

## Notas

!!! note
    `make test-checkstatus` resume resultados registrados. No reemplaza leer el JSON completo del artifact cuando necesitás contexto detallado de debugging.

!!! note
    `make test-clean` elimina sólo el estado local de tests de este repositorio. No borra VMs de Multipass preservadas. Para eso usá `./tests/test-in-vm-cleanup.sh`.
