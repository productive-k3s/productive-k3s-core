# Longhorn Single-Node Notes

This repository is primarily designed around a single-node `k3s` setup. That matters for Longhorn.

## Symptom pattern

A chart requests a PVC and Kubernetes shows it as `Bound`, but the workload stays in `ContainerCreating`.

Longhorn then shows volumes such as:

- `state: detached`
- `robustness: faulted`

Typical pod-level error:

```text
volume is not ready for workloads
```

## Root causes seen in this stack

### Replica count incompatible with a single node

If a Longhorn-backed volume is created with `numberOfReplicas: "3"` on a one-node cluster, scheduling can fail immediately.

### Longhorn disk free-space threshold too strict

If `storage-minimal-available-percentage` is too high for the host's available disk space, Longhorn may refuse scheduling and report `ReplicaSchedulingFailure` or unavailable disks.

## Bootstrap behavior in this repository

For single-node clusters, the bootstrap now aims to avoid this class of failure from the start by:

- defaulting Longhorn replica count to `1`
- creating a `longhorn-single` `StorageClass` with `numberOfReplicas: "1"`
- defaulting the registry PVC to `longhorn-single` when appropriate
- setting Longhorn `storage-minimal-available-percentage` to a more practical single-node value

## Useful commands

```bash
./utils/inspect-longhorn.sh
./utils/inspect-longhorn-volumes.sh
sudo k3s kubectl get sc
sudo k3s kubectl get volumes.longhorn.io -n longhorn-system
sudo k3s kubectl get pvc -A
sudo k3s kubectl describe pvc -n <namespace> <pvc-name>
```

## If a volume is already faulted

Fixing Longhorn settings may not be enough for a PVC that was already provisioned under invalid conditions.

In this repo's intended dev/lab workflow, the practical recovery path is usually:

1. correct the Longhorn defaults and scheduling-related settings
2. recreate the affected PVC
3. let the workload provision a fresh volume

## Validation targets

Expected healthy outcome:

- Longhorn volume `state=attached`
- Longhorn volume `robustness=healthy`
- workload pod `Running`
