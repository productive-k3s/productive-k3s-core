# Longhorn Checks

## Quick commands

```bash
sudo k3s kubectl get ns longhorn-system
sudo k3s kubectl get pods -n longhorn-system -o wide
sudo k3s kubectl get svc -n longhorn-system
sudo k3s kubectl get sc
sudo k3s kubectl get volumes.longhorn.io -n longhorn-system
sudo k3s kubectl get settings.longhorn.io -n longhorn-system
```

## Helper utility

```bash
./utils/inspect-longhorn.sh
./utils/inspect-longhorn-volumes.sh
```

## Useful related objects

```bash
sudo k3s kubectl get csidrivers
sudo k3s kubectl get volumeattachments
sudo k3s kubectl get pvc -A
```

## What to confirm

- Longhorn pods are `Running`
- exactly one default `StorageClass` is configured for your intended setup
- PVCs bound to Longhorn have attached, healthy backing volumes

## Single-node note

If this cluster is running on a single node, also read:

- [Longhorn single-node notes](longhorn-single-node-notes.md)
