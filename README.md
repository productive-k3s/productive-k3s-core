# Productive-k3s

A simple way to run Kubernetes on a single VM, without the overhead of a full cluster.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-yellow.svg)](./LICENSE)
![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Ubuntu 22.04](https://img.shields.io/badge/Ubuntu-22.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Debian 13](https://img.shields.io/badge/Debian-13%20trixie-A81D33?logo=debian&logoColor=white)
![Debian 12](https://img.shields.io/badge/Debian-12%20bookworm-A81D33?logo=debian&logoColor=white)

Bootstrap and validation for a local `k3s` stack with:

- `cert-manager`
- `Longhorn`
- `Rancher`
- internal registry
- host NFS export

Bootstrap modes:

- `single-node` (default): installs the base node and can install the local stack on the same machine
- `server`: installs only the base server bootstrap components
- `agent`: joins a node to an existing K3S server using a server URL and cluster token
- `stack`: installs or reuses stack components on top of an existing cluster

## Reasons Behind

`productive-k3s` is meant to provide a lightweight but production-oriented Kubernetes environment on a single host.

The intent is to avoid ad hoc local setups and replace them with a stack that is:

- reproducible
- closer to real Kubernetes operations
- simple enough to bootstrap, inspect, validate, back up, and tear down locally

Core rationale:

- `k3s`: lightweight Kubernetes distribution with low operational overhead and good compatibility with normal Kubernetes workflows
- `cert-manager`: in-cluster TLS lifecycle management so ingress-exposed services do not depend on manual certificate handling
- `Longhorn`: Kubernetes-native persistent storage for stateful workloads
- `Rancher`: management UI for cluster inspection and operations
- internal registry: local image push/pull workflow without depending on an external registry for every iteration
- host NFS export: simple host-to-cluster shared file path for datasets and other host-managed files

Detailed rationale:

- [Why this stack exists](./docs/src/en/overview/reasons-behind.md)
- [Post-development testing guide](./docs/src/en/guides/post-development-testing.md)
- [GitHub Actions and release automation](./docs/src/en/contributor/github-actions.md)
- [Privacy and telemetry contract](./docs/src/en/reference/privacy-and-telemetry.md)

## Supported Platforms

The repository is now validated and supported on these Linux runtime targets:

- Ubuntu `24.04` LTS
- Ubuntu `22.04` LTS
- Debian `13` `trixie`
- Debian `12` `bookworm`

Support means these flows have successful retained validation evidence:

- `smoke`
- `core`
- `full`
- `full-rollback`
- `full-clean`

Test runner note:

- `full` and `full-rollback` can spend extra time in strict validation while Rancher and Fleet finish reconciling secondary workloads; seeing a few retry loops before the profile turns green is expected.
- `full-rollback` can also hit a `longhorn-uninstall` job failure such as `BackoffLimitExceeded` during rollback. The harness continues with forced cleanup and then verifies that the Longhorn, Rancher, Registry, cert-manager, NFS export, and bootstrap-managed host entries were actually removed.

Platform notes:

- package installation assumes `apt-get`
- service management assumes `systemd`
- VM-based integration testing is centered on `multipass`
- Windows and macOS are not native bootstrap targets; they are only relevant as host environments capable of running Linux VMs

Validation evidence model:

- Ubuntu `24.04` has both direct hosted validation and VM-based validation coverage
- Ubuntu `22.04`, Debian `12`, and Debian `13` are validated through the VM harness
- Debian support in this repository refers to the Linux runtime inside the validated VM guest, not to GitHub-hosted direct-run CI

Platform-specific validation notes:

- [Debian 13 supported platform](./docs/src/en/contributor/debian-13-supported.md)
- [Debian 12 supported platform](./docs/src/en/contributor/debian-12-supported.md)

## Minimum Hardware

This repository is designed first for a single-node host.

Practical minimum for the full stack:

- CPU: `4 vCPU`
- RAM: `12 GB`
- Disk: `60 GB` free SSD space

Recommended for a smoother experience:

- CPU: `6-8 vCPU`
- RAM: `16 GB`
- Disk: `100 GB+` free SSD space

Why these numbers are not lower:

- `Rancher` and `Longhorn` both add steady control-plane and management overhead
- the internal registry consumes persistent storage
- stateful workloads need headroom beyond the base platform itself
- low free disk space is especially problematic for `Longhorn`

Single-node note:

- this setup is intentionally biased toward single-node operation
- the bootstrap applies safer defaults for that mode, including `longhorn-single`, replica count `1`, and a reduced Longhorn minimal-available-space threshold

## Software Requirements

Software requirements depend on what you want to do with the repository.

### Base Requirements

Required for normal repository usage on a supported target host:

- Linux host with `systemd`
- `bash`
- `sudo`
- `curl`
- `getent`
- `make` if you want to use the provided `Makefile` targets

Expected platform assumptions:

- Ubuntu or Debian on a real host or VM
- `apt-get` is used by the bootstrap to install missing OS packages when needed
- the scripts are intended to run on Linux, not on macOS or Windows directly

### Bootstrap And Validation

Required to bootstrap and validate the stack locally:

- `sudo`
- `curl`
- `systemctl`
- `getent`

Installed or reused by the managed workflow:

- `k3s`
- `helm`

Optional but commonly useful:

- standalone `kubectl`
- `docker` for registry push/pull validation with `--docker-registry-test`

### Rollback And Backup

Additional tools used by specific scripts:

- `jq` for `scripts/rollback-k3s-stack.sh`
- `tar` and `date` for `scripts/backup-k3s-stack.sh`

### Docker Smoke Test

Required only for the containerized smoke test:

- `docker`

Command:

```bash
make test-smoke
```

### VM-Based Test Harness

Required only for the VM-based test harness:

- `multipass`

Commands:

```bash
make test-core
make test-matrix-all
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
./tests/test-in-vm.sh --platform debian12 --profile full-rollback
./tests/test-in-vm.sh --platform debian13 --profile full-clean
```

CI note:

- GitHub Actions uses a hosted `ubuntu-24.04` runner without Multipass
- hosted CI runs a full install, strict validation, and destructive cleanup directly on the hosted runner
- local Multipass validation remains the authoritative path for real VM install, rollback, and clean coverage across the supported matrix

### Utilities

Useful tools for inspection and troubleshooting:

- `jq`
- `curl`
- `docker` if you want to test registry push/pull from the host

### Practical Summary

If you only want to install and operate the stack locally, the practical host-side prerequisites are:

- `bash`
- `sudo`
- `curl`
- `getent`
- `make`

If you also want full contributor validation coverage, add:

- `docker`
- `multipass`
- `jq`

### Tool Reference

| Tool | Required | Used for |
| --- | --- | --- |
| `bash` | yes | running all repository scripts |
| `sudo` | yes | host package/service management and cluster operations |
| `curl` | yes | installer downloads and endpoint checks |
| `getent` | yes | user/home detection |
| `systemctl` | yes | service lifecycle management |
| `make` | optional | convenience targets |
| `docker` | optional | registry validation and smoke tests |
| `multipass` | optional | VM-based integration tests |
| `jq` | optional | rollback logic and JSON inspection |

## License

This project is licensed under the Apache License 2.0.

See [LICENSE](./LICENSE).
