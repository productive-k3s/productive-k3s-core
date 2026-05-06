# Windows Development Guide

This guide explains how a developer using Windows can work on this repository and run the VM-based validation flow.

The important model is:

- Windows is the developer workstation and Multipass host.
- The repository test harness launches a supported Linux VM through Multipass.
- The stack scripts run inside that Linux VM.
- The scripts are not intended to run directly on Windows.

## Support Statement

This repository has been developed and validated against Linux hosts and supported Linux Multipass VMs.

For Windows developers, the supported target model is:

- use Windows only as the host operating system
- use Multipass to launch supported Linux test VMs
- run repository scripts inside those Linux VMs through `tests/test-in-vm.sh`

Do not treat this as native Windows support.

Native Windows execution is out of scope because the scripts assume Linux host behavior such as:

- `bash`
- `sudo`
- `systemd`
- Linux networking
- Linux filesystems
- `/etc/hosts`
- `/etc/exports`
- `k3s`
- `containerd`

## Recommended Windows Setup

Recommended components:

- Windows 11 or a current Windows 10 build with virtualization enabled
- Multipass for Windows
- WSL 2 with Ubuntu, used as the shell environment for this repository
- Git inside WSL
- `make` inside WSL if you want to use `Makefile` targets

Optional but useful:

- Windows Terminal
- VS Code with the Remote - WSL extension

Official references:

- Multipass installation: https://documentation.ubuntu.com/multipass/en/latest/how-to-guides/install-multipass/
- Multipass drivers: https://documentation.ubuntu.com/multipass/latest/explanation/driver/
- WSL installation: https://learn.microsoft.com/windows/wsl/install

## Why WSL Is Recommended

The test harness is written in Bash and uses Linux-style paths.

Using WSL gives the closest developer experience to the Ubuntu/Linux workflow already used by this repository.

Recommended workflow:

1. Install Multipass on Windows.
2. Install WSL 2 with Ubuntu.
3. Clone this repository inside the WSL filesystem.
4. Run `tests/test-in-vm.sh` from WSL.
5. Let Multipass create and destroy Ubuntu VMs.

Avoid cloning the repository under `/mnt/c/...` unless you have a specific reason.

Prefer a WSL-native path, for example:

```bash
mkdir -p ~/src
cd ~/src
git clone <repo-url> productive-k3s
cd productive-k3s
```

This avoids common path, permission, performance, and line-ending issues.

## Baseline Validation Flow From Windows

Start with cheap checks before running the full stack.

### 1. Confirm Multipass is reachable

From WSL:

```bash
multipass version
multipass list
```

If `multipass` is not found from WSL, try:

```bash
multipass.exe version
multipass.exe list
```

If only `multipass.exe` works, add a shell alias in WSL:

```bash
alias multipass=multipass.exe
```

For a persistent alias, add it to `~/.bashrc`.

### 2. Run the smoke VM profile

```bash
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke
```

This is the first check to run from Windows. It validates that:

- WSL can execute the Bash test harness
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

From WSL, check whether Windows exposes the executable as `multipass.exe`:

```bash
multipass.exe version
```

If that works:

```bash
alias multipass=multipass.exe
```

If neither works:

- confirm Multipass is installed on Windows
- restart the WSL shell
- verify Windows PATH integration for WSL
- run `multipass version` from PowerShell to confirm the Windows installation

### Multipass cannot launch a VM

Check:

- virtualization is enabled in BIOS/UEFI
- Hyper-V or VirtualBox backend is available
- Multipass service is running
- corporate endpoint security is not blocking VM creation
- there is enough CPU, RAM, and disk available

On Windows, Multipass uses Hyper-V on Windows Pro and VirtualBox on Windows Home by default. See the official Multipass driver documentation for backend details.

If launch fails while retrieving image metadata or downloading an image, refresh Multipass image metadata and try again:

```bash
multipass find --force-update
```

This is especially useful after errors such as:

- `Cannot retrieve headers`
- `Operation canceled`
- image lookup/download failures during `multipass launch`

After forcing the update, retry the test command.

Example:

```bash
multipass find --force-update
./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core
```

### VM launches but networking fails

Symptoms:

- package installs fail
- chart downloads fail
- endpoint checks fail
- DNS inside the VM does not work

Check:

- VPN software
- corporate proxy
- Windows firewall
- DNS configuration
- whether the VM can reach the internet:

```bash
multipass exec <vm-name> -- ping -c 3 1.1.1.1
multipass exec <vm-name> -- getent hosts github.com
```

### `multipass transfer` fails

Prefer cloning the repository inside the WSL filesystem instead of `/mnt/c/...`.

Avoid:

- paths with spaces
- very long Windows paths
- repositories stored in OneDrive-synced folders
- mixed Windows/Linux line endings

Recommended:

```bash
~/src/productive-k3s
```

### Scripts fail with `bad interpreter` or strange syntax errors

Likely causes:

- CRLF line endings
- running from PowerShell instead of WSL Bash
- Git autocrlf changing shell scripts

Check from WSL:

```bash
file tests/test-in-vm.sh
bash -n tests/test-in-vm.sh
```

The scripts should use Unix line endings.

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

Do not run the production bootstrap directly on Windows.

Do not try to install `k3s`, Longhorn, Rancher, or NFS directly on Windows through these scripts.

Do not treat WSL itself as the target host for the full stack unless that is explicitly tested. WSL is recommended here as the shell used to drive Multipass, not as the Kubernetes host.

Do not assume Windows-hosted Multipass validation is complete until the same VM profile artifacts report `status: "success"`.

## Recommended Contributor Checklist

For a Windows contributor validating changes:

1. Install Multipass on Windows.
2. Install WSL 2 with Ubuntu.
3. Clone the repository inside the WSL filesystem.
4. Confirm `multipass version` works from WSL.
5. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile smoke`.
6. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core`.
7. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full` when needed.
8. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback` for rollback changes.
9. Run `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean` for cleanup changes.
10. Confirm the relevant artifact JSON files report `status: "success"`.
11. Clean up with `./tests/test-in-vm-cleanup.sh --all --purge`.

## Documentation Status

This guide describes the intended Windows contributor workflow.

The repository remains Ubuntu-first in its examples and hosted CI. Windows should be considered a supported developer host only for driving supported Linux VM-based tests through Multipass, not as a native runtime target for the stack scripts.
