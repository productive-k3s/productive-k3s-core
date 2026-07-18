# Supported Platforms

This page summarizes the supported runtime targets for Productive K3S Core and the practical sizing guidance for a single-node host.

The point of this support matrix is not to claim every Kubernetes-shaped environment. The point is to keep the simple starting path reliable and explicit.

The tool is prepared for production-oriented environments based on the most widely used non-proprietary operating systems across common cloud and VM platforms. In practice, that is why the supported runtime targets end up being Linux distributions.

At the same time, the development workflow provides a practical way for contributors using Windows or macOS to work on improvements to the tool scripts by using Multipass and supported Linux VMs.

## Supported Targets

The repository is validated and supported on:

- Ubuntu `24.04` LTS on `amd64`
- Ubuntu `24.04` LTS on `arm64`
- Ubuntu `22.04` LTS on `amd64`
- Debian `13` `trixie` on `amd64`
- Debian `12` `bookworm` on `amd64`

Support means the retained validation evidence includes these flows:

- `smoke`
- `core`
- `full`
- `full-rollback`
- `full-clean`

## Validation Model

- Ubuntu `24.04` on `amd64` has both direct hosted validation and VM-based validation
- Ubuntu `24.04` on `arm64` has retained public validation through the on-prem ARM path
- Ubuntu `22.04`, Debian `12`, and Debian `13` are validated through the VM harness
- Debian support refers to the runtime inside the validated VM guest, not to GitHub-hosted direct-run CI
- the retained public ARM validation is currently specific to Ubuntu `24.04`

## Platform Assumptions

- package installation assumes `apt-get`
- service management assumes `systemd`
- VM-based integration testing is centered on `multipass`
- Windows and macOS are relevant only as host environments capable of running Linux VMs

## Minimum Hardware

Practical minimum for the full stack:

- CPU: `4 vCPU`
- RAM: `12 GB`
- Disk: `60 GB` free SSD space

Recommended for a smoother experience:

- CPU: `6-8 vCPU`
- RAM: `16 GB`
- Disk: `100 GB+` free SSD space

## Why the baseline is not smaller

- `Rancher` and `Longhorn` add steady control-plane overhead
- the internal registry consumes persistent storage
- stateful workloads need headroom beyond the base platform itself
- low free disk space is especially problematic for `Longhorn`

## See also

- [Ubuntu 22.04 support baseline](../developer-docs/ubuntu-22-04-supported.md)
- [Ubuntu 24.04 support baseline](../developer-docs/ubuntu-24-04-supported.md)
- [Debian 12 support baseline](../developer-docs/debian-12-supported.md)
- [Debian 13 support baseline](../developer-docs/debian-13-supported.md)
- [Post-development testing](../developer-docs/guides/post-development-testing.md)
