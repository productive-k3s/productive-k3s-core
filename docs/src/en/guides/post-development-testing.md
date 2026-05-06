# Post-Development Testing Guide

This guide defines the recommended validation sequence after making changes to this repository.

The goal is to keep a consistent testing path so changes to bootstrap, validation, rollback, cleanup, documentation, or helper scripts are checked in a predictable order.

## Scope

Use this guide after changes to:

- `scripts/bootstrap-k3s-stack.sh`
- `scripts/validate-k3s-stack.sh`
- `scripts/rollback-k3s-stack.sh`
- `scripts/clean-k3s-stack.sh`
- `tests/test-in-vm.sh`
- `tests/test-in-docker.sh`
- `utils/`
- `docs/`
- `Makefile`

## Recommended Sequence

Run the checks in this order.

### 1. Smoke test in Docker

Fast sanity check for the bootstrap harness and repository packaging.

```bash
make test-smoke
```

What it covers:

- Docker build context
- containerized smoke harness
- bootstrap dry-run path

### 2. Core VM test

Validates the minimal install path with `k3s` and `helm`, without forcing the full optional stack.

```bash
make test-core
```

What it covers:

- VM provisioning
- repository copy into VM
- minimal bootstrap install path
- non-strict validation of the core profile

Expected outcome:

- success with possible warnings about skipped optional components

### 3. Full VM test

Validates the full stack install path.

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
```

What it covers:

- `k3s`
- `helm`
- `cert-manager`
- `Longhorn`
- `Rancher`
- internal registry
- NFS setup
- strict validation convergence

Expected outcome:

- success with `Failures: 0`
- strict validation converges cleanly

### 4. Full rollback test

Validates manifest-guided rollback after a full install.

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
```

What it covers:

- full bootstrap path
- rollback plan generation
- rollback apply flow
- removal of installed stack components introduced by the test run

Expected outcome:

- rollback completes
- target namespaces and cluster-scoped resources are removed as expected
- the test artifact ends with `status: "success"`
- post-rollback checks confirm removal of:
  - `cert-manager`
  - `longhorn-system`
  - `cattle-system`
  - `registry`
  - `selfsigned` `ClusterIssuer`
  - bootstrap-managed NFS export
  - bootstrap-managed `/etc/hosts` entries

### 5. Full clean test

Validates destructive cleanup after a full install.

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

What it covers:

- full bootstrap path
- destructive cleanup flow
- `k3s` uninstall/cleanup path

Expected outcome:

- cleanup completes
- `k3s` is no longer active in the VM

### 6. VM cleanup

If test VMs remain, clean them explicitly.

```bash
./tests/test-in-vm-cleanup.sh
```

Useful follow-up checks:

```bash
ls -1 test-artifacts
multipass list
```

## Multipass Quick Reference

This repository uses `multipass` only as a host-side VM harness for integration testing.

The minimum commands contributors usually need are these.

### Check whether Multipass is available

```bash
multipass version
multipass list
multipass find --force-update
```

Use this before starting VM-based tests.

`multipass find --force-update` is especially useful when Multipass fails to refresh image metadata or fails while downloading a VM image.

### Run a VM-based test profile

Core profile:

```bash
make test-core
```

Full profiles:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

### Preserve a VM for manual inspection

If you want the test VM to remain after the run:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --keep-vm
```

This is useful when a test fails and you want to inspect the machine manually.

### Open a shell in a preserved VM

```bash
multipass shell <vm-name>
```

Typical follow-up checks inside the VM:

```bash
cd /home/ubuntu/productive-k3s
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
```

### Remove one preserved VM

```bash
./tests/test-in-vm-cleanup.sh --name <vm-name>
```

Equivalent direct `multipass` command:

```bash
multipass delete <vm-name>
```

### Remove all test VMs created by this repository

```bash
./tests/test-in-vm-cleanup.sh --all
```

This removes only VMs whose names start with `productive-k3s-test-`.

### Purge deleted instances

```bash
./tests/test-in-vm-cleanup.sh --all --purge
```

Equivalent direct `multipass` command:

```bash
multipass purge
```

### List artifacts after a VM run

```bash
ls -1 test-artifacts
```

Use the test artifact JSON, not only the copied bootstrap manifest, to determine pass/fail.

### Recommended minimal Multipass workflow

For most contributors, this is enough:

1. `multipass list`
2. `multipass find --force-update`
3. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full`
4. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback`
5. `./tests/test-in-vm-cleanup.sh --all --purge`

## Artifact Review

VM-based tests write artifacts under `test-artifacts/`.

There are two different kinds of JSON files there, and they do not mean the same thing.

### 1. Test result artifact

Pattern:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json'
```

Example:

```bash
test-artifacts/test-in-vm-20260422-192326-full-rollback-productive-k3s-test-full-rollback-20260422-192326.json
```

This is the file that tells you whether the test itself passed or failed.

Fields to check first:

- `status`
- `profile`
- `vm_name`
- `bootstrap_manifest_local`
- `bootstrap_manifest_remote`

Quick check:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, vm_name, bootstrap_manifest_local, bootstrap_manifest_remote}'
```

Pass criteria:

- `status: "success"` means the full test profile completed successfully
- `status: "failed"` means the test harness exited with an error, even if bootstrap partially succeeded

### 2. Bootstrap manifest copy

Pattern:

```bash
test-artifacts/*-bootstrap-manifest.json
```

Example:

```bash
test-artifacts/test-in-vm-20260422-192326-full-rollback-productive-k3s-test-full-rollback-20260422-192326-bootstrap-manifest.json
```

This is not the test result artifact. It is only a copied bootstrap manifest from the VM.

Important interpretation note:

- this file can contain `status: "success"` for the bootstrap run itself
- but it does not prove that the whole VM test passed
- it does not include the same top-level fields as the test result artifact

Use it for:

- rollback investigation
- bootstrap/rollback planning review
- component-level execution review

Do not use it as the primary source for pass/fail of `make test-core`, `--profile full`, `--profile full-rollback`, or `--profile full-clean`.

## How To Read A Successful Run

For VM-based profiles, the console output can show temporary failures during convergence. That is expected.

Examples:

- pods briefly in `ContainerCreating`
- `CrashLoopBackOff` during early Rancher/Fleet startup
- validation retries while the cluster converges

That does not mean the profile failed.

A run should be considered successful only if the ending is clean.

For `full`, the minimum expected ending is:

- validation reaches `Failures: 0`
- the artifact JSON records `status: "success"`
- the console ends with `VM test completed successfully`

For `full-rollback`, the minimum expected ending is:

- validation reaches `Failures: 0` before rollback starts
- rollback apply finishes
- rollback verification lines are all `Verified: ...`
- the artifact JSON records `status: "success"`
- the console ends with `VM test completed successfully`

## Current Contributor Baseline

At the time this guide was updated, the following sequence had been validated successfully from the generated artifacts:

1. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full`
2. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback`
3. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean`

When touching teardown logic, contributors should still run:

1. `make test-smoke`
2. `make test-core`
3. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full`
4. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback`
5. `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean`

Reference outcome recorded in local artifacts during this validation cycle:

- `full`: `status: "success"`
- `full-rollback`: `status: "success"`
- `full-clean`: `status: "success"`

## Recommended Local Validation

If the change affects the real host install path, run local validation too.

### Validate the current local stack

```bash
make validate
```

If the change targets stricter convergence rules:

```bash
make validate-strict
```

### Inspect the running local stack

```bash
./utils/inspect-ingress.sh
./utils/inspect-rancher.sh
./utils/inspect-longhorn.sh
./utils/inspect-longhorn-volumes.sh
./utils/list-registry-images.sh
```

## When To Run Which Tests

Suggested minimum:

- docs-only changes: review links and examples manually
- utility script changes: `make test-smoke`, `make test-core`
- bootstrap or validate changes: `make test-smoke`, `make test-core`, `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full`
- rollback or cleanup changes: full sequence including `full-rollback` and `full-clean`

## Failure Triage

If a test fails, capture:

- failing command
- VM name if applicable
- last bootstrap manifest under `runs/`
- copied artifact under `test-artifacts/`
- whether the failing JSON was the real test artifact or only the copied bootstrap manifest
- relevant output from the inspect scripts

Useful commands:

```bash
ls -1 test-artifacts
multipass list
multipass find --force-update
```

If `multipass launch` fails while retrieving headers, metadata, or image downloads, run `multipass find --force-update` and retry the test.

If a VM was preserved or is still running:

```bash
multipass shell <vm-name>
```

Inside the VM, common checks are:

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl get ingress -A
sudo k3s kubectl get sc
sudo k3s kubectl get certificates -A
```

## Pass Criteria

A change is considered validated when:

- the relevant test sequence completes successfully
- full profile validation converges cleanly
- rollback or clean tests pass when the change touches teardown logic
- local validation still behaves as expected for host-side changes

## Related Docs

- [Guides overview](index.md)
- [k3s checks](../reference/k3s-checks.md)
- [Ingress checks](../reference/ingress-checks.md)
- [Rancher checks](../reference/rancher-checks.md)
- [Registry checks](../reference/registry-checks.md)
- [Longhorn checks](../reference/longhorn-checks.md)
- [Certificate checks](../reference/certificate-checks.md)
