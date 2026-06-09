# Modos De Productive K3S Core

`apply.sh` expone modos explícitos de ejecución mediante `--mode`.

## Modos soportados

| Modo | Propósito |
| --- | --- |
| `single-node` | Modo combinado legado. Instala el core más el stack default en una sola pasada |
| `server` | Modo default. Hace bootstrap sólo de los componentes core del nodo servidor |
| `agent` | Suma un nodo como agente de K3S |
| `stack` | Instala o reutiliza un stack explícito sobre un clúster existente |

## Significado operativo

Internamente el script trata a los modos como switches de capacidades:

- `single-node`: ejecuta instalación base, instalación del stack y tareas locales del host
- `server`: ejecuta sólo la instalación base
- `agent`: configura un nodo agente y requiere URL del servidor más token del clúster
- `stack`: requiere un clúster existente y Helm, y luego opera sólo sobre los componentes del stack seleccionado

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
- omite integraciones locales del stack como `/etc/hosts` administrado por add-ons, Docker registry trust y NFS

### `agent`

- apunta a `k3s-agent` en lugar del servicio servidor
- pide `Agent server URL` y `Agent cluster token` cuando hace falta instalar el agente
- omite Helm y componentes del stack

### `stack`

- requiere un `k3s` server ya en funcionamiento y `helm` instalado
- no instala la base de `k3s`
- se enfoca en componentes del stack y cluster issuers
- es el camino público esperado para `./productive-k3s-core.sh stack install <name>`

## Por qué importa la separación por modos

El modelo de modos es lo que hace posible la orquestación desde `productive-k3s-infra`. Le da a la automatización de infraestructura una interfaz estable para:

- provisioning base de nodos
- joins de agentes
- instalación del stack del clúster una vez que el clúster ya existe

## Notas

!!! note
    `single-node` se conserva como camino all-in-one legado. El contrato público ahora prefiere `apply` para la instalación core-only y `stack install <name>` para instalar un stack de forma explícita.

!!! note
    `server`, `agent` y `stack` son especialmente valiosos cuando otra capa orquesta la secuencia del bootstrap.
