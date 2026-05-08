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

Example:

```bash
make test-clean
make test-matrix-all
make test-checkstatus
```

## What these targets do

### `make test-clean`

Removes the local files that this repository uses as test state:

- `test-artifacts/`
- local `runs/bootstrap-*.json`
- local `runs/telemetry-outbox/bootstrap-*.json`
- local `runs/telemetry-outbox/bootstrap-*.status`

Use it before starting a new validation cycle when you want `make test-checkstatus` to describe only the current run.

### `make test-checkstatus`

Scans the current test result artifacts under `test-artifacts/` and prints a concise summary of the recorded outcomes.

It reports entries such as:

- VM-based test results written by `tests/test-in-vm.sh`
- GitHub-hosted summary results written by `tests/test-on-gh-hosted.sh`

It intentionally ignores files that are not the real top-level test result:

- copied bootstrap manifests like `*-bootstrap-manifest.json`
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
