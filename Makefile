.PHONY: bootstrap dry-run backup validate validate-strict docs-build docs-serve docs-up docs-down docs-clean test-bootstrap-modes test-agent-smoke test-smoke test-core test-core-debian12 test-core-debian13 test-matrix-smoke test-matrix-core test-matrix-full test-matrix-full-rollback test-matrix-full-clean test-matrix-all

bootstrap:
	./scripts/bootstrap-k3s-stack.sh

dry-run:
	./scripts/bootstrap-k3s-stack.sh --dry-run

backup:
	./scripts/backup-k3s-stack.sh

validate:
	./scripts/validate-k3s-stack.sh

validate-strict:
	./scripts/validate-k3s-stack.sh --strict

docs-build:
	./docs/build.sh

docs-serve:
	./docs/serve.sh

docs-up:
	./docs/serve.sh --background

docs-down:
	./docs/clean.sh

docs-clean:
	./docs/clean.sh

test-bootstrap-modes:
	bash ./tests/test-bootstrap-modes.sh

test-agent-smoke:
	bash ./tests/test-agent-in-docker.sh

test-smoke:
	./tests/test-in-docker.sh

test-core:
	./tests/test-in-vm.sh --platform ubuntu --image 24.04 --profile core

test-core-debian12:
	./tests/test-in-vm.sh --platform debian12 --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2 --profile core

test-core-debian13:
	./tests/test-in-vm.sh --platform debian13 --image https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 --profile core

test-matrix-smoke:
	$(MAKE) -C tests run-smoke-tests

test-matrix-core:
	$(MAKE) -C tests run-core-tests

test-matrix-full:
	$(MAKE) -C tests run-full-tests

test-matrix-full-rollback:
	$(MAKE) -C tests run-full-rollback-tests

test-matrix-full-clean:
	$(MAKE) -C tests run-full-clean-tests

test-matrix-all:
	$(MAKE) -C tests run-all-tests
