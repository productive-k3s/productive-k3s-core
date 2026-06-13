# TODO

Simple, versioned backlog for `productive-k3s-core` only.

Format:
- `Title`: short action-oriented label
- `Description`: one sentence, max 250 chars, easy to scan in reviews

Rules:
- Keep only repo-local responsibilities here.
- Do not track work owned by other repositories.
- Cross-repo dependencies can be mentioned only as context, never as the main ownership of an item.

## Runtime and Platform

- `Commit Stack Matrix Targets`
  `Commit the new stack matrix targets, Ubuntu-only RKE2 guards, and Ubuntu 22.04 RKE2 coverage once the isolated checkout validation passes cleanly.`

- `Publish RKE2 Platform Contract`
  `Document explicitly that RKE2 support is currently limited to Ubuntu 24.04 and 22.04, and that Debian remains unsupported until validated.`

- `Validate Debian Expansion Strategy`
  `Assess what would be required to support RKE2 on Debian without reopening the stack refactor; keep the work scoped to engine/runtime layers.`

## Stack and Addon Productization

- `Document Stack Artifact Contract`
  `Publish the final contract for stack source vs stack artifact behavior, including bundled addons, compatibility fields, and runtime expectations.`

- `Add Stack URL Install Path`
  `Consider a first-class stack install flow from URL so Core can consume published stack artifacts without requiring a manual download step.`

- `Validate Kubernetes Version Compatibility`
  `Enforce or warn on stack-declared Kubernetes minimum versions so compatibility metadata does more than document intent.`

## CLI and UX

- `Review Public CLI Readiness`
  `Do one pass focused on help text, command naming, examples, and error messages to ensure the Core CLI is consistent as a public operator entrypoint.`

- `Simplify Root Makefile`
  `Move transversal make targets into domain folders like docs, tests, or tools, and keep the root Makefile focused on app commands and operational entrypoints.`

## Testing and Quality

- `Increase ShellSpec Coverage`
  `Raise automated coverage around stack install, packaged addon execution, compatibility guards, and external test harness behavior.`

- `Add Failure-Focused External Cases`
  `Add focused tests for bad stack metadata, unsupported distro selections, missing bundled artifacts, and broken packaged addon runtime assumptions.`

- `Review Long-Running VM Test Costs`
  `Track which stack and matrix tests are expensive, and decide what stays in fast maintainer flows versus deeper validation passes.`

## Release and Docs

- `Close Release Checklist`
  `Add a maintainer checklist for source change, artifact generation, publish, catalog update, and isolated checkout validation of stack artifacts.`

- `Update User-Facing Documentation`
  `Refresh product, user, and developer docs so published examples reflect explicit stack installation, artifact testing, and current support boundaries.`

- `Track Ecosystem TODO Files`
  `Adopt the same TODO.md pattern across related repositories so pending work remains local, versioned, and easy to review without external trackers.`
