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

## Managed validators

```bash
./scripts/validate.sh
./scripts/validate.sh --strict
./scripts/validate.sh --json | jq
./productive-k3s-core.sh stack validate base --strict
```

Use `validate.sh` when you want to check the local core installation only.

Use `stack validate <name>` when you want to validate an explicit stack such as `base`.
