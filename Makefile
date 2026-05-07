.PHONY: preflight preflight-strict bootstrap dry-run backup validate validate-strict docs-build docs-serve docs-up docs-down docs-clean test-preflight-host test-bootstrap-modes test-productive-k3s-cli test-agent-smoke test-smoke test-core test-core-debian12 test-core-debian13 test-matrix-smoke test-matrix-core test-matrix-full test-matrix-full-rollback test-matrix-full-clean test-matrix-all

preflight:
	./scripts/productive-k3s.sh preflight

preflight-strict:
	./scripts/productive-k3s.sh preflight --strict

bootstrap:
	./scripts/productive-k3s.sh bootstrap

dry-run:
	./scripts/productive-k3s.sh bootstrap --dry-run

backup:
	./scripts/productive-k3s.sh backup

validate:
	./scripts/productive-k3s.sh validate

validate-strict:
	./scripts/productive-k3s.sh validate --strict

docs-build:
	./scripts/productive-k3s-dev.sh docs-build

docs-serve:
	./scripts/productive-k3s-dev.sh docs-serve

docs-up:
	./scripts/productive-k3s-dev.sh docs-up

docs-down:
	./scripts/productive-k3s-dev.sh docs-down

docs-clean:
	./scripts/productive-k3s-dev.sh docs-clean

test-preflight-host:
	./scripts/productive-k3s-dev.sh test-preflight-host

test-bootstrap-modes:
	./scripts/productive-k3s-dev.sh test-bootstrap-modes

test-productive-k3s-cli:
	./scripts/productive-k3s-dev.sh test-productive-k3s-cli

test-agent-smoke:
	./scripts/productive-k3s-dev.sh test-agent-smoke

test-smoke:
	./scripts/productive-k3s-dev.sh test-smoke

test-core:
	./scripts/productive-k3s-dev.sh test-core

test-core-debian12:
	./scripts/productive-k3s-dev.sh test-core-debian12

test-core-debian13:
	./scripts/productive-k3s-dev.sh test-core-debian13

test-matrix-smoke:
	./scripts/productive-k3s-dev.sh test-matrix-smoke

test-matrix-core:
	./scripts/productive-k3s-dev.sh test-matrix-core

test-matrix-full:
	./scripts/productive-k3s-dev.sh test-matrix-full

test-matrix-full-rollback:
	./scripts/productive-k3s-dev.sh test-matrix-full-rollback

test-matrix-full-clean:
	./scripts/productive-k3s-dev.sh test-matrix-full-clean

test-matrix-all:
	./scripts/productive-k3s-dev.sh test-matrix-all
