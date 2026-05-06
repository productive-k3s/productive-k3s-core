# Verificaciones de ingress

Usá esto cuando necesites confirmar cómo se exponen las aplicaciones a través de Traefik.

## Comandos rápidos

```bash
sudo k3s kubectl get svc -n kube-system traefik
sudo k3s kubectl describe svc -n kube-system traefik
sudo k3s kubectl get ingressclass
sudo k3s kubectl get ingress -A
sudo k3s kubectl describe ingress -A
```

## Utilidad auxiliar

```bash
./utils/inspect-ingress.sh
```

El helper imprime:

- exposición del servicio Traefik
- definiciones de ingress class
- todos los recursos ingress
- vista detallada por ingress con:
  - ingress class
  - dirección anunciada
  - hosts
  - hosts TLS y `secretName`
  - mapeos de servicios backend
  - annotations

## Qué confirmar

- el servicio `traefik` expone `80` y `443`
- los recursos ingress tienen los hostnames esperados
- TLS está presente para los hosts que deben terminar en HTTPS
- `spec.tls[].secretName` coincide con el secret de certificado esperado
- los servicios backend y sus puertos coinciden con el entrypoint previsto de la aplicación
- el DNS local o `/etc/hosts` apunta los hostnames al IP del nodo

## Probes básicos

```bash
curl -I http://<host>
curl -kI https://<host>
```

## Ejemplo de interpretación

- Si un ingress muestra sólo `PORTS 80` y `tls: <none>`, está expuesto sólo por HTTP.
- Si un ingress muestra `PORTS 80, 443` y un secret TLS, la terminación HTTPS está configurada en Traefik.
- Si el host es correcto pero el servicio backend o el puerto son incorrectos, el ingress existirá pero ruteará al target equivocado.
