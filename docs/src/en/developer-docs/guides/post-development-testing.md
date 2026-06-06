# Post-Development Testing Guide

This page defines the default local workflow for running tests after making changes in `productive-k3s-core`.

The goal is simple:

1. start from a clean local test state
2. run the test target you want
3. ask the repository to summarize which tests passed or failed

## Recommended local workflow

For day-to-day development, use this sequence from the repository root:

```bash
make test-clean
make <test-target>
make test-checkstatus
```

## Local test tooling

The repository now also exposes a fast local-maintainer layer:

```bash
make test
make test-unit
make test-lint
make test-format
make test-spell
make test-coverage
```

Those targets use:

- `ShellSpec` for unit-style shell tests under `tests/spec/`
- `ShellCheck` for shell linting
- `shfmt` for formatting checks
- `codespell` for lightweight spell checks
- `kcov` for shell coverage reports

If you install tools without root, keep `~/.local/bin` in `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

User-local install commands used during development on Ubuntu:

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
curl -fsSLO https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz
tar -xJf shellcheck-v0.11.0.linux.x86_64.tar.xz
install shellcheck-v0.11.0/shellcheck "$HOME/.local/bin/shellcheck"

curl -fsSLo "$HOME/.local/bin/shfmt" https://github.com/mvdan/sh/releases/download/v3.13.1/shfmt_v3.13.1_linux_amd64
chmod +x "$HOME/.local/bin/shfmt"

curl -fsSLO https://github.com/shellspec/shellspec/releases/download/0.28.1/shellspec-dist.tar.gz
mkdir -p "$HOME/.local/share/shellspec"
tar -xzf shellspec-dist.tar.gz -C "$HOME/.local/share/shellspec"
cat > "$HOME/.local/bin/shellspec" <<'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/share/shellspec/shellspec/shellspec" "$@"
EOF
chmod +x "$HOME/.local/bin/shellspec"
```

`codespell` can be installed with:

```bash
python3 -m pip install --user codespell
```

`kcov` is the one exception on this machine: building it locally failed because Ubuntu `22.04` is missing `libelf` and `elfutils` development headers. On Ubuntu, install it with root privileges when you want shell coverage:

```bash
sudo apt-get update
sudo apt-get install -y kcov libelf-dev libdw-dev
```

Example:

```bash
make test-clean
make test-matrix-all
make test-checkstatus
```

## Current local coverage baseline

The current maintainer baseline from the latest local `make test-coverage` run is:

- total ShellSpec coverage: `75.06%`
- `scripts/apply.sh`: `78.17%`
- `scripts/preflight-host.sh`: `89.02%`
- `scripts/validate.sh`: `59.52%`
- `scripts/send-telemetry.sh`: `83.48%`
- `scripts/send-telemetry-event.sh`: `60.94%`

This baseline is intended to guide future additions and refactors. It is not yet enforced as a CI threshold.

## What these targets do

### `make test-clean`

Removes the local files that this repository uses as test state:

- `test-artifacts/`
- local `runs/apply-*.json`
- local `runs/telemetry-outbox/bootstrap-*.json`
- local `runs/telemetry-outbox/bootstrap-*.status`

Use it before starting a new validation cycle when you want `make test-checkstatus` to describe only the current run.

### `make test-checkstatus`

Scans the current test result artifacts under `test-artifacts/` and prints a concise summary of the recorded outcomes.

It reports entries such as:

- VM-based test results written by `tests/test-in-vm.sh`
- GitHub-hosted summary results written by `tests/test-on-gh-hosted.sh`

It intentionally ignores files that are not the real top-level test result:

- copied bootstrap manifests like `*-apply-manifest.json`
- public privacy-scrubbed companion artifacts like `*-public.json`

If at least one recorded test result is failed, `make test-checkstatus` exits non-zero.

If no test result artifacts are present, it also exits non-zero and tells you that no status could be determined.

## Common test targets

Use these root targets most often:

| Target | Purpose |
| --- | --- |
| `make test-smoke` | Fast Docker-based smoke validation |
| `make test-core` | Core VM validation on Ubuntu `24.04` |
| `make test-core-debian12` | Core VM validation on Debian `12` |
| `make test-core-debian13` | Core VM validation on Debian `13` |
| `make test-matrix-smoke` | Smoke matrix across Ubuntu and Debian |
| `make test-matrix-core` | Core matrix across Ubuntu and Debian |
| `make test-matrix-full` | Full stack matrix across Ubuntu and Debian |
| `make test-matrix-full-rollback` | Full rollback matrix across Ubuntu and Debian |
| `make test-matrix-full-clean` | Full cleanup matrix across Ubuntu and Debian |
| `make test-matrix-all` | Run every matrix profile in sequence and preserve all result artifacts for final status review |

## Why `test-matrix-all` is special

The matrix profiles under `tests/Makefile` still validate each profile independently, but the aggregate `run-all-tests` path now cleans only once at the beginning.

That means this workflow works as expected:

```bash
make test-clean
make test-matrix-all
make test-checkstatus
```

At the end of that sequence, `test-checkstatus` can still see the accumulated artifacts from the full matrix run instead of only the final profile.

## When a test fails

Start with:

```bash
make test-checkstatus
```

Then inspect the matching artifact files in `test-artifacts/`.

Useful follow-up commands:

```bash
ls -1 test-artifacts
jq . test-artifacts/<artifact>.json
```

For VM-based failures, preserve the VM when needed:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --keep-vm
```

Then inspect it:

```bash
multipass shell <vm-name>
cd /home/ubuntu/productive-k3s-core
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
```

## Notes

!!! note
    `make test-checkstatus` summarizes recorded test outcomes. It does not replace reading the full artifact JSON when you need detailed debugging context.

!!! note
    `make test-clean` removes local test state for this repository only. It does not delete preserved Multipass VMs. Use `./tests/test-in-vm-cleanup.sh` for that.
