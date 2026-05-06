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

Si querés ver cómo se ejecutaría el instalador antes de cambiar algo en la máquina, primero podés hacer un `dry-run` opcional:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/vX.Y.Z/install-productive-k3s.sh | bash -s -- --dry-run
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
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/vX.Y.Z/install-productive-k3s.sh | bash
```

Ese instalador descarga el bundle correspondiente a ese release y ejecuta el bootstrap sobre el host.

## Después de instalar

Cuando el bootstrap termina, usá la documentación de validación y referencia para inspeccionar el resultado:

- [Verificaciones de k3s](../reference/k3s-checks.md)
- [Verificaciones de ingress](../reference/ingress-checks.md)
- [Verificaciones de Rancher](../reference/rancher-checks.md)
- [Verificaciones del registry](../reference/registry-checks.md)
- [Verificaciones de Longhorn](../reference/longhorn-checks.md)
- [Verificaciones de certificados](../reference/certificate-checks.md)
