# Productive K3S Core Modes

`apply.sh` exposes explicit execution modes through `--mode`.

## Supported modes

| Mode | Purpose |
| --- | --- |
| `single-node` | Legacy combined mode. Installs the core plus the default stack in one pass |
| `server` | Default mode. Bootstraps only the core server node components |
| `agent` | Joins a node as a K3S agent |
| `stack` | Installs or reuses an explicit stack on top of an existing cluster |

## Operational meaning

The script internally treats the modes as capability switches:

- `single-node`: runs base installation, stack installation, and host-local tasks
- `server`: runs base installation only
- `agent`: configures an agent node and requires a server URL plus cluster token
- `stack`: requires an existing cluster and Helm, then operates only on the selected stack components

## What changes by mode

### `single-node`

- can install `k3s` and Helm
- can install stack components like `cert-manager`, `Longhorn`, `Rancher`, and the in-cluster registry
- can manage local `/etc/hosts`
- can manage host-local NFS
- can install local Docker trust for the self-signed registry

### `server`

- can install or reuse `k3s` and Helm
- skips stack-only components
- skips host-local stack integrations such as add-on managed `/etc/hosts`, Docker registry trust, and NFS

### `agent`

- targets `k3s-agent` instead of the server service
- prompts for `Agent server URL` and `Agent cluster token` when an agent install is needed
- skips Helm and stack components

### `stack`

- requires an already running `k3s` server and an installed `helm`
- does not install base `k3s`
- focuses on stack-level components and cluster issuers
- is the expected public path for `./productive-k3s-core.sh stack install <name>`

## Why the mode split matters

The mode model is what makes `productive-k3s-infra` orchestration possible. It gives infrastructure automation a stable interface for:

- base node provisioning
- agent joins
- cluster stack installation after the cluster already exists

## Notes

!!! note
    `single-node` is retained as a legacy all-in-one path. The public contract now prefers `apply` for core-only installation and `stack install <name>` for explicit stack installation.

!!! note
    `server`, `agent`, and `stack` are especially valuable when the bootstrap sequence is orchestrated by another layer.
