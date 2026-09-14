# Productive K3S Exported Stack Bundle

This directory is a bootstrap project generated from Productive K3S. It replays
the exported stack installation for `{{subject_ref}}`, and can also be used as
the starting point for a project-specific deployment repository.

The generated files are meant to be readable and editable. Keep the Productive
K3S references below as provenance: they explain where the runtime came from and
where to look when a future maintainer or agent needs upstream context.

## Contents

- `install.sh` replays the exported installation using the bundled Core runtime.
- `preflight.sh` verifies bundle structure, stack metadata, and host prerequisites before installation.
- `{{artifact_name}}` is the packaged stack artifact consumed by the installer.
- `install-config.env` freezes exported environment defaults for this bundle.
- `manifest.json` records the exported command metadata.
- `AGENTS.md` explains the bundle for automation agents and future repository maintainers.

## Usage

```bash
./preflight.sh
./install.sh
```

To validate without installing:

```bash
./install.sh --preflight-only
```

To replay after a preflight already passed in the same environment:

```bash
./install.sh --skip-preflight
```

This bundle is self-contained with respect to Productive K3S tooling, but it may still require host prerequisites, Kubernetes access, cluster credentials, and network access at install time.

## Manual Customization

- Edit `install-config.env` for exported environment defaults such as distro,
  engine, or telemetry flags.
- Pass extra Core runtime flags to `./install.sh`; unsupported bundle flags are
  forwarded to `productive-k3s-core.sh stack install`.
- Keep `preflight.sh` enabled for the first run so missing commands, broken
  bundle contents, or host readiness problems fail before installation starts.
- Replace `{{artifact_name}}` only with another valid packaged stack artifact.
  Re-run `./preflight.sh` after replacing it.
- Add local project scripts or CI next to `install.sh` instead of editing files
  under `scripts/`, unless this repository intentionally forks the vendored
  Productive K3S Core runtime.

## Project Structure

- `install.sh` is the main entrypoint for humans and automation.
- `preflight.sh` validates the bundle and target host before installation.
- `{{artifact_name}}` is the replaceable packaged stack artifact.
- `install-config.env` is the safest place for local environment defaults.
- `manifest.json` records what was exported.
- `AGENTS.md` gives automation agents a working map of this bootstrap.
- `productive-k3s-core.sh` and `scripts/` are vendored Productive K3S Core
  runtime files. You can fork them, but normal project customization should live
  beside them.

## Upstream References

- Productive K3S Core: https://github.com/productive-k3s/productive-k3s-core
- Productive K3S CLI: https://github.com/productive-k3s/productive-k3s-cli
- Productive K3S Addons: https://github.com/productive-k3s/productive-k3s-addons
