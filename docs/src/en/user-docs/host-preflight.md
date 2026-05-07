# Host Preflight

`Productive K3S` includes a host-side compatibility check you can run before bootstrap.

## Purpose

Use this tool when you want to answer a simple question before installation:

Is this host or VM aligned with the supported platform assumptions for `productive-k3s`?

It is especially useful when:

- validating a fresh VM before installation
- checking whether a reused cloud instance still matches the expected baseline
- failing early in automation before starting the interactive bootstrap

## Basic usage

From the repository root:

```bash
make preflight
```

Or call the script directly:

```bash
./scripts/preflight-host.sh
```

Or call the operational wrapper:

```bash
./productive-k3s.sh preflight
```

Or use the release installer path without cloning the repository:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/X.Y.Z/productive-k3s-cli.sh | bash -s -- preflight
```

## Strict mode

By default, warning-level findings do not fail the command.

If you want warnings to return a non-zero exit code too:

```bash
make preflight-strict
```

Or:

```bash
./productive-k3s.sh preflight --strict
```

## Mode-aware checks

You can evaluate the host against a specific runtime profile:

```bash
./scripts/preflight-host.sh --mode single-node
./scripts/preflight-host.sh --mode server
./scripts/preflight-host.sh --mode agent
./scripts/preflight-host.sh --mode stack
```

`single-node` is the default.

## What it checks

The preflight currently validates:

- supported platform and version
- supported CPU architecture
- `systemd` as PID 1
- required commands such as `sudo`, `curl`, `getent`, `apt-get`, `systemctl`, `tar`, `sha256sum`, and `mktemp`
- sudo posture
- practical hardware guidance for `single-node` and `stack`

Today, the public support baseline is `amd64`/`x86_64`.

Architectures such as `arm64`/`aarch64` are intentionally reported as unsupported for now, even on otherwise valid Ubuntu or Debian targets.

The hardware guidance follows the published platform baseline:

- practical minimum: `4 vCPU`, `12 GiB` RAM, `60 GiB` free disk
- recommended: `6-8 vCPU`, `16 GiB` RAM, `100+ GiB` free disk

## Output model

The tool emits:

- `OK` for checks that look aligned
- `WARN` for soft issues or shortfalls
- `FAIL` for blockers that make the target unsuitable

For automation, use machine-readable output:

```bash
./productive-k3s.sh preflight --json-output
```

## What it does not do

The preflight is not a dry-run installer.

It does not:

- install missing packages
- modify the host
- validate a running cluster
- replace the post-install validator

Use this before bootstrap. Use [k3s checks](k3s-checks.md) and the rest of the validation pages after bootstrap.
