# Razones del diseño de `productive-k3s-core`

La configuración de `productive-k3s-core` fue diseñada para ofrecer un entorno local de Kubernetes liviano pero orientado a producción sobre un único host. La idea es ir más allá de despliegues locales ad hoc y ofrecer un stack más cercano a operaciones reales de Kubernetes, pero que siga siendo lo bastante simple como para ejecutarlo y validarlo localmente.

## k3s

Se eligió `k3s` como distribución de Kubernetes porque ofrece un clúster completamente funcional con una huella operativa mucho menor que una instalación upstream estándar. Encaja muy bien en entornos de nodo único y clusters pequeños, por lo que resulta una opción fuerte para infraestructura local que igual necesita comportarse como un cluster real.

Esto nos da:

- un control plane real de Kubernetes
- compatibilidad con charts de Helm y recursos estándar de Kubernetes
- un camino más simple desde entornos locales hacia despliegues más cercanos a producción

Referencias:

- [k3s](https://k3s.io/)
- [documentación de k3s](https://docs.k3s.io/)

## cert-manager

Se incluyó `cert-manager` para manejar el ciclo de vida de certificados dentro del cluster. Incluso en entornos locales o semi-locales, TLS pasa a ser necesario apenas los servicios se exponen por ingress o son consumidos por varios componentes.

Esto nos da:

- emisión y renovación automática de certificados
- una configuración TLS más limpia y reproducible
- una base para exponer servicios de forma segura sin manejo manual de certificados

Referencias:

- [cert-manager](https://cert-manager.io/)
- [documentación de cert-manager](https://cert-manager.io/docs/)

## Longhorn

Se eligió `Longhorn` como capa de almacenamiento persistente cloud-native para cargas stateful en Kubernetes. En vez de depender de mounts de disco locales ad hoc para todo, Longhorn permite administrar volúmenes persistentes de una manera consistente con los patrones de Kubernetes.

Esto nos da:

- volúmenes persistentes para bases de datos y otros servicios stateful
- una capa de almacenamiento gestionada nativamente desde Kubernetes
- mejor visibilidad operativa para cargas stateful
- un modelo de almacenamiento más realista que montar directamente el host para cada componente persistente

Referencias:

- [Longhorn](https://longhorn.io/)
- [documentación de Longhorn](https://longhorn.io/docs/)

## Rancher

Se agregó `Rancher` para ofrecer una interfaz de gestión y operaciones del cluster. Aunque todo puede hacerse con `kubectl`, contar con un dashboard simplifica la administración local, el troubleshooting y la validación.

Esto nos da:

- visibilidad sobre workloads, servicios, almacenamiento y logs
- operaciones cotidianas del cluster más simples
- una experiencia más amigable para usuarios que no quieran depender sólo de la CLI

Referencias:

- [Rancher](https://www.rancher.com/)
- [documentación de Rancher](https://ranchermanager.docs.rancher.com/)

## Registry interno

El registry interno se incluyó para soportar un flujo autocontenido de distribución de imágenes. En entornos locales o parcialmente desconectados, depender de registries externos para cada build y despliegue agrega fricción y dependencia externa.

Esto nos da:

- push y pull de imágenes local sin depender de registries externos en cada iteración
- ciclos de desarrollo y despliegue más rápidos
- mejor control sobre las versiones de imágenes usadas en el cluster
- un camino más fluido para CI/CD y pruebas locales iterativas

Referencia:

- [Distribution registry](https://distribution.github.io/distribution/)

## Export NFS del host

El export NFS del host se agregó para cubrir el caso de compartir archivos administrados en el host con workloads que corren dentro del cluster. Esto es útil cuando algunos datos deben seguir siendo fáciles de inspeccionar, editar o poblar directamente desde la máquina host, mientras siguen siendo consumidos por aplicaciones dentro de Kubernetes.

Esto nos da:

- una forma simple de exponer archivos del host dentro del cluster
- un mecanismo práctico para datasets, recursos estáticos o archivos administrados por aplicaciones
- una separación clara entre almacenamiento persistente nativo de Kubernetes y datos compartidos administrados por el host

Referencias:

- [NFS en Ubuntu Server](https://documentation.ubuntu.com/server/how-to/networking/install-nfs/)
- [Volúmenes NFS en Kubernetes](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)

## Racional general del diseño

Tomado como conjunto, este stack busca equilibrar simplicidad, reproducibilidad y realismo operativo.

Apunta a ofrecer:

- un entorno local que se comporte mucho más como una plataforma real de Kubernetes
- soporte tanto para cargas stateless como stateful
- mejor observabilidad y capacidad de operación que una configuración local mínima
- una base práctica para desplegar aplicaciones con Helm y validarlas contra un cluster local realista

En resumen, la idea es que sea lo bastante pequeño como para correr localmente, pero lo bastante estructurado como para reflejar patrones reales de despliegue.

## Ver también

- [Resumen del producto](index.md)
- [Notas de Longhorn para nodo único](../user-docs/longhorn-single-node-notes.md)
- [Verificaciones de certificados](../user-docs/certificate-checks.md)
