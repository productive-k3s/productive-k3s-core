# Modos De Productive K3S Core

`apply.sh` expone modos explícitos de ejecución mediante `--mode`.

## Modos soportados

| Modo | Propósito |
| --- | --- |
| `single-node` | Modo default. Hace bootstrap de una instalación de nodo único y puede instalar el stack local |
| `server` | Hace bootstrap sólo de los componentes base del nodo servidor |
| `agent` | Suma un nodo como agente de K3S |
| `stack` | Instala o reutiliza componentes del stack sobre un clúster existente |

## Significado operativo

Internamente el script trata a los modos como switches de capacidades:

- `single-node`: ejecuta instalación base, instalación del stack y tareas locales del host
- `server`: ejecuta sólo la instalación base
- `agent`: configura un nodo agente y requiere URL del servidor más token del clúster
- `stack`: requiere un clúster existente y Helm, y luego opera sólo sobre componentes del stack

## Qué cambia según el modo

### `single-node`

- puede instalar `k3s` y Helm
- puede instalar componentes del stack como `cert-manager`, `Longhorn`, `Rancher` y el registry in-cluster
- puede administrar `/etc/hosts` local
- puede administrar NFS local del host
- puede instalar trust local de Docker para el registry self-signed

### `server`

- puede instalar o reutilizar `k3s` y Helm
- omite componentes sólo de stack
- omite integraciones locales del stack como NFS y Docker registry trust

### `agent`

- apunta a `k3s-agent` en lugar del servicio servidor
- pide `Agent server URL` y `Agent cluster token` cuando hace falta instalar el agente
- omite Helm y componentes del stack

### `stack`

- requiere un `k3s` server ya en funcionamiento y `helm` instalado
- no instala la base de `k3s`
- se enfoca en componentes del stack y cluster issuers

## Por qué importa la separación por modos

El modelo de modos es lo que hace posible la orquestación desde `productive-k3s-infra`. Le da a la automatización de infraestructura una interfaz estable para:

- provisioning base de nodos
- joins de agentes
- instalación del stack del clúster una vez que el clúster ya existe

## Notas

!!! note
    `single-node` sigue siendo el camino más simple de tipo all-in-one para uso local directo.

!!! note
    `server`, `agent` y `stack` son especialmente valiosos cuando otra capa orquesta la secuencia del bootstrap.
