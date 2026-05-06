# Reasons Behind the `productive-k3s` Setup

The `productive-k3s` setup was designed to provide a lightweight but production-oriented local Kubernetes environment on a single host. The goal is to move beyond ad hoc local deployments and offer a stack that is closer to real Kubernetes operations, while still being simple enough to run and validate locally.

## k3s

`k3s` was chosen as the Kubernetes distribution because it provides a fully functional Kubernetes cluster with a much smaller operational footprint than a standard upstream installation. It is well suited for single-node and small-cluster environments, which makes it a strong fit for local infrastructure that still needs to behave like a real cluster.

This gives us:

- a real Kubernetes control plane
- compatibility with Helm charts and standard Kubernetes resources
- a simpler path from local environments to more production-like deployments

References:

- [k3s](https://k3s.io/)
- [k3s documentation](https://docs.k3s.io/)

## cert-manager

`cert-manager` was included to handle certificate lifecycle management inside the cluster. Even in local or semi-local environments, TLS becomes necessary as soon as services are exposed through ingress or consumed by multiple components.

This gives us:

- automated certificate issuance and renewal
- a cleaner and more reproducible TLS setup
- a foundation for exposing services securely without manual certificate handling

References:

- [cert-manager](https://cert-manager.io/)
- [cert-manager documentation](https://cert-manager.io/docs/)

## Longhorn

`Longhorn` was selected as the cloud-native persistent storage layer for stateful workloads running in Kubernetes. Rather than depending on ad hoc local disk mounts for everything, Longhorn allows persistent volumes to be managed in a way that is consistent with Kubernetes patterns.

This gives us:

- persistent volumes for databases and other stateful services
- a storage layer managed natively through Kubernetes
- better operational visibility for stateful workloads
- a more realistic storage model than direct host mounts for every persistent component

References:

- [Longhorn](https://longhorn.io/)
- [Longhorn documentation](https://longhorn.io/docs/)

## Rancher

`Rancher` was added to provide a management and operations UI for the cluster. While everything can be done with `kubectl`, having a dashboard makes local administration, troubleshooting, and validation easier.

This gives us:

- visibility into workloads, services, storage, and logs
- easier day-to-day cluster operations
- a friendlier experience for users who do not want to rely only on the CLI

References:

- [Rancher](https://www.rancher.com/)
- [Rancher documentation](https://ranchermanager.docs.rancher.com/)

## Internal Registry

The internal registry was included to support a self-contained image distribution workflow. In local or partially disconnected environments, relying on external registries for every build and deployment adds friction and external dependency.

This gives us:

- local image push/pull without depending on external registries for every iteration
- faster development and deployment cycles
- better control over image versions used in the cluster
- a smoother path for CI/CD and iterative local testing

Reference:

- [Distribution registry](https://distribution.github.io/distribution/)

## Host NFS Export

The host NFS export was added to cover the use case of sharing host-managed files with workloads running inside the cluster. This is useful when some data must remain easy to inspect, edit, or populate directly from the host machine, while still being consumed by applications inside Kubernetes.

This gives us:

- a simple way to expose host files into the cluster
- a practical mechanism for datasets, static resources, or application-managed files
- a clear separation between Kubernetes-native persistent storage and host-managed shared data

References:

- [NFS on Ubuntu Server](https://documentation.ubuntu.com/server/how-to/networking/install-nfs/)
- [Kubernetes NFS volumes](https://kubernetes.io/docs/concepts/storage/volumes/#nfs)

## Overall Design Rationale

Taken together, this stack aims to balance simplicity, reproducibility, and operational realism.

It is intended to provide:

- a local environment that behaves much more like a real Kubernetes platform
- support for both stateless and stateful workloads
- better observability and manageability than a minimal local setup
- a practical foundation for deploying Helm-based applications and validating them against a realistic local cluster

In short, the setup is meant to be small enough to run locally, but structured enough to reflect real deployment patterns.

## See Also

- [Product overview](index.md)
- [Longhorn single-node notes](../reference/longhorn-single-node-notes.md)
- [Certificate checks](../reference/certificate-checks.md)
