# Certificate Checks

Use this when validating `cert-manager`, Rancher TLS, and Registry TLS.

## cert-manager health

```bash
sudo k3s kubectl get ns cert-manager
sudo k3s kubectl get pods -n cert-manager -o wide
sudo k3s kubectl get clusterissuer
sudo k3s kubectl get certificates -A
```

## Rancher certificate

```bash
sudo k3s kubectl get certificate -n cattle-system
sudo k3s kubectl describe certificate rancher-tls -n cattle-system
sudo k3s kubectl get secret tls-rancher-ingress -n cattle-system
curl -kI https://rancher.home.arpa
```

## Registry certificate

```bash
sudo k3s kubectl get certificate -n registry
sudo k3s kubectl describe certificate registry-tls -n registry
sudo k3s kubectl get secret registry-tls -n registry
curl -kI https://registry.home.arpa/v2/
```

## Inspect certificate subject from Kubernetes secret

```bash
sudo k3s kubectl get secret registry-tls -n registry -o jsonpath='{.data.tls\.crt}' \
| base64 -d | openssl x509 -noout -subject -issuer -dates
```

## Local Docker trust reference

```bash
ls -R /etc/docker/certs.d/registry.home.arpa
```
