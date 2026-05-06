# Verificaciones de certificados

Usá esto cuando necesites validar `cert-manager`, TLS de Rancher y TLS del Registry.

## Estado de `cert-manager`

```bash
sudo k3s kubectl get ns cert-manager
sudo k3s kubectl get pods -n cert-manager -o wide
sudo k3s kubectl get clusterissuer
sudo k3s kubectl get certificates -A
```

## Certificado de Rancher

```bash
sudo k3s kubectl get certificate -n cattle-system
sudo k3s kubectl describe certificate rancher-tls -n cattle-system
sudo k3s kubectl get secret tls-rancher-ingress -n cattle-system
curl -kI https://rancher.home.arpa
```

## Certificado del Registry

```bash
sudo k3s kubectl get certificate -n registry
sudo k3s kubectl describe certificate registry-tls -n registry
sudo k3s kubectl get secret registry-tls -n registry
curl -kI https://registry.home.arpa/v2/
```

## Inspeccionar subject del certificado desde el secret de Kubernetes

```bash
sudo k3s kubectl get secret registry-tls -n registry -o jsonpath='{.data.tls\.crt}' \
| base64 -d | openssl x509 -noout -subject -issuer -dates
```

## Referencia de confianza local de Docker

```bash
ls -R /etc/docker/certs.d/registry.home.arpa
```
