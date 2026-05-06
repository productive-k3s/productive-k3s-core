# Registry Checks

## Kubernetes objects

```bash
sudo k3s kubectl get ns registry
sudo k3s kubectl get pods -n registry -o wide
sudo k3s kubectl get svc -n registry
sudo k3s kubectl get ingress -n registry
sudo k3s kubectl get pvc -n registry
```

## HTTP checks

```bash
curl -kI https://registry.home.arpa/v2/
curl -k https://registry.home.arpa/v2/_catalog | jq
```

Expected response for `/v2/`:

- `200 OK`, or
- `401 Unauthorized`

Both mean the registry endpoint is responding.

## List repositories and tags

```bash
./utils/list-registry-images.sh
./utils/list-registry-images.sh --json | jq
```

## Functional push/pull test

```bash
docker pull busybox:1.36
docker tag busybox:1.36 registry.home.arpa/test/busybox:1.36
docker push registry.home.arpa/test/busybox:1.36
docker pull registry.home.arpa/test/busybox:1.36
```

## In-cluster service probe

```bash
sudo k3s kubectl run curltest --rm -it --restart=Never --image=curlimages/curl -- \
  curl -I http://registry.registry.svc.cluster.local:5000/v2/
```
