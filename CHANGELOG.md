# Changelog

## Unreleased

### Added
- Incremental bootstrap for `k3s`, `helm`, `cert-manager`, `Longhorn`, `Rancher`, internal registry, host NFS export, `/etc/hosts`, and local Docker trust.
- Structured bootstrap run manifests under `runs/` for later inspection and manifest-guided rollback.
- `docs/` operational how-to guides for `k3s`, ingress, Rancher, registry, Longhorn, and certificate checks.
- `docs/` note for Longhorn single-node behavior and PVC troubleshooting.
- `utils/` helper scripts for inspecting ingress, Rancher, Longhorn, Longhorn volumes, and listing registry repositories/tags.
- `scripts/validate.sh` with:
  - strict mode
  - JSON output
  - optional Docker registry push/pull validation
- `scripts/backup.sh` for stack and host configuration export.
- `scripts/rollback.sh` for safe manifest-guided rollback of bootstrap-introduced resources.
- `scripts/cleanup.sh` for destructive full local stack cleanup.
- `tests/test-in-docker.sh` as a smoke-only container harness for bootstrap `--dry-run`.
- `tests/test-in-vm.sh` as the real integration harness using Multipass, with profiles:
  - `smoke`
  - `core`
  - `full`
  - `full-clean`
  - `full-rollback`
- `tests/test-in-vm-cleanup.sh` for cleanup of Multipass-based test VMs.
- Host-side VM test artifacts under `test-artifacts/`, including copied bootstrap manifests when available.

### Changed
- Bootstrap UX was reorganized into:
  - detection
  - diagnosis
  - high-level decisions
  - plan
  - apply or dry-run
- Prompt labels now explicitly indicate whether a choice is:
  - required
  - optional
  - required for TLS-dependent installs
- Longhorn bootstrap no longer formats or mounts disks.
- Longhorn bootstrap is now aligned with the repository's single-node-first target by creating a `longhorn-single` storage class, preferring one replica, and lowering the minimal available storage threshold to a practical dev/lab default.
- Standalone `kubectl` is treated as optional; the managed workflow uses `sudo k3s kubectl`.
- Validator now treats absent optional components as skip conditions instead of implicit failures.
- Validator now focuses on active pods plus Deployment/StatefulSet/DaemonSet readiness, while treating historical terminal pods as informational context instead of hard failures.
- VM-based tests now wait for validation to converge instead of assuming immediate readiness.

### Fixed
- Bootstrap prompt handling was stabilized for interactive terminals and non-TTY smoke tests.
- Bootstrap now waits for `cert-manager-webhook` endpoints and for Rancher/Registry certificates to become `Ready` before continuing.
- Longhorn default `StorageClass` handling was corrected to avoid multiple defaults in new installs.
- Rollback now resolves a usable kubeconfig before running helm-based cleanup.
- Rollback and clean teardown were hardened for:
  - Rancher/Fleet/Turtles namespaces and cluster-scoped artifacts
  - Longhorn webhook, CRD, `StorageClass`, and `CSIDriver` cleanup
- VM test profiles now persist artifacts and copied manifests on the host for later inspection.
