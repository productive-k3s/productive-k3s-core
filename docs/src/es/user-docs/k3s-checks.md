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

## Validadores administrados

```bash
./scripts/validate.sh
./scripts/validate.sh --strict
./scripts/validate.sh --json | jq
./productive-k3s-core.sh stack validate base --strict
```

Usá `validate.sh` cuando quieras chequear sólo la instalación local del core.

Usá `stack validate <name>` cuando quieras validar un stack explícito como `base`.
