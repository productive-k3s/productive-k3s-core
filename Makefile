.PHONY: preflight preflight-strict bootstrap dry-run backup validate validate-strict docs-build docs-serve docs-up docs-down docs-clean test-clean test-checkstatus test-preflight-host test-bootstrap-modes test-artifact-tools test-productive-k3s-core-cli test-agent-smoke test-smoke test-core test-core-debian12 test-core-debian13 test-matrix-smoke test-matrix-core test-matrix-full test-matrix-full-rollback test-matrix-full-clean test-matrix-all

preflight:
	./productive-k3s-core.sh preflight

preflight-strict:
	./productive-k3s-core.sh preflight --strict

bootstrap:
	./productive-k3s-core.sh bootstrap

dry-run:
	./productive-k3s-core.sh bootstrap --dry-run

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

test-clean:
	./scripts/productive-k3s-core-dev.sh test-clean

test-checkstatus:
	./scripts/productive-k3s-core-dev.sh test-checkstatus

test-preflight-host:
	./scripts/productive-k3s-core-dev.sh test-preflight-host

test-bootstrap-modes:
	./scripts/productive-k3s-core-dev.sh test-bootstrap-modes

test-artifact-tools:
	./scripts/productive-k3s-core-dev.sh test-artifact-tools

test-productive-k3s-core-cli:
	./scripts/productive-k3s-core-dev.sh test-productive-k3s-core-cli

test-agent-smoke:
	./scripts/productive-k3s-core-dev.sh test-agent-smoke

test-smoke:
	./scripts/productive-k3s-core-dev.sh test-smoke

test-core:
	./scripts/productive-k3s-core-dev.sh test-core

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
