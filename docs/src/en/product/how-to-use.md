# How to Use Productive K3S

The simplest way to use `productive-k3s` is to run the release installer on one of the [supported platforms](supported-platforms.md), in a host or a VM with those operating systems.

Required host/VM commands for this install path:

- `bash`
- `sudo`
- `curl`
- `tar`
- `sha256sum`
- `mktemp`

## Before install

Before running the bootstrap, you can validate whether the target host matches the public platform assumptions and hardware guidance:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- preflight
```

If you want warnings to fail the command as well, use:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- preflight --strict
```

This preflight checks the supported platform list, `systemd` expectation, required commands, and practical hardware guidance for the selected mode.

If you already have the repository checked out locally, the equivalent root targets are still available:

```bash
make preflight
make preflight-strict
```

See [Host preflight](../user-docs/host-preflight.md) for the detailed behavior.

If you want to see how the installer would run before changing anything on the machine, you can first do an optional dry run:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- bootstrap --dry-run
```

Even in `dry-run`, the script may still show prompts based on what it detects on the host, for example whether an existing `k3s` installation should be reused. Those prompts are used to build the execution plan, but `dry-run` still does not apply changes.

## What will happen on the host

The bootstrap is expected to run on the target machine itself. It can:

- install missing OS packages with `apt-get`
- install or reuse `k3s`
- install or reuse `helm`
- configure the local single-node stack components

By default, the practical target is a single supported VM or Linux host.

This is not intended for an arbitrary Linux distribution. The target must match the [supported platforms](supported-platforms.md) page, whether it is a real host or a VM.

## Basic install

Replace `X.Y.Z` with the release you want to install:

```bash
curl -fsSL https://github.com/jemacchi/productive-k3s/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- bootstrap
```

That installer downloads the matching release bundle and runs the public `productive-k3s` CLI on the host.

## After install

Once the bootstrap finishes, use the validation and reference docs to inspect the result:

- [Host preflight](../user-docs/host-preflight.md)
- [k3s checks](../user-docs/k3s-checks.md)
- [Ingress checks](../user-docs/ingress-checks.md)
- [Rancher checks](../user-docs/rancher-checks.md)
- [Registry checks](../user-docs/registry-checks.md)
- [Longhorn checks](../user-docs/longhorn-checks.md)
- [Certificate checks](../user-docs/certificate-checks.md)
