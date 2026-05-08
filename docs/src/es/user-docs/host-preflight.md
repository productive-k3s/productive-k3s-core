# Preflight Del Host

`Productive K3S Core` incluye un chequeo de compatibilidad del host que podés correr antes del bootstrap.

## Propósito

Usá esta herramienta cuando quieras responder una pregunta simple antes de instalar:

¿Este host o esta VM están alineados con los supuestos de plataforma soportada de `productive-k3s-core`?

Es especialmente útil cuando:

- validás una VM nueva antes de instalar
- chequeás si una instancia cloud reutilizada sigue coincidiendo con la baseline esperada
- querés fallar temprano en automatización antes de arrancar el bootstrap interactivo

## Uso básico

Desde la raíz del repositorio:

```bash
make preflight
```

O invocando el script directamente:

```bash
./scripts/preflight-host.sh
```

O llamando al wrapper operativo:

```bash
./productive-k3s-core.sh preflight
```

O usando el camino del instalador release sin clonar el repositorio:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- preflight
```

## Modo estricto

Por defecto, los hallazgos de nivel warning no hacen fallar el comando.

Si querés que los warnings también devuelvan código no cero:

```bash
make preflight-strict
```

O:

```bash
./productive-k3s-core.sh preflight --strict
```

## Chequeos sensibles al modo

Podés evaluar el host contra un perfil de runtime específico:

```bash
./scripts/preflight-host.sh --mode single-node
./scripts/preflight-host.sh --mode server
./scripts/preflight-host.sh --mode agent
./scripts/preflight-host.sh --mode stack
```

`single-node` es el default.

## Qué chequea

Hoy el preflight valida:

- plataforma y versión soportadas
- arquitectura de CPU soportada
- `systemd` como PID 1
- comandos requeridos como `sudo`, `curl`, `getent`, `apt-get`, `systemctl`, `tar`, `sha256sum` y `mktemp`
- postura de `sudo`
- guía práctica de hardware para `single-node` y `stack`

Hoy la baseline pública soportada es `amd64`/`x86_64`.

Arquitecturas como `arm64`/`aarch64` se reportan intencionalmente como no soportadas por ahora, incluso sobre targets Ubuntu o Debian que por lo demás serían válidos.

La guía de hardware sigue la baseline publicada de plataforma:

- mínimo práctico: `4 vCPU`, `12 GiB` de RAM, `60 GiB` libres en disco
- recomendado: `6-8 vCPU`, `16 GiB` de RAM, `100+ GiB` libres

## Modelo de salida

La herramienta emite:

- `OK` para chequeos que se ven alineados
- `WARN` para problemas suaves o faltantes parciales
- `FAIL` para bloqueantes que vuelven al target no apto

Para automatización, usá salida machine-readable:

```bash
./productive-k3s-core.sh preflight --json-output
```

## Qué no hace

El preflight no es un instalador en dry-run.

No:

- instala paquetes faltantes
- modifica el host
- valida un clúster en ejecución
- reemplaza al validador post-instalación

Usalo antes del bootstrap. Usá [Verificaciones de k3s](k3s-checks.md) y el resto de las páginas de validación después del bootstrap.
