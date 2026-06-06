# Cómo usar Productive K3S Core

La forma más simple de usar `productive-k3s-core` es ejecutar el instalador del release sobre una de las [plataformas soportadas](supported-platforms.md), en un host o una VM con esos sistemas operativos.

Comandos requeridos en el host o la VM para este camino de instalación:

- `bash`
- `sudo`
- `curl`
- `tar`
- `sha256sum`
- `mktemp`

## Antes de instalar

Antes de correr el bootstrap, podés validar si el host destino coincide con los supuestos públicos de plataforma y con la guía de hardware:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- preflight
```

Si querés que también fallen los warnings, usá:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- preflight --strict
```

Este preflight chequea la lista de plataformas soportadas, la expectativa de `systemd`, los comandos requeridos y la guía práctica de hardware para el modo seleccionado.

Si ya tenés el repositorio clonado localmente, los targets equivalentes del root siguen disponibles:

```bash
make preflight
make preflight-strict
```

Ver [Preflight del host](../user-docs/host-preflight.md) para el comportamiento detallado.

Si querés ver cómo se ejecutaría el instalador antes de cambiar algo en la máquina, primero podés hacer un `dry-run` opcional:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- apply --dry-run
```

Incluso en `dry-run`, el script puede seguir mostrando prompts según lo que detecte en el host, por ejemplo si una instalación existente de `k3s` debería reutilizarse. Esos prompts se usan para armar el plan de ejecución, pero el `dry-run` igualmente no aplica cambios.

## Qué pasará en el host

El bootstrap está pensado para correr directamente sobre la máquina de destino. Puede:

- instalar paquetes faltantes del sistema con `apt-get`
- instalar o reutilizar `k3s`
- instalar o reutilizar `helm`
- configurar los componentes del stack local de nodo único

Por defecto, el destino práctico es una única VM soportada o un host Linux soportado.

Esto no está pensado para cualquier distribución Linux. El destino tiene que coincidir con la página de [plataformas soportadas](supported-platforms.md), ya sea como host real o como VM.

## Engine opcional de instalación

El engine por default y esperado es el camino nativo de bootstrap del repositorio.

También existe una variable de entorno opcional y experimental:

```bash
PRODUCTIVE_K3S_ENGINE=native|k3sup
```

- `native`: camino default y principal soportado
- `k3sup`: backend experimental opcional para la etapa base de instalación de K3S

`k3sup` se integró como una opción complementaria, no como un reemplazo de `productive-k3s-core`.
Su propósito es permitir que usuarios avanzados experimenten con las mismas decisiones de bootstrap y stack de Productive K3S usando una herramienta de instalación de K3S con la que ya se sientan cómodos.

Límites importantes de scope:

- `productive-k3s-core` sigue siendo la capa de bootstrap, validación y operaciones
- `k3sup` sólo afecta el backend de instalación base de K3S
- el comportamiento del stack después de que K3S existe no cambia
- las garantías de soporte siguen siendo las documentadas en la matriz soportada del repositorio

Si usás `PRODUCTIVE_K3S_ENGINE=k3sup`, tratá ese camino como experimental.
En flujos de nodos separados o en orquestaciones manuales, la responsabilidad de pasar el contexto SSH correcto y el entorno relacionado cuando ese backend lo necesite es tuya.
Eso no amplía la matriz pública de soporte hacia plataformas arbitrarias ni hacia modelos arbitrarios de orquestación.

## Instalación básica

Reemplazá `X.Y.Z` por el release que quieras instalar:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- apply
```

Ese instalador descarga el bundle correspondiente a ese release y ejecuta sobre el host el CLI público de `productive-k3s-core`.

## Después de instalar

Cuando el bootstrap termina, usá la documentación de validación y referencia para inspeccionar el resultado:

- [Preflight del host](../user-docs/host-preflight.md)
- [Verificaciones de k3s](../user-docs/k3s-checks.md)
- [Verificaciones de ingress](../user-docs/ingress-checks.md)
- [Verificaciones de Rancher](../user-docs/rancher-checks.md)
- [Verificaciones del registry](../user-docs/registry-checks.md)
- [Verificaciones de Longhorn](../user-docs/longhorn-checks.md)
- [Verificaciones de certificados](../user-docs/certificate-checks.md)
