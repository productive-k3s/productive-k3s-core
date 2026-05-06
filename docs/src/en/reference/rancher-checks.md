# Rancher Checks

## Quick commands

```bash
sudo k3s kubectl get ns cattle-system
sudo k3s kubectl get pods -n cattle-system -o wide
sudo k3s kubectl get deploy -n cattle-system
sudo k3s kubectl get svc -n cattle-system
sudo k3s kubectl get ingress -n cattle-system
sudo k3s kubectl get certificate -n cattle-system
sudo k3s kubectl get secret -n cattle-system | grep -E 'tls|bootstrap|ca'
curl -kI https://rancher.home.arpa
```

## Helper utility

```bash
./utils/inspect-rancher.sh
```

## Rollout check

```bash
sudo k3s kubectl rollout status deploy/rancher -n cattle-system --timeout=60s
```

## Bootstrap password reference

```bash
sudo k3s kubectl get secret -n cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
```
