# Targets De Make Para Desarrollo

El repositorio expone un `Makefile` pequeño en la raíz más un `Makefile` de matriz más grande bajo `tests/`.

## Targets de raíz

Estos son los entrypoints de uso diario más comunes desde la raíz del repositorio.

| Target | Propósito |
| --- | --- |
| `make preflight` | Ejecutar los chequeos de preflight del host con guía en nivel warning |
| `make preflight-strict` | Ejecutar los chequeos de preflight del host y fallar también por warnings |
| `make bootstrap` | Ejecutar el flujo interactivo de bootstrap en su modo default `single-node` |
| `make dry-run` | Ejecutar el bootstrap en modo planificación sin aplicar cambios |
| `make backup` | Capturar un snapshot de backup del host y del clúster |
| `make validate` | Ejecutar el validador del stack |
| `make validate-strict` | Tratar warnings como fallos en la validación |
| `make docs-build` | Construir el sitio MkDocs en modo estricto |
| `make docs-serve` | Servir la documentación localmente |
| `make docs-up` | Levantar el servidor de docs en background |
| `make docs-down` | Detener el servidor local de docs y limpiar artefactos |
| `make docs-clean` | Limpiar artefactos de docs y el virtualenv local de docs |

## Targets de tests puntuales

El `Makefile` raíz también expone algunos entrypoints de tests cómodos para desarrollo:

| Target | Propósito |
| --- | --- |
| `make test-preflight-host` | Verificar la CLI del preflight del host, su salida JSON y el comportamiento de strict mode |
| `make test-bootstrap-modes` | Verificar que la ayuda CLI y la validación de modos de bootstrap se comporten correctamente |
| `make test-agent-smoke` | Ejercitar el modo `agent` dentro de Docker |
| `make test-smoke` | Ejecutar un smoke check del bootstrap dry-run basado en Docker |
| `make test-core` | Ejecutar el perfil VM `core` sobre Ubuntu `24.04` |
| `make test-core-debian12` | Ejecutar el perfil VM `core` sobre Debian `12` |
| `make test-core-debian13` | Ejecutar el perfil VM `core` sobre Debian `13` |

## Targets de matriz

Para una cobertura más amplia, el `Makefile` raíz delega en `tests/Makefile`:

| Target | Propósito |
| --- | --- |
| `make test-matrix-smoke` | Ejecutar la matriz `smoke` sobre Ubuntu y Debian |
| `make test-matrix-core` | Ejecutar la matriz `core` sobre Ubuntu y Debian |
| `make test-matrix-full` | Ejecutar la matriz `full` sobre Ubuntu y Debian |
| `make test-matrix-full-rollback` | Ejecutar la matriz `full-rollback` sobre Ubuntu y Debian |
| `make test-matrix-full-clean` | Ejecutar la matriz `full-clean` sobre Ubuntu y Debian |
| `make test-matrix-all` | Ejecutar todos los perfiles de matriz en secuencia |

## Targets útiles directos de `tests/Makefile`

Cuando necesitás un loop de iteración más chico, usá `make -C tests ...`.

Ejemplos:

- `make -C tests smoke-ubuntu-24.04`
- `make -C tests core-debian12`
- `make -C tests full-rollback-ubuntu-22.04`
- `make -C tests clean-test-artifacts`

## Notas

!!! note
    Los targets de raíz son entrypoints de conveniencia. La granularidad más fina de la matriz vive en `tests/Makefile`.

!!! note
    Para trabajo de documentación, `make docs-build` es el chequeo final más seguro porque ejecuta MkDocs en modo estricto.
