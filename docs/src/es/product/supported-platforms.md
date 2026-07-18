# Plataformas soportadas

Esta página resume los targets soportados por Productive K3S Core y la guía práctica de dimensionamiento para un host de nodo único.

La idea de esta matriz de soporte no es reclamar cualquier entorno con forma de Kubernetes. La idea es mantener confiable y explícito el camino simple de entrada.

La herramienta está preparada para entornos orientados a producción basados en los sistemas operativos no propietarios más utilizados en plataformas comunes de cloud y de VMs. En la práctica, por eso los targets de runtime soportados terminan siendo distribuciones Linux.

Al mismo tiempo, el flujo de desarrollo da una forma práctica para que contribuidores que usan Windows o macOS puedan trabajar en mejoras sobre los scripts de la herramienta usando Multipass y VMs Linux soportadas.

## Targets soportados

El repositorio está validado y soportado sobre:

- Ubuntu `24.04` LTS sobre `amd64`
- Ubuntu `24.04` LTS sobre `arm64`
- Ubuntu `22.04` LTS sobre `amd64`
- Debian `13` `trixie` sobre `amd64`
- Debian `12` `bookworm` sobre `amd64`

El soporte significa que la evidencia de validación retenida incluye estos flujos:

- `smoke`
- `core`
- `full`
- `full-rollback`
- `full-clean`

## Modelo de validación

- Ubuntu `24.04` sobre `amd64` tiene validación directa en runners hosteados y validación basada en VM
- Ubuntu `24.04` sobre `arm64` tiene validación pública retenida a través del camino on-prem ARM
- Ubuntu `22.04`, Debian `12` y Debian `13` se validan mediante el harness de VM
- El soporte para Debian se refiere al runtime dentro de la VM validada, no a CI hosteado directo de GitHub
- La validación pública retenida para ARM hoy es específica de Ubuntu `24.04`

## Supuestos de plataforma

- la instalación de paquetes asume `apt-get`
- la gestión de servicios asume `systemd`
- las pruebas de integración basadas en VM se apoyan en `multipass`
- Windows y macOS sólo son relevantes como hosts capaces de ejecutar VMs Linux

## Hardware mínimo

Mínimo práctico para el stack completo:

- CPU: `4 vCPU`
- RAM: `12 GB`
- Disco: `60 GB` libres en SSD

Recomendado para una experiencia más fluida:

- CPU: `6-8 vCPU`
- RAM: `16 GB`
- Disco: `100 GB+` libres

## Por qué la base no es menor

- `Rancher` y `Longhorn` agregan overhead sostenido al plano de control
- el registry interno consume almacenamiento persistente
- las cargas stateful necesitan margen más allá de la plataforma base
- el bajo espacio libre en disco es especialmente problemático para `Longhorn`

## Ver también

- [Baseline soportado para Ubuntu 22.04](../developer-docs/ubuntu-22-04-supported.md)
- [Baseline soportado para Ubuntu 24.04](../developer-docs/ubuntu-24-04-supported.md)
- [Baseline soportado para Debian 12](../developer-docs/debian-12-supported.md)
- [Baseline soportado para Debian 13](../developer-docs/debian-13-supported.md)
- [Pruebas después de cambios](../developer-docs/guides/post-development-testing.md)
