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

- `Publish RKE2 Platform Contract`
  `Document explicitly that RKE2 support is currently limited to Ubuntu 24.04 and 22.04, and that Debian remains unsupported until validated.`

- `Validate Debian Expansion Strategy`
  `Assess what would be required to support RKE2 on Debian without reopening the stack refactor; keep the work scoped to engine/runtime layers.`

## Stack and Addon Productization

- `Document Stack Artifact Contract`
  `Publish the final contract for stack source vs stack artifact behavior, including bundled addons, compatibility fields, and runtime expectations.`

- `Add Stack URL Install Path`
  `Consider a first-class stack install flow from URL so Core can consume published stack artifacts without requiring a manual download step.`

- `Tighten Compatibility Enforcement`
  `Turn stack compatibility metadata into explicit warnings or hard failures for unsupported distro and Kubernetes version combinations.`

## CLI and UX

- `Review Public CLI Readiness`
  `Do one pass focused on help text, command naming, examples, and error messages to ensure the Core CLI is consistent as a public operator entrypoint.`

## Testing and Quality

- `Expand Runtime Regression Coverage`
  `Add focused automated coverage for manifest runtime metadata, cleanup and rollback parity, and runtime-aware addon execution paths.`

- `Expand Negative Stack Cases`
  `Add external and CLI-focused failure cases for invalid stack metadata, unsupported compatibility declarations, and missing bundled inputs.`

- `Review Long-Running VM Test Costs`
  `Track which stack and matrix tests are expensive, and decide what stays in fast maintainer flows versus deeper validation passes.`

## Release and Docs

- `Close Release Checklist`
  `Add a maintainer checklist for source change, artifact generation, publish, catalog update, and isolated checkout validation of stack artifacts.`

- `Centralize GitHub Owner and Release URL Base`
  `Replace hardcoded jemacchi repo URLs with a repo-local base/owner setting in docs/src/index.md, docs/src/en/product/how-to-use.md, docs/src/es/product/how-to-use.md, and docs/mkdocs.yml.`

- `Update User-Facing Documentation`
  `Refresh product, user, and developer docs so published examples reflect explicit stack installation, artifact testing, and current support boundaries.`
