# GitHub Actions y automatización de releases

Este documento define el modelo de automatización del repositorio para releases y validación hosteada en CI.

## Alcance

Hay dos workflows separados:

1. empaquetado y publicación de releases
2. validación hosteada en GitHub

Deben seguir separados.

No mezcles publicación de releases con validación en un mismo workflow.

## Por qué la validación hosteada es limitada

El camino de CI de GitHub Actions no usa Multipass.

El objetivo de CI hosteado se divide en dos capas:

- una matriz `smoke` containerizada para distribuciones base soportadas
- una validación full hosteada directamente sobre `ubuntu-24.04`

Esto da una señal de CI mucho más fuerte que un dry-run, pero sigue siendo diferente de la validación local con Multipass porque no ejercita el harness de VM en sí mismo.

No reemplaza las pruebas locales con Multipass para:

- bootstrap real sobre VM
- validación de rollback
- validación sobre VMs Debian

## Modelo de runners

Workflow de release:

- runner Ubuntu hosteado por GitHub

Workflow de validación hosteada:

- runner `ubuntu-24.04` hosteado por GitHub

Motivo:

- evita depender de virtualización anidada en runners hosteados por GitHub
- mantiene el workflow reproducible y de bajo mantenimiento
- deja el camino pesado de Multipass del lado local, donde el repositorio ya tiene tooling específico

## Workflow de release

Trigger:

- push de un tag de versión como `1.2.3`

Guard:

- el commit del tag debe ser alcanzable desde `origin/main`

Outputs:

- `productive-k3s-<tag>.tar.gz`
- `productive-k3s-<tag>.tar.gz.sha256`
- `productive-k3s-cli.sh`

El workflow de release crea un GitHub Release y sube esos archivos como assets.

El script instalador queda versionado por release y puede usarse así:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- bootstrap
```

Ahora el instalador expone la misma familia de comandos operativos que el CLI público incluido dentro del bundle. Por ejemplo:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- preflight
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- validate --strict
```

Todavía pueden pasarse flags adicionales al bootstrap:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- bootstrap --dry-run
```

## Workflow de validación hosteada

Trigger:

- pull request contra `main`
- tipos de actividad:
  - `opened`
  - `reopened`
  - `ready_for_review`
  - `synchronize`
- dispatch manual opcional

Notas:

- se vuelve a ejecutar cuando se empujan nuevos commits a la rama del PR
- los draft PR se omiten hasta que pasan a ready for review

El workflow debería ofrecer estos jobs:

1. `smoke-matrix`

- corre sobre `ubuntu-24.04`
- ejecuta `tests/test-in-docker.sh` contra estas base images:
  - `ubuntu:24.04`
  - `ubuntu:22.04`
  - `debian:12`
  - `debian:13`
- sube un log smoke por cada pata de la matriz

2. `hosted-full-ubuntu-24.04`

- corre sobre `ubuntu-24.04`
- ejecuta shell syntax checks
- corre el bootstrap full directamente sobre el host del runner
- corre `scripts/validate-k3s-stack.sh --strict`
- corre `scripts/clean-k3s-stack.sh --apply`
- sube `test-artifacts/` y `runs/` como workflow artifacts
- falla si `test-artifacts/hosted-validation-summary.json` no termina con `status == "success"`

Todavía no existe un workflow `core` containerizado.

Motivo:

- el repositorio ya tiene un harness containerizado honesto para `smoke`
- todavía no tiene un harness containerizado igual de honesto para una instalación real `core`
- forzar `core` dentro de un container en GitHub Actions produciría una señal más débil y potencialmente engañosa porque `k3s`, la gestión de servicios y el networking del host no se modelan igual ahí

## Validación pesada local

Las siguientes validaciones siguen siendo responsabilidad local:

- `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full`
- `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback`
- `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean`
- `./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile ...`
- `make test-matrix-core`
- `make test-matrix-full`
- `make test-matrix-full-rollback`
- `make test-matrix-full-clean`

Esos checks siguen siendo la fuente de verdad para el comportamiento real de instalación y teardown.
