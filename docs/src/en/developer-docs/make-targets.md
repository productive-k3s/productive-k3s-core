# Make Targets For Development

The repository exposes a small root `Makefile` plus a larger matrix `Makefile` under `tests/`.

The root `Makefile` delegates to two shell dispatchers:

- `./productive-k3s-core.sh` for operational commands that are also part of the release install contract
- `./scripts/productive-k3s-core-dev.sh` for docs, tests, and other development entry points

## Root targets

These are the day-to-day entry points most developers use from the repository root.

| Target | Purpose |
| --- | --- |
| `make preflight` | Run the host preflight checks with warning-level guidance |
| `make preflight-strict` | Run the host preflight checks and fail on warnings too |
| `make apply` | Run the interactive bootstrap flow in its default `single-node` mode |
| `make dry-run` | Run the bootstrap flow in planning mode without applying changes |
| `make backup` | Capture a host and cluster backup snapshot |
| `make validate` | Run the stack validator |
| `make validate-strict` | Treat warnings as failures in validation |
| `make docs-build` | Build the MkDocs site strictly |
| `make docs-serve` | Serve the docs locally |
| `make docs-up` | Start the docs server in the background |
| `make docs-down` | Stop the local docs server and clean its artifacts |
| `make docs-clean` | Clean docs artifacts and local docs virtualenv |
| `make test-clean` | Remove local test result artifacts and other local test state |
| `make test-checkstatus` | Summarize the current recorded test outcomes from local artifacts |

## Focused test targets

The root `Makefile` also exposes a set of developer-friendly test entry points:

| Target | Purpose |
| --- | --- |
| `make test-preflight-host` | Verify the host preflight CLI, JSON output, and strict-mode behavior |
| `make test-bootstrap-modes` | Verify that bootstrap mode CLI help and validation behave correctly |
| `make test-productive-k3s-core-cli` | Verify the public CLI contract and the root `Makefile` routing |
| `make test-agent-smoke` | Exercise the `agent` mode in Docker |
| `make test-smoke` | Run a Docker-based smoke check for bootstrap dry-run |
| `make test-core` | Run the `core` VM profile on Ubuntu `24.04` |
| `make test-core-debian12` | Run the `core` VM profile on Debian `12` |
| `make test-core-debian13` | Run the `core` VM profile on Debian `13` |

## Matrix targets

For broader coverage, the root `Makefile` delegates to `tests/Makefile`:

| Target | Purpose |
| --- | --- |
| `make test-matrix-smoke` | Run the `smoke` matrix across Ubuntu and Debian |
| `make test-matrix-core` | Run the `core` matrix across Ubuntu and Debian |
| `make test-matrix-full` | Run the `full` matrix across Ubuntu and Debian |
| `make test-matrix-full-rollback` | Run the `full-rollback` matrix across Ubuntu and Debian |
| `make test-matrix-full-clean` | Run the `full-clean` matrix across Ubuntu and Debian |
| `make test-matrix-all` | Run all matrix profiles in sequence |

## Useful direct `tests/Makefile` targets

When you need narrower iteration loops, use `make -C tests ...`.

Examples:

- `make -C tests smoke-ubuntu-24.04`
- `make -C tests core-debian12`
- `make -C tests full-rollback-ubuntu-22.04`
- `make -C tests clean-test-state`
- `make -C tests check-test-status`

## Notes

!!! note
    The root targets are convenience entry points. The deeper matrix granularity lives in `tests/Makefile`.

!!! note
    For documentation work, `make docs-build` is the safest final check because it runs MkDocs in strict mode.
