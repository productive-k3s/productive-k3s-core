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

Current public support baseline:

- Ubuntu `24.04` and `22.04` on `amd64`
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

If you also want full repository validation coverage, add:

- `docker`
- `multipass`
- `jq`

See the linked site pages above for details, platform notes, and validation expectations.

## License

This project is licensed under the Apache License 2.0.

See [LICENSE](./LICENSE).
