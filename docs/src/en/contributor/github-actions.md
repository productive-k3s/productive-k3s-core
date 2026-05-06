# GitHub Actions And Release Automation

This document defines the repository automation model for releases and hosted CI validation.

## Scope

There are two separate workflows:

1. release packaging and publication
2. GitHub-hosted validation

They must remain separate.

Do not mix release publication with validation in a single workflow.

## Why Hosted Validation Is Limited

The GitHub Actions CI path does not use Multipass.

The hosted CI goal is split in two layers:

- a containerized smoke matrix for supported base distributions
- a full hosted validation directly on `ubuntu-24.04`

This gives a much stronger CI signal than a dry-run, but it is still different from local Multipass validation because it does not exercise the VM harness itself.

It does not replace local Multipass-based testing for:

- real VM bootstrap
- rollback validation
- Debian VM validation

## Runner Model

Release workflow:

- GitHub-hosted Ubuntu runner

Hosted validation workflow:

- GitHub-hosted `ubuntu-24.04`

Reason:

- this avoids depending on nested virtualization in GitHub-hosted runners
- the workflow remains reproducible and low-maintenance
- the heavier Multipass path stays local, where the repository already has dedicated tooling

## Release Workflow

Trigger:

- push of a version tag such as `v1.2.3`

Guard:

- the tag commit must be reachable from `origin/main`

Outputs:

- `productive-k3s-<tag>.tar.gz`
- `productive-k3s-<tag>.tar.gz.sha256`
- `install-productive-k3s.sh`

The release workflow creates a GitHub Release and uploads those files as release assets.

The installer script is versioned per release and can be used like this:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/vX.Y.Z/install-productive-k3s.sh | bash
```

Additional bootstrap flags can still be passed:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/vX.Y.Z/install-productive-k3s.sh | bash -s -- --dry-run
```

## Hosted Validation Workflow

Trigger:

- pull request against `main`
- activity types:
  - `opened`
  - `reopened`
  - `ready_for_review`
  - `synchronize`
- optional manual dispatch

Notes:

- it reruns when new commits are pushed to the PR branch
- draft PRs are skipped until they are marked ready for review

The workflow should provide these jobs:

1. `smoke-matrix`

- run on `ubuntu-24.04`
- execute `tests/test-in-docker.sh` against these base images:
  - `ubuntu:24.04`
  - `ubuntu:22.04`
  - `debian:12`
  - `debian:13`
- upload one smoke log per matrix leg

2. `hosted-full-ubuntu-24.04`

- run on `ubuntu-24.04`
- run shell syntax checks
- run the full bootstrap directly on the runner host
- run `scripts/validate-k3s-stack.sh --strict`
- run `scripts/clean-k3s-stack.sh --apply`
- upload `test-artifacts/` and `runs/` as workflow artifacts
- fail if `test-artifacts/hosted-validation-summary.json` does not end with `status == "success"`

There is no containerized `core` workflow yet.

Reason:

- the repository has an honest dry-run container harness for `smoke`
- it does not yet have an equally honest container harness for a real `core` install
- forcing `core` into a GitHub Actions job container would produce a weaker and potentially misleading signal because `k3s`, service management, and host networking behavior are not modeled the same way there

## Local Heavy Validation

The following validations remain local responsibilities:

- `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full`
- `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-rollback`
- `./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile full-clean`
- `./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile ...`
- `make test-matrix-core`
- `make test-matrix-full`
- `make test-matrix-full-rollback`
- `make test-matrix-full-clean`

Those checks are still the source of truth for real installation and teardown behavior.
