# Ingress Checks

Use this when you need to confirm how applications are exposed through Traefik.

## Quick commands

```bash
sudo k3s kubectl get svc -n kube-system traefik
sudo k3s kubectl describe svc -n kube-system traefik
sudo k3s kubectl get ingressclass
sudo k3s kubectl get ingress -A
sudo k3s kubectl describe ingress -A
```

## Helper utility

```bash
./utils/inspect-ingress.sh
```

The helper prints:

- Traefik service exposure
- ingress class definitions
- all ingress resources
- detailed per-ingress view with:
  - ingress class
  - advertised address
  - hosts
  - TLS hosts and `secretName`
  - backend service mappings
  - annotations

## What to confirm

- `traefik` service exposes `80` and `443`
- ingress resources have the expected hostnames
- TLS is present for hosts that should terminate HTTPS
- `spec.tls[].secretName` matches the expected certificate secret
- backend services and ports match the intended application entrypoint
- local DNS or `/etc/hosts` points hostnames to the node IP

## Basic probes

```bash
curl -I http://<host>
curl -kI https://<host>
```

## Example interpretation

- If an ingress shows only `PORTS 80` and `tls: <none>`, it is exposed only over HTTP.
- If an ingress shows `PORTS 80, 443` and a TLS secret, HTTPS termination is configured at Traefik.
- If the host is correct but the backend service or port is wrong, the ingress will exist but route to the wrong application target.
