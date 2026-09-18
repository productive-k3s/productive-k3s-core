.PHONY: preflight preflight-strict apply dry-run backup validate validate-strict docs-build docs-serve docs-up docs-down docs-clean test-local-all test-external-all test-matrix-all tag-release

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
	$(MAKE) -C ./docs docs-build

docs-serve:
	$(MAKE) -C ./docs docs-serve

docs-up:
	$(MAKE) -C ./docs docs-up

docs-down:
	$(MAKE) -C ./docs docs-down

docs-clean:
	$(MAKE) -C ./docs docs-clean

test-local-all:
	$(MAKE) -C ./tests test-local-all

test-external-all:
	$(MAKE) -C ./tests test-external-all

test-matrix-all:
	$(MAKE) -C ./tests test-matrix-all

tag-release:
	./scripts/create-release-tag.sh $(VERSION)
