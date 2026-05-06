# Verificaciones de Rancher

## Comandos rápidos

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

## Utilidad auxiliar

```bash
./utils/inspect-rancher.sh
```

## Verificación de rollout

```bash
sudo k3s kubectl rollout status deploy/rancher -n cattle-system --timeout=60s
```

## Referencia de bootstrap password

```bash
sudo k3s kubectl get secret -n cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
```
