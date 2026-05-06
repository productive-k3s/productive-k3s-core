# Notas de Longhorn para nodo único

Este repositorio está diseñado principalmente alrededor de una instalación `k3s` de nodo único. Eso importa para Longhorn.

## Patrón del síntoma

Un chart pide un PVC y Kubernetes lo muestra como `Bound`, pero el workload queda en `ContainerCreating`.

Luego Longhorn muestra volúmenes como:

- `state: detached`
- `robustness: faulted`

Error típico a nivel pod:

```text
volume is not ready for workloads
```

## Causas raíz vistas en este stack

### Cantidad de réplicas incompatible con un nodo único

Si un volumen respaldado por Longhorn se crea con `numberOfReplicas: "3"` en un cluster de un solo nodo, el scheduling puede fallar de inmediato.

### Umbral de espacio libre en disco demasiado estricto

Si `storage-minimal-available-percentage` es demasiado alto para el espacio libre real del host, Longhorn puede rechazar el scheduling y reportar `ReplicaSchedulingFailure` o discos no disponibles.

## Comportamiento del bootstrap en este repositorio

Para clusters de nodo único, el bootstrap ahora intenta evitar esta clase de fallos desde el principio:

- deja el replica count de Longhorn en `1`
- crea un `StorageClass` `longhorn-single` con `numberOfReplicas: "1"`
- usa `longhorn-single` como default para el PVC del registry cuando corresponde
- ajusta `storage-minimal-available-percentage` a un valor más práctico para nodo único

## Comandos útiles

```bash
./utils/inspect-longhorn.sh
./utils/inspect-longhorn-volumes.sh
sudo k3s kubectl get sc
sudo k3s kubectl get volumes.longhorn.io -n longhorn-system
sudo k3s kubectl get pvc -A
sudo k3s kubectl describe pvc -n <namespace> <pvc-name>
```

## Si un volumen ya quedó faulted

Corregir settings de Longhorn puede no ser suficiente para un PVC que ya fue provisionado bajo condiciones inválidas.

En el flujo dev/lab buscado por este repositorio, el camino práctico de recuperación suele ser:

1. corregir defaults de Longhorn y settings relacionados con scheduling
2. recrear el PVC afectado
3. dejar que el workload aprovisione un volumen nuevo

## Objetivos de validación

Resultado saludable esperado:

- volumen de Longhorn `state=attached`
- volumen de Longhorn `robustness=healthy`
- pod del workload en `Running`
