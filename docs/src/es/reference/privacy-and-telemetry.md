# Privacidad y telemetría

`productive-k3s` escribe un manifiesto estructurado de ejecución por cada bootstrap.

Objetivos:

- mantener útil el troubleshooting local y la evidencia de pruebas
- evitar registrar datos personales o específicos del entorno en el manifiesto público
- dejar espacio para telemetría opt-in futura sin cambiar más adelante el contrato de privacidad

## Manifiesto público de ejecución

Los bootstrap escriben un manifiesto público bajo `runs/bootstrap-<run_id>.json`.

Ese manifiesto está limitado intencionalmente a datos operativos anónimos como:

- modo de bootstrap
- plataforma soportada y familia/versión de OS
- plan y resultado de componentes
- feature flags no sensibles
- timestamps, exit code y paso actual

El manifiesto público **no** registra:

- hostnames
- usernames
- current working directory
- server URLs
- ingress hostnames
- local filesystem paths
- redes cliente de NFS

## Contexto privado de rollback

Algunas operaciones de rollback todavía necesitan detalles locales como hostnames, export paths o targets de confianza de Docker.

Por eso el bootstrap también escribe un archivo local-only asociado:

- `runs/bootstrap-<run_id>-private.json`

Ese archivo se usa sólo para soportar el planning y la aplicación del rollback sobre la misma máquina.

No forma parte del contrato del manifiesto público y no debe tratarse como telemetría compartible.

## Dirección de la telemetría

Si se agrega telemetría más adelante, debería seguir siendo:

- opt-in explícito
- anónima
- event-driven
- basada en el mismo contrato del manifiesto público documentado acá

Ejemplos de categorías de evento seguras:

- install
- mode usage
- component enabled
- operation attempt

La interpretación de esos eventos pertenece al lado receptor, no al cliente local del bootstrap.

## Controles de entrega

La entrega de telemetría sigue siendo explícitamente opt-in.

Reglas de decisión:

- si `TELEMETRY_ENABLED=true`, la telemetría queda habilitada sin prompt
- si `TELEMETRY_ENABLED=false`, la telemetría queda deshabilitada sin prompt
- si `TELEMETRY_ENABLED` no está seteada y el bootstrap corre de forma interactiva, el bootstrap pregunta una sola vez si querés habilitar telemetría anónima para esa corrida, con `Yes` como default
- si `TELEMETRY_ENABLED` no está seteada y el bootstrap no corre de forma interactiva, la telemetría queda deshabilitada

Variables de entorno:

- `TELEMETRY_ENABLED`: setear en `true` para habilitar entrega best-effort del manifiesto público de bootstrap
- `TELEMETRY_ENDPOINT`: URL de destino para la entrega de telemetría
- `TELEMETRY_MAX_RETRIES`: máximo total de intentos de entrega, incluyendo el primero. Default: `3`
- `TELEMETRY_CONNECT_TIMEOUT_SECONDS`: timeout de conexión por intento. Default: `5`
- `TELEMETRY_REQUEST_TIMEOUT_SECONDS`: timeout total del request por intento. Default: `10`
- `TELEMETRY_OUTBOX_DIR`: directorio local usado para retener payloads de entregas fallidas. Default: `runs/telemetry-outbox`
- `TELEMETRY_USER_AGENT`: user agent HTTP usado para los requests de entrega

Reglas de entrega:

- la telemetría es sólo best-effort
- la telemetría nunca debe bloquear ni fallar la instalación del bootstrap
- los intentos fallidos se retienen localmente en el directorio outbox de telemetría
- los reintentos se marcan dentro del payload para que el receptor distinga entre la entrega original y un retry
