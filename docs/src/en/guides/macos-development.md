# macOS Development Guide

This guide explains how a developer using macOS can work on this repository and run the VM-based validation flow.

The important model is:

- macOS is the developer workstation and Multipass host
- the repository test harness launches a supported Linux VM through Multipass
- the stack scripts run inside that Linux VM
- the scripts are not intended to run directly on macOS

## Support Statement

This tool has been developed and validated against Linux hosts and supported Linux Multipass VMs.

For macOS developers, the supported target model is:

- use macOS only as the host operating system
- use Multipass to launch supported Linux test VMs
- run repository scripts from the macOS shell through `tests/test-in-vm.sh`

Do not treat this as native macOS support.

You can collaborate on the development of the tool from macOS, but that does not mean the tool runs natively on macOS. The supported approach is to use macOS only as the developer host and validate the tool inside supported Linux VMs.

Native macOS execution is out of scope because the scripts assume Linux host behavior such as:

- `bash`
- `sudo`
- `systemd`
- Linux networking
- Linux filesystems
- `/etc/hosts`
- `/etc/exports`
- `k3s`
- `containerd`

## Recommended macOS Setup

Recommended components:

- macOS `13.3` or later
- Multipass for macOS
- Terminal or iTerm2
- Git
- `make` if you want to use `Makefile` targets

Optional but useful:

- VS Code
- VirtualBox only if you intentionally want to use it instead of the default Multipass backend

Official references:

- Multipass installation: https://documentation.ubuntu.com/multipass/en/latest/how-to-guides/install-multipass
- Multipass drivers: https://documentation.ubuntu.com/multipass/latest/explanation/driver/
- Driver setup: https://documentation.ubuntu.com/multipass/latest/how-to-guides/customise-multipass/set-up-the-driver

## Why This Model Is Recommended

The test harness is written in Bash and expects Linux-style behavior on the target machine.

On macOS, the clean way to work with this repository is:

1. install Multipass on macOS
2. clone this repository locally
3. run `tests/test-in-vm.sh` from the macOS shell
4. let Multipass create and destroy supported Linux VMs

This keeps the development host separate from the supported runtime target.

## Baseline Validation Flow From macOS

Start with cheap checks before running the full stack.

### 1. Confirm Multipass is reachable

From Terminal:

```bash
multipass version
multipass list
```

Unlike Windows, there is no `multipass.exe` path here. The normal `multipass` CLI should be available directly in the macOS shell.

### 2. Run the smoke VM profile

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke
```

This is the first check to run from macOS. It validates that:

- the Bash test harness runs from the macOS shell
- Multipass is reachable
- a VM can be launched
- the repository can be transferred to the VM
- the bootstrap dry-run path works

### 3. Run the core VM profile

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core
```

This validates the minimal install path:

- VM launch
- repository transfer
- `k3s`
- `helm`
- basic validation

### 4. Run the full profiles

After `smoke` and `core` pass:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean
```

These profiles are slower and heavier. They install and validate the full stack in a supported Linux VM.

The baseline examples in this guide use Ubuntu `24.04`, but the harness also supports:

- Ubuntu `22.04`
- Debian `12`
- Debian `13`

## Selecting The Ubuntu VM Image

The VM image defaults to Ubuntu `24.04`.

To test Ubuntu `22.04`:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile core
./tests/test-in-vm.sh --platform ubuntu --image 22.04 --profile full
```

Use this when you want to validate compatibility with the current real-host baseline.

## Preserving A Failed VM

By default, the test harness deletes the VM after the run.

To keep the VM for troubleshooting:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --keep-vm
```

Then inspect it:

```bash
multipass shell <vm-name>
```

Inside the VM:

```bash
cd /home/ubuntu/productive-k3s
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A -o wide
sudo k3s kubectl get ingress -A
sudo k3s kubectl get sc
```

## Cleaning Up Test VMs

Remove one VM:

```bash
./tests/test-in-vm-cleanup.sh --name <vm-name>
```

Remove all repository-created test VMs:

```bash
./tests/test-in-vm-cleanup.sh --all
```

Remove and purge deleted instances:

```bash
./tests/test-in-vm-cleanup.sh --all --purge
```

Direct Multipass commands:

```bash
multipass list
multipass delete <vm-name>
multipass purge
```

The cleanup helper only targets VMs whose names start with:

```text
productive-k3s-test-
```

## Reading Test Results

VM tests write artifacts under:

```bash
test-artifacts/
```

The pass/fail source of truth is the test result artifact:

```bash
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json'
```

Check recent results:

```bash
ls -1t test-artifacts/*.json | head
find test-artifacts -maxdepth 1 -type f -name 'test-in-vm-*.json' ! -name '*-bootstrap-manifest.json' -print0 \
  | xargs -0 jq '{status, profile, image, vm_name}'
```

Successful runs should show:

```json
"status": "success"
```

Do not use `*-bootstrap-manifest.json` as the primary pass/fail indicator. Those files describe the bootstrap run, not the whole VM test profile.

## Common Troubleshooting

### `multipass: command not found`

Check:

- Multipass is installed on macOS
- you opened a new shell after installing it
- the `multipass` binary is on your shell `PATH`

If needed:

```bash
which multipass
```

### Multipass cannot launch a VM

Check:

- enough CPU, RAM, and disk are available
- macOS virtualization features are available
- Multipass has the permissions it needs
- corporate endpoint security is not blocking VM creation

According to the official Multipass documentation, macOS uses the `qemu` driver by default. VirtualBox is optional if you intentionally choose it.

If launch fails while retrieving image metadata or downloading an image, refresh Multipass image metadata and try again:

```bash
multipass find --force-update
```

Then retry the test command.

### VM launches but networking fails

Symptoms:

- package installs fail
- chart downloads fail
- endpoint checks fail
- DNS inside the VM does not work

Check:

- VPN software
- corporate proxy
- macOS firewall or network filtering tools
- DNS configuration
- whether the VM can reach the internet:

```bash
multipass exec <vm-name> -- ping -c 3 1.1.1.1
multipass exec <vm-name> -- getent hosts github.com
```

### `multipass transfer` fails

Check:

- paths with spaces
- restrictive permissions
- shell quoting issues
- very long paths

Recommended repository path example:

```bash
~/src/productive-k3s
```

### Full profiles are slow

Expected.

The full profiles install:

- `k3s`
- `helm`
- `cert-manager`
- `Longhorn`
- `Rancher`
- internal registry
- NFS server

Run `smoke` and `core` first. Only run the full profiles when the cheaper checks pass.

### VM disk fills up

Increase disk size:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full --disk 60G
```

For repeated full-stack testing, use at least:

- CPU: `4`
- memory: `8G`
- disk: `40G`

More headroom is better for `full`, `full-rollback`, and `full-clean`.

### The test fails but the VM was deleted

Rerun with:

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile <profile> --keep-vm
```

Then inspect with:

```bash
multipass shell <vm-name>
```

## What Not To Do

Do not run the production bootstrap directly on macOS.

Do not try to install `k3s`, Longhorn, Rancher, or NFS directly on macOS through these scripts.

Do not assume macOS-hosted Multipass validation is complete until the same VM profile artifacts report `status: "success"`.

## Recommended Contributor Checklist

For a macOS contributor validating changes:

1. Install Multipass on macOS.
2. Clone the repository locally.
3. Confirm `multipass version` works.
4. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke`.
5. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core`.
6. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full` when needed.
7. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback` for rollback changes.
8. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean` for cleanup changes.
9. Confirm the relevant artifact JSON files report `status: "success"`.
10. Clean up with `./tests/test-in-vm-cleanup.sh --all --purge`.

## Documentation Status

This guide describes the intended macOS contributor workflow.

The repository remains Ubuntu-first in its examples and hosted CI. macOS should be considered a supported developer host only for driving supported Linux VM-based tests through Multipass, not as a native runtime target for the stack scripts.
