# Debian 13 Supported Platform

This document records the supported validation baseline for Debian 13.

Debian 13 is supported for this repository alongside Ubuntu 22.04, Ubuntu 24.04, and Debian 12.

## Current Status

Status: supported

Target release:

- Debian 13 `trixie`

Validation evidence retained:

- `smoke`: passed with artifact `status: "success"`
- `core`: passed with artifact `status: "success"`
- `full`: passed with artifact `status: "success"`
- `full-rollback`: passed with artifact `status: "success"`
- `full-clean`: passed with artifact `status: "success"`

Interpretation:

- Debian 13 is validated for bootstrap, strict validation convergence, rollback, and destructive cleanup
- Debian 13 should be treated as a supported platform, not as a candidate

## Scope

The validated model is:

- host: any machine capable of running Multipass
- VM guest: Debian 13 cloud image
- scripts: executed inside the Debian 13 VM

## Harness Defaults

The VM harness supports:

```bash
./tests/test-in-vm.sh --platform debian13
```

When `--platform debian13` is used, the harness defaults to:

- image: `https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2`
- remote user: `ubuntu`
- remote directory: `/home/ubuntu/productive-k3s`

These values can be overridden:

```bash
./tests/test-in-vm.sh --platform debian13 --image <image-or-url> --remote-user <user> --remote-dir <path>
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
./tests/test-in-vm.sh --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile smoke
```

### 2. Core

```bash
./tests/test-in-vm.sh --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile core
```

### 3. Full

```bash
./tests/test-in-vm.sh --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile full
```

### 4. Full Rollback

```bash
./tests/test-in-vm.sh --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile full-rollback
```

### 5. Full Clean

```bash
./tests/test-in-vm.sh --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile full-clean
```

## Artifact Review

Check Debian 13 artifacts:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*debian13*.json' ! -name '*-bootstrap-manifest.json' | sort | tail
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*debian13*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, platform, image, remote_user, remote_dir, vm_name}'
```

Pass criteria:

- each supported profile has `status: "success"`
- each supported profile has `platform: "debian13"`
- `image` should match the Debian 13 cloud image unless intentionally overridden

Use the `test-in-vm-*.json` artifact as the authoritative pass/fail signal.
