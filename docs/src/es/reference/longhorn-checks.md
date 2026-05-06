# Verificaciones de Longhorn

## Comandos rápidos

```bash
sudo k3s kubectl get ns longhorn-system
sudo k3s kubectl get pods -n longhorn-system -o wide
sudo k3s kubectl get svc -n longhorn-system
sudo k3s kubectl get sc
sudo k3s kubectl get volumes.longhorn.io -n longhorn-system
sudo k3s kubectl get settings.longhorn.io -n longhorn-system
```

## Utilidad auxiliar

```bash
./utils/inspect-longhorn.sh
./utils/inspect-longhorn-volumes.sh
```

## Objetos relacionados útiles

```bash
sudo k3s kubectl get csidrivers
sudo k3s kubectl get volumeattachments
sudo k3s kubectl get pvc -A
```

## Qué confirmar

- los pods de Longhorn están en `Running`
- hay exactamente un `StorageClass` default configurado para la topología buscada
- los PVCs ligados a Longhorn tienen volúmenes adjuntos y saludables

## Nota para nodo único

Si este cluster corre sobre un solo nodo, leé también:

- [Notas de Longhorn para nodo único](longhorn-single-node-notes.md)
