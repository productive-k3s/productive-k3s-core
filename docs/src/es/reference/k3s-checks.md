# Verificaciones de k3s

## Salud básica del cluster

```bash
sudo systemctl status k3s
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
```

## Servicios del control plane

```bash
sudo k3s kubectl get svc -A
sudo k3s kubectl get deploy -A
sudo k3s kubectl get daemonset -A
```

## Panorama de storage e ingress

```bash
sudo k3s kubectl get sc
sudo k3s kubectl get pvc -A
sudo k3s kubectl get ingress -A
```

## Validador administrado

```bash
./scripts/validate-k3s-stack.sh
./scripts/validate-k3s-stack.sh --strict
./scripts/validate-k3s-stack.sh --json | jq
```
