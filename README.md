# Productive K3S Core

`productive-k3s-core` is the bootstrap, validation, and operations engine for a production-oriented `k3s` stack on a supported single host or VM.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-yellow.svg)](./LICENSE)
![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Ubuntu 22.04](https://img.shields.io/badge/Ubuntu-22.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Debian 13](https://img.shields.io/badge/Debian-13%20trixie-A81D33?logo=debian&logoColor=white)
![Debian 12](https://img.shields.io/badge/Debian-12%20bookworm-A81D33?logo=debian&logoColor=white)

The stack includes:

- `cert-manager`
- `Longhorn`
- `Rancher`
- internal registry
- host NFS export

Bootstrap modes:

- `single-node`: install the base node and optionally the full stack on the same machine
- `server`: install only the base server bootstrap components
- `agent`: join a node to an existing K3S server
- `stack`: install or reuse stack components on top of an existing cluster

Optional install engine:

- `PRODUCTIVE_K3S_ENGINE=native`: default and expected path
- `PRODUCTIVE_K3S_ENGINE=k3sup`: experimental complementary backend for the base K3S install step

`k3sup` integration does not redefine the scope of `productive-k3s-core`.
The repository support guarantees are still the tested platform and mode matrix documented in the project, not arbitrary third-party orchestration combinations.

Current public support baseline:

- Ubuntu `24.04` on `amd64` and `arm64`
- Ubuntu `22.04` on `amd64`
- Debian `12` and `13` on `amd64`

## Documentation

The long-form documentation lives in the published site.

Start here:

- [Site home](https://core.productive-k3s.io/)
- [English docs](https://core.productive-k3s.io/en/)
- [Spanish docs](https://core.productive-k3s.io/es/)
- [Product overview](https://core.productive-k3s.io/en/product/)
- [User docs](https://core.productive-k3s.io/en/user-docs/)
- [Developer docs](https://core.productive-k3s.io/en/developer-docs/)

## Product

Use these pages for the high-level product view instead of repeating the same rationale in the README:

- [How to use Productive K3S Core](https://core.productive-k3s.io/en/product/how-to-use/)
- [Reasons behind the stack](https://core.productive-k3s.io/en/product/reasons-behind/)
- [Supported platforms](https://core.productive-k3s.io/en/product/supported-platforms/)
- [Relationship with Productive K3S Infra](https://core.productive-k3s.io/en/product/productive-k3s-infra-relationship/)

## User Docs

Operational checks and user-facing references:

- [Host preflight](https://core.productive-k3s.io/en/user-docs/host-preflight/)
- [k3s checks](https://core.productive-k3s.io/en/user-docs/k3s-checks/)
- [Ingress checks](https://core.productive-k3s.io/en/user-docs/ingress-checks/)
- [Rancher checks](https://core.productive-k3s.io/en/user-docs/rancher-checks/)
- [Registry checks](https://core.productive-k3s.io/en/user-docs/registry-checks/)
- [Longhorn checks](https://core.productive-k3s.io/en/user-docs/longhorn-checks/)
- [Certificate checks](https://core.productive-k3s.io/en/user-docs/certificate-checks/)
- [Longhorn single-node notes](https://core.productive-k3s.io/en/user-docs/longhorn-single-node-notes/)
- [Privacy and telemetry](https://core.productive-k3s.io/en/user-docs/privacy-and-telemetry/)

## Developer Docs

Repository references and maintainer guidance:

- [Make targets for development](https://core.productive-k3s.io/en/developer-docs/make-targets/)
- [Productive K3S Core modes](https://core.productive-k3s.io/en/developer-docs/productive-k3s-modes/)
- [Scripts parameters](https://core.productive-k3s.io/en/developer-docs/script-parameters/)
- [GitHub Actions and release automation](https://core.productive-k3s.io/en/developer-docs/github-actions/)
- [macOS development](https://core.productive-k3s.io/en/developer-docs/guides/macos-development/)
- [Windows development](https://core.productive-k3s.io/en/developer-docs/guides/windows-development/)
- [Post-development testing](https://core.productive-k3s.io/en/developer-docs/guides/post-development-testing/)
- [Ubuntu 24.04 supported platform](https://core.productive-k3s.io/en/developer-docs/ubuntu-24-04-supported/)
- [Ubuntu 22.04 supported platform](https://core.productive-k3s.io/en/developer-docs/ubuntu-22-04-supported/)
- [Debian 13 supported platform](https://core.productive-k3s.io/en/developer-docs/debian-13-supported/)
- [Debian 12 supported platform](https://core.productive-k3s.io/en/developer-docs/debian-12-supported/)

## Practical Summary

If you only want to install and operate the stack locally, the practical host-side prerequisites are:

- Linux host with `systemd`
- `bash`
- `sudo`
- `curl`
- `getent`
- `tar`
- `sha256sum`
- `mktemp`

Before bootstrap, you can validate the target host with [Host preflight](https://core.productive-k3s.io/en/user-docs/host-preflight/), directly with `make preflight`, or through the release installer path:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- preflight
```

To inspect the CLI/runtime bill of materials for a local checkout or a published bundle:

```bash
./productive-k3s-core.sh bundle info --json
./productive-k3s-core.sh bom --json
```

The versions pinned for the managed stack components live in [scripts/component-versions.sh](./scripts/component-versions.sh). The bootstrap flow and the BOM both read from that same file so the reported versions match what the installer actually selects.

Telemetry consent is only relevant for mutating public CLI flows such as `apply` and `addon install`. Read-only commands like `help`, `bundle info --json`, and `bom --json` do not prompt for telemetry and do not emit command-level telemetry events.

`addon install` also supports an optional basic public exposure contract:

```bash
./productive-k3s-core.sh addon install --tgz ./nginx-addon.tgz --public-host nginx-01.k3s.lab.internal --cluster-context default
```

Core's responsibility is intentionally narrow here:

- validate that the add-on declares basic public ingress support
- create a standard Traefik ingress for one host routed to one service and port
- reject obvious host collisions

Core is not the generic ingress feature engine for every add-on. Advanced behavior such as custom paths, custom TLS material, multiple hosts, or arbitrary ingress annotations remains an add-on responsibility.

If you also want full repository validation coverage, add:

- `docker`
- `multipass`
- `jq`

See the linked site pages above for details, platform notes, and validation expectations.

## License

This project is licensed under the Apache License 2.0.

See [LICENSE](./LICENSE).
