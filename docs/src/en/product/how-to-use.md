# How to Use Productive K3S Core

The simplest way to use `productive-k3s-core` is to treat it as the direct path into a real Kubernetes base.

Use Core directly when:

- you want the clearest base installation contract;
- you want to understand exactly how the cluster base is assembled;
- you want explicit control over addon or stack installation after the base cluster exists.

If you prefer the simplest and recommended ecosystem experience, use `pk3s` and come back to Core only when you need component-level detail.

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
curl -fsSL https://github.com/productive-k3s/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- preflight
```

If you want warnings to fail the command as well, use:

```bash
curl -fsSL https://github.com/productive-k3s/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- preflight --strict
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
curl -fsSL https://github.com/productive-k3s/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- apply --dry-run
```

Even in `dry-run`, the script may still show prompts based on what it detects on the host, for example whether an existing `k3s` installation should be reused. Those prompts are used to build the execution plan, but `dry-run` still does not apply changes.

## What will happen on the host

The bootstrap is expected to run on the target machine itself. It can:

- install missing OS packages with `apt-get`
- install or reuse `k3s`
- install or reuse `helm`
- later install explicit stacks or add-ons on top of that local core installation

By default, the practical target is a single supported VM or Linux host, and the public `apply` contract is core-only.

This is not intended for an arbitrary Linux distribution. The target must match the [supported platforms](supported-platforms.md) page, whether it is a real host or a VM.

## Advanced install engines

The default and expected install engine is the native repository bootstrap path built into Core.

An optional experimental environment variable is also available:

```bash
PRODUCTIVE_K3S_ENGINE=native|k3sup
```

- `native`: default and primary supported path
- `k3sup`: optional experimental backend for the base K3S installation step

`k3sup` was integrated as a complementary option, not as a replacement for `productive-k3s-core`.
Its purpose is to let advanced users experiment with the same Productive K3S base decisions while using a K3S install tool they already know.

The same contract is also what leaves room for more advanced engine choices such as `rke2` in broader Productive K3S evolution.

Important scope boundaries:

- `productive-k3s-core` remains the bootstrap, validation, and operations layer
- `k3sup` only affects the base K3S installation backend
- stack behavior after K3S exists does not change
- the support guarantees remain the ones documented in the repository support matrix

If you use `PRODUCTIVE_K3S_ENGINE=k3sup`, treat it as experimental.
In split-node or manually orchestrated flows, you are responsible for providing the correct SSH context and related environment when that backend needs it.
That does not expand the public support matrix to arbitrary platforms or arbitrary orchestration models.

## Basic install

Replace `X.Y.Z` with the release you want to install:

```bash
curl -fsSL https://github.com/productive-k3s/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- apply
```

That installer downloads the matching release bundle and runs the public `productive-k3s-core` CLI on the host.

If you also want the default stack after the core is ready:

```bash
curl -fsSL https://github.com/productive-k3s/productive-k3s-core/releases/download/X.Y.Z/productive-k3s-core-cli.sh | bash -s -- stack install base
```

## After install

Once the bootstrap finishes, use the validation and reference docs to inspect the result:

- [Host preflight](../user-docs/host-preflight.md)
- [k3s checks](../user-docs/k3s-checks.md)
- [Ingress checks](../user-docs/ingress-checks.md)
- [Rancher checks](../user-docs/rancher-checks.md)
- [Registry checks](../user-docs/registry-checks.md)
- [Longhorn checks](../user-docs/longhorn-checks.md)
- [Certificate checks](../user-docs/certificate-checks.md)
