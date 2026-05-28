# Productive K3S Core Tests

This directory now exposes two complementary test layers:

- existing live and VM-oriented validation scripts under `tests/*.sh`
- fast local unit-style checks under `tests/spec/` using `ShellSpec`

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
make test
make test-unit
make test-lint
make test-format
make test-spell
make test-coverage
```

These commands are intentionally local-maintainer oriented. They do not redefine the existing live matrix or CI contract.

## Current ShellSpec Focus

- bootstrap argument parsing, manifests, installers, waits, retries, host helpers, cleanup, and dry-run paths
- telemetry helper behavior, payload delivery, retry handling, and failure recording
- host preflight platform detection, resource guidance, strict mode, and required command checks
- stack validation summary, default resource checks, and registry-related failure paths

## Current Coverage Baseline

Latest local `make test-coverage` run:

- total ShellSpec coverage: `75.06%`
- `scripts/bootstrap-k3s-stack.sh`: `78.17%`
- `scripts/preflight-host.sh`: `89.02%`
- `scripts/validate-k3s-stack.sh`: `59.52%`
- `scripts/send-telemetry.sh`: `83.48%`
- `scripts/send-telemetry-event.sh`: `60.94%`

Treat this as a maintainer baseline for new changes, not as a hard CI gate.

## Tooling Notes

- `ShellSpec` runs the specs under `tests/spec/`
- `ShellCheck` lints shell sources in `scripts/` and `tests/`
- `shfmt` checks formatting for `*.sh`
- `kcov` generates shell coverage reports under `tests/coverage/`
- spell checking prefers `codespell` when available and falls back to a small typo scanner
