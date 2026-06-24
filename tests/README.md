# Productive K3S Core Tests

This directory now exposes two complementary test layers:

- existing live and VM-oriented validation scripts under `tests/*.sh`
- fast local unit-style checks under `tests/spec/` using `ShellSpec`
- suite-level artifact summaries for `matrix`, `local`, and `external` runs

The goal is to keep the public bootstrap scripts maintainable without forcing every change through a full VM or Docker cycle.

## Layout

```text
tests/
  bin/
  helpers/
  spec/
  spell/
```

Generated at runtime and intentionally not tracked:

- `tests/artifacts/`
- `tests/coverage/`

`fixtures/` and `mocks/` are not kept as empty placeholders in this repo. Add them only when a new spec actually needs shared fixture files or standalone mock executables.

## Commands

Run the normalized local test entrypoints:

```bash
make -C tests test
make -C tests test-unit
make -C tests test-lint
make -C tests test-format
make -C tests test-spell
make -C tests test-coverage
make -C tests test-clean-artifacts
make -C tests test-clean-vms
make -C tests test-clean-all
make -C tests test-local-all
make -C tests test-external-all
make -C tests test-checkstatus-local
make -C tests test-checkstatus-external
```

These commands are intentionally local-maintainer oriented. They do not redefine the existing live matrix or CI contract.

The VM matrix stays separate:

```bash
make -C tests test-matrix-all
make -C tests test-checkstatus-matrix
```

Dedicated Ubuntu 24.04 RKE2 entrypoints are also available:

```bash
make -C tests test-rke2-core
make -C tests test-rke2-core-ubuntu22
make -C tests test-rke2-full
make -C tests test-rke2-full-clean
make -C tests test-rke2-full-rollback
make -C tests test-rke2-ubuntu-all
```

Published stack artifact entrypoints are also available:

```bash
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-k3s
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-rke2
```

Semantics:

- `test-stacks` runs both published stack artifact matrices: `k3s` first, then `rke2`
- `test-stacks-k3s` runs the published stack artifact across the supported `k3s` VM matrix:
  - Ubuntu 24.04
  - Ubuntu 22.04
  - Debian 13
  - Debian 12
- `test-stacks-rke2` runs the published stack artifact across the supported `rke2` VM matrix:
  - Ubuntu 24.04
  - Ubuntu 22.04

Granular stack targets are also available for debugging one platform at a time:

```bash
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-k3s-ubuntu24
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-k3s-ubuntu22
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-k3s-debian13
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-k3s-debian12
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-rke2-ubuntu24
STACK_TGZ_URL=https://downloads.productive-k3s.io/addons/base-0.1.0.tgz make -C tests test-stacks-rke2-ubuntu22
```

From the repository root, keep only the three principal test entrypoints:

```bash
make test-local-all
make test-matrix-all
make test-external-all
```

Category intent:

- `matrix`: VM-backed integration profiles (`smoke`, `core`, `full`, `full-rollback`, `full-clean`)
- `local`: non-matrix suites that run locally without third-party services
- `external`: suites that may hit external endpoints, currently telemetry-related checks

Cleanup intent:

- `test-clean`: safe alias for artifact cleanup only
- `test-clean-artifacts`: remove local test artifacts and run metadata
- `test-clean-vms`: remove Productive K3S test VMs from Multipass and purge deleted instances
- `test-clean-all`: perform both VM cleanup and artifact cleanup

## Current ShellSpec Focus

- bootstrap argument parsing, manifests, installers, waits, retries, host helpers, cleanup, and dry-run paths
- telemetry helper behavior, payload delivery, retry handling, and failure recording
- host preflight platform detection, resource guidance, strict mode, and required command checks
- stack validation summary, default resource checks, and registry-related failure paths

## Current Coverage Baseline

Latest local `make test-coverage` run:

- total ShellSpec coverage: `75.06%`
- `scripts/apply.sh`: `78.17%`
- `scripts/preflight-host.sh`: `89.02%`
- `scripts/validate.sh`: `59.52%`
- `scripts/send-telemetry.sh`: `83.48%`
- `scripts/send-telemetry-event.sh`: `60.94%`

Treat this as a maintainer baseline for new changes, not as a hard CI gate.

## Tooling Notes

- `ShellSpec` runs the specs under `tests/spec/`
- `ShellCheck` lints shell sources in `scripts/` and `tests/`
- `shfmt` checks formatting for `*.sh`
- `kcov` generates shell coverage reports under `tests/coverage/`
- spell checking prefers `codespell` when available and falls back to a small typo scanner
