# Plataformas soportadas

Esta página resume los targets soportados por Productive K3S y la guía práctica de dimensionamiento para un host de nodo único.

## Targets Linux soportados

El repositorio está validado y soportado sobre:

- Ubuntu `24.04` LTS
- Ubuntu `22.04` LTS
- Debian `13` `trixie`
- Debian `12` `bookworm`

El soporte significa que la evidencia de validación retenida incluye estos flujos:

- `smoke`
- `core`
- `full`
- `full-rollback`
- `full-clean`

## Modelo de validación

- Ubuntu `24.04` tiene validación directa en runners hosteados y validación basada en VM
- Ubuntu `22.04`, Debian `12` y Debian `13` se validan mediante el harness de VM
- El soporte para Debian se refiere al runtime dentro de la VM validada, no a CI hosteado directo de GitHub

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

- [Baseline soportado para Debian 12](../contributor/debian-12-supported.md)
- [Baseline soportado para Debian 13](../contributor/debian-13-supported.md)
- [Pruebas después de cambios](../guides/post-development-testing.md)
