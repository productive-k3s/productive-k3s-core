# Cómo usar Productive K3S

La forma más simple de usar `productive-k3s` es ejecutar el instalador del release sobre una de las [plataformas soportadas](supported-platforms.md), en un host o una VM con esos sistemas operativos.

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
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/vX.Y.Z/productive-k3s-cli.sh | bash -s -- preflight
```

Si querés que también fallen los warnings, usá:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/vX.Y.Z/productive-k3s-cli.sh | bash -s -- preflight --strict
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
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/vX.Y.Z/productive-k3s-cli.sh | bash -s -- bootstrap --dry-run
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

## Instalación básica

Reemplazá `vX.Y.Z` por el release que quieras instalar:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/vX.Y.Z/productive-k3s-cli.sh | bash -s -- bootstrap
```

Ese instalador descarga el bundle correspondiente a ese release y ejecuta sobre el host el CLI público de `productive-k3s`.

## Después de instalar

Cuando el bootstrap termina, usá la documentación de validación y referencia para inspeccionar el resultado:

- [Preflight del host](../user-docs/host-preflight.md)
- [Verificaciones de k3s](../user-docs/k3s-checks.md)
- [Verificaciones de ingress](../user-docs/ingress-checks.md)
- [Verificaciones de Rancher](../user-docs/rancher-checks.md)
- [Verificaciones del registry](../user-docs/registry-checks.md)
- [Verificaciones de Longhorn](../user-docs/longhorn-checks.md)
- [Verificaciones de certificados](../user-docs/certificate-checks.md)
