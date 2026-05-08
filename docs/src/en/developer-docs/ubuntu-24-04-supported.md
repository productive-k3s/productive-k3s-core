# Ubuntu 24.04 Supported Platform

This document records the supported validation baseline for Ubuntu 24.04.

Ubuntu 24.04 is supported for this repository alongside Ubuntu 22.04, Debian 12, and Debian 13.

## Current Status

Status: supported

Target release:

- Ubuntu `24.04` LTS

Validation evidence retained:

- `smoke`: passed with artifact `status: "success"`
- `core`: passed with artifact `status: "success"`
- `full`: passed with artifact `status: "success"`
- `full-rollback`: passed with artifact `status: "success"`
- `full-clean`: passed with artifact `status: "success"`

Interpretation:

- Ubuntu 24.04 is validated for bootstrap, strict validation convergence, rollback, destructive cleanup, and the direct hosted validation path
- Ubuntu 24.04 should be treated as a supported platform, not as a candidate

## Scope

The validated model is:

- host: any machine capable of running Multipass
- VM guest: Ubuntu 24.04 image
- scripts: executed inside the Ubuntu 24.04 VM
- hosted CI: direct validation on `ubuntu-24.04`

## Harness Defaults

The VM harness supports:

```bash
./tests/test-in-vm.sh --platform ubuntu
```

When `--platform ubuntu` is used, the harness defaults to:

- image: `24.04`
- remote user: `ubuntu`
- remote directory: `/home/ubuntu/productive-k3s-core`

These values can be overridden:

```bash
./tests/test-in-vm.sh --platform ubuntu --image <image-or-release> --remote-user <user> --remote-dir <path>
```

The bootstrap detects the host OS through `/etc/os-release`.

Current behavior:

- Ubuntu: supported
- Debian 12: supported
- Debian 13: supported
- anything else: unsupported

## Supported Validation Sequence

Reference commands:

### 1. Smoke

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke
```

### 2. Core

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core
```

### 3. Full

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
```

### 4. Full Rollback

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
```

### 5. Full Clean

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

## Artifact Review

Check Ubuntu 24.04 artifacts:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*ubuntu*.json' ! -name '*-bootstrap-manifest.json' | sort | tail
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*ubuntu*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, platform, image, remote_user, remote_dir, vm_name}'
```

Pass criteria:

- each supported profile has `status: "success"`
- each supported profile has `platform: "ubuntu"`
- `image` should match `24.04` unless intentionally overridden

Use the `test-in-vm-*.json` artifact as the authoritative pass/fail signal.
