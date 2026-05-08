# Relación Con `productive-k3s-infra`

`productive-k3s-core` es la capa de bootstrap. `productive-k3s-infra` es la capa compañera de infraestructura construida alrededor de ella.

## Qué aporta `productive-k3s-core`

Este repositorio aporta el contrato de bootstrap para:

- instalar `k3s`
- ensamblar un rol o una etapa de topología del clúster
- instalar el stack compartido de plataforma
- validar el entorno resultante

Ese contrato se expone mediante modos explícitos:

- `single-node`
- `server`
- `agent`
- `stack`

## Qué agrega `productive-k3s-infra`

`productive-k3s-infra` usa esos modos para construir flujos más completos de infraestructura alrededor del clúster.

Agrega concerns como:

- provisioning de máquinas cuando hace falta
- derivación de inventarios y metadata de hosts
- orquestación del bootstrap entre múltiples nodos
- secuenciación remota de `server`, `agent` y `stack`
- validación de resultados específicos de infraestructura

## Por qué esto importa para un clúster real

Por sí solo, `productive-k3s-core` ya alcanza para bootstrapear un entorno K3S real.

El repositorio de infraestructura extiende eso hacia caminos más cercanos al ciclo de vida de un clúster real, por ejemplo:

- un clúster local de tres nodos sobre Multipass
- un flujo on-premises por SSH con un servidor y uno o más agentes
- un camino básico single-node sobre AWS

El habilitador clave es la separación por modos:

1. `server` bootstrapea el nodo de control-plane
2. `agent` suma nodos adicionales
3. `stack` instala componentes a nivel clúster sólo después de que el clúster existe

Eso es lo que permite que otro repositorio arme un clúster multinodo real sin reimplementar el bootstrap del clúster en sí.

## Interpretación práctica

Si sólo necesitás un camino de bootstrap directo sobre una sola máquina, `productive-k3s-core` es el proyecto principal.

Si además necesitás:

- provisioning de máquinas
- orquestación remota
- ensamblado multinodo
- workflows de infraestructura específicos por caso de uso

entonces `productive-k3s-infra` es la siguiente capa por encima.

## Ver también

- [Resumen del producto](index.md)
- [Razones del diseño](reasons-behind.md)
- [Cómo usar Productive K3S Core](how-to-use.md)
