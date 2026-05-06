# k3s Checks

## Basic cluster health

```bash
sudo systemctl status k3s
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
```

## Control-plane services

```bash
sudo k3s kubectl get svc -A
sudo k3s kubectl get deploy -A
sudo k3s kubectl get daemonset -A
```

## Storage and ingress overview

```bash
sudo k3s kubectl get sc
sudo k3s kubectl get pvc -A
sudo k3s kubectl get ingress -A
```

## Managed validator

```bash
./scripts/validate-k3s-stack.sh
./scripts/validate-k3s-stack.sh --strict
./scripts/validate-k3s-stack.sh --json | jq
```
