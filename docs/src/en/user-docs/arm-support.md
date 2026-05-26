# ARM Support

This page documents the current public ARM support baseline for `productive-k3s-core`.

## Supported public ARM path

The retained public ARM validation currently includes:

- Ubuntu `24.04` Desktop on `arm64`
- Raspberry Pi 5 Model B Rev `1.1`
- `4` CPU cores
- about `7.7 GiB` RAM

That retained validation successfully completed:

- host preflight
- `server` bootstrap
- `stack` bootstrap
- validation of `cert-manager`, `Longhorn`, `Rancher`, and the in-cluster registry

## Practical interpretation

ARM is now part of the public support matrix for Ubuntu `24.04`.

That does not mean every small ARM board is generous hardware for the full stack. The retained Raspberry Pi validation proves viability, but it still sits below the published full-stack RAM guidance, so users should expect tighter margins than on larger x86 hosts.

## Host expectations

The ARM host still needs the same base assumptions as the rest of the supported matrix:

- `systemd`
- `apt-get`
- `curl`
- `sudo`
- outbound Internet access during bootstrap downloads

## Related docs

- [Supported platforms](../product/supported-platforms.md)
- [Host preflight](host-preflight.md)
