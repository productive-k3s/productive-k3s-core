.PHONY: preflight preflight-strict apply dry-run backup validate validate-strict docs-build docs-serve docs-up docs-down docs-clean test test-unit test-lint test-format test-spell test-coverage test-clean test-clean-artifacts test-clean-vms test-clean-all test-checkstatus test-checkstatus-matrix test-checkstatus-local test-checkstatus-external test-local-all test-external-all test-stacks test-preflight-host test-arm-support-docs test-bootstrap-modes test-artifact-tools test-telemetry test-productive-k3s-core-cli test-in-vm-engine-propagation test-agent-smoke test-smoke test-core test-rke2-core test-rke2-full test-rke2-full-clean test-rke2-full-rollback test-rke2-ubuntu-all test-core-debian12 test-core-debian13 test-matrix-smoke test-matrix-core test-matrix-full test-matrix-full-rollback test-matrix-full-clean test-matrix-all tag-release

preflight:
	./productive-k3s-core.sh preflight

preflight-strict:
	./productive-k3s-core.sh preflight --strict

apply:
	./productive-k3s-core.sh apply

dry-run:
	./productive-k3s-core.sh apply --dry-run

backup:
	./productive-k3s-core.sh backup

validate:
	./productive-k3s-core.sh validate

validate-strict:
	./productive-k3s-core.sh validate --strict

docs-build:
	./scripts/productive-k3s-core-dev.sh docs-build

docs-serve:
	./scripts/productive-k3s-core-dev.sh docs-serve

docs-up:
	./scripts/productive-k3s-core-dev.sh docs-up

docs-down:
	./scripts/productive-k3s-core-dev.sh docs-down

docs-clean:
	./scripts/productive-k3s-core-dev.sh docs-clean

test: test-unit test-lint test-format test-spell

test-unit:
	bash ./tests/bin/run-shellspec.sh

test-lint:
	bash ./tests/bin/run-shellcheck.sh

test-format:
	bash ./tests/bin/run-shfmt.sh

test-spell:
	bash ./tests/bin/run-spellcheck.sh

test-coverage:
	bash ./tests/bin/run-kcov.sh

test-clean:
	./scripts/productive-k3s-core-dev.sh test-clean

test-clean-artifacts:
	./scripts/productive-k3s-core-dev.sh test-clean-artifacts

test-clean-vms:
	./scripts/productive-k3s-core-dev.sh test-clean-vms

test-clean-all:
	./scripts/productive-k3s-core-dev.sh test-clean-all

test-checkstatus:
	./scripts/productive-k3s-core-dev.sh test-checkstatus

test-checkstatus-matrix:
	./scripts/productive-k3s-core-dev.sh test-checkstatus-matrix

test-checkstatus-local:
	./scripts/productive-k3s-core-dev.sh test-checkstatus-local

test-checkstatus-external:
	./scripts/productive-k3s-core-dev.sh test-checkstatus-external

test-local-all:
	./scripts/productive-k3s-core-dev.sh test-local-all

test-external-all:
	./scripts/productive-k3s-core-dev.sh test-external-all

test-stacks:
	./scripts/productive-k3s-core-dev.sh test-stacks

test-preflight-host:
	./scripts/productive-k3s-core-dev.sh test-preflight-host

test-arm-support-docs:
	./scripts/productive-k3s-core-dev.sh test-arm-support-docs

test-bootstrap-modes:
	./scripts/productive-k3s-core-dev.sh test-bootstrap-modes

test-artifact-tools:
	./scripts/productive-k3s-core-dev.sh test-artifact-tools

test-telemetry:
	./scripts/productive-k3s-core-dev.sh test-telemetry

test-productive-k3s-core-cli:
	./scripts/productive-k3s-core-dev.sh test-productive-k3s-core-cli

test-in-vm-engine-propagation:
	./scripts/productive-k3s-core-dev.sh test-in-vm-engine-propagation

test-agent-smoke:
	./scripts/productive-k3s-core-dev.sh test-agent-smoke

test-smoke:
	./scripts/productive-k3s-core-dev.sh test-smoke

test-core:
	./scripts/productive-k3s-core-dev.sh test-core

test-rke2-core:
	./scripts/productive-k3s-core-dev.sh test-rke2-core

test-rke2-full:
	./scripts/productive-k3s-core-dev.sh test-rke2-full

test-rke2-full-clean:
	./scripts/productive-k3s-core-dev.sh test-rke2-full-clean

test-rke2-full-rollback:
	./scripts/productive-k3s-core-dev.sh test-rke2-full-rollback

test-rke2-ubuntu-all:
	./scripts/productive-k3s-core-dev.sh test-rke2-ubuntu-all

test-core-debian12:
	./scripts/productive-k3s-core-dev.sh test-core-debian12

test-core-debian13:
	./scripts/productive-k3s-core-dev.sh test-core-debian13

test-matrix-smoke:
	./scripts/productive-k3s-core-dev.sh test-matrix-smoke

test-matrix-core:
	./scripts/productive-k3s-core-dev.sh test-matrix-core

test-matrix-full:
	./scripts/productive-k3s-core-dev.sh test-matrix-full

test-matrix-full-rollback:
	./scripts/productive-k3s-core-dev.sh test-matrix-full-rollback

test-matrix-full-clean:
	./scripts/productive-k3s-core-dev.sh test-matrix-full-clean

test-matrix-all:
	./scripts/productive-k3s-core-dev.sh test-matrix-all

tag-release:
	./scripts/create-release-tag.sh $(VERSION)
