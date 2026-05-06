# Verificaciones del Registry

## Objetos de Kubernetes

```bash
sudo k3s kubectl get ns registry
sudo k3s kubectl get pods -n registry -o wide
sudo k3s kubectl get svc -n registry
sudo k3s kubectl get ingress -n registry
sudo k3s kubectl get pvc -n registry
```

## Checks HTTP

```bash
curl -kI https://registry.home.arpa/v2/
curl -k https://registry.home.arpa/v2/_catalog | jq
```

Respuesta esperada para `/v2/`:

- `200 OK`, o
- `401 Unauthorized`

Ambas significan que el endpoint del registry está respondiendo.

## Listar repositorios y tags

```bash
./utils/list-registry-images.sh
./utils/list-registry-images.sh --json | jq
```

## Prueba funcional de push/pull

```bash
docker pull busybox:1.36
docker tag busybox:1.36 registry.home.arpa/test/busybox:1.36
docker push registry.home.arpa/test/busybox:1.36
docker pull registry.home.arpa/test/busybox:1.36
```

## Probe del servicio in-cluster

```bash
sudo k3s kubectl run curltest --rm -it --restart=Never --image=curlimages/curl -- \
  curl -I http://registry.registry.svc.cluster.local:5000/v2/
```
