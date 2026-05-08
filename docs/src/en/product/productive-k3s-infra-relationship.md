# Relationship With `productive-k3s-infra`

`productive-k3s-core` is the bootstrap layer. `productive-k3s-infra` is the infrastructure companion layer built around it.

## What `productive-k3s-core` provides

This repository provides the bootstrap contract for:

- installing `k3s`
- assembling a cluster role or topology step
- installing the shared platform stack
- validating the resulting environment

That contract is exposed through explicit modes:

- `single-node`
- `server`
- `agent`
- `stack`

## What `productive-k3s-infra` adds

`productive-k3s-infra` uses those modes to build more complete infrastructure flows around the cluster.

It adds concerns such as:

- provisioning machines when needed
- deriving inventories and host metadata
- orchestrating bootstrap across multiple nodes
- sequencing remote `server`, `agent`, and `stack` execution
- validating infrastructure-specific outcomes

## Why this matters for a real cluster

On its own, `productive-k3s-core` is already enough to bootstrap a real K3S environment.

The infrastructure repository extends that into paths that are closer to a real cluster lifecycle, for example:

- a local three-node cluster on Multipass
- an on-premises SSH flow with one server and one or more agents
- a basic AWS single-node path

The key enabler is the mode split:

1. `server` bootstraps the control-plane node
2. `agent` joins additional nodes
3. `stack` installs cluster-level components only after the cluster exists

That is what lets another repository assemble a real multi-node cluster without re-implementing the cluster bootstrap itself.

## Practical interpretation

If you only need a direct bootstrap path on one machine, `productive-k3s-core` is the primary project.

If you also need:

- machine provisioning
- remote orchestration
- multi-node assembly
- use-case-specific infrastructure workflows

then `productive-k3s-infra` is the next layer above it.

## See also

- [Product overview](index.md)
- [Reasons behind the stack](reasons-behind.md)
- [How to use Productive K3S Core](how-to-use.md)
