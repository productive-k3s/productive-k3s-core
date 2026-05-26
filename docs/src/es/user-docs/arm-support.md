# ARM Support

Esta página documenta la baseline pública actual de soporte ARM para `productive-k3s-core`.

## Camino público soportado para ARM

La validación pública retenida para ARM incluye actualmente:

- Ubuntu `24.04` Desktop sobre `arm64`
- Raspberry Pi 5 Model B Rev `1.1`
- `4` CPU cores
- alrededor de `7.7 GiB` de RAM

Esa validación retenida completó con éxito:

- host preflight
- bootstrap `server`
- bootstrap `stack`
- validación de `cert-manager`, `Longhorn`, `Rancher` y el registry in-cluster

## Interpretación práctica

ARM ahora forma parte de la matriz pública soportada para Ubuntu `24.04`.

Eso no significa que cualquier placa ARM chica tenga margen amplio para el stack completo. La validación retenida sobre Raspberry Pi prueba viabilidad, pero sigue estando por debajo de la guía publicada de RAM para full stack.

## Ver también

- [Plataformas soportadas](../product/supported-platforms.md)
- [Preflight del host](host-preflight.md)
