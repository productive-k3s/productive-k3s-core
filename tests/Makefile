SHELL := /bin/bash

VM_TEST := ./test-in-vm.sh
ARTIFACT_CHECK := ./check-test-artifacts.sh
PUBLIC_ARTIFACT_PRIVACY_CHECK := ./check-public-test-artifacts.sh
DEBIAN12_IMAGE := https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
DEBIAN13_IMAGE := https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2

.PHONY: \
	clean-test-state \
	clean-test-artifacts \
	clean-smoke-artifacts \
	clean-core-artifacts \
	clean-full-artifacts \
	clean-full-rollback-artifacts \
	clean-full-clean-artifacts \
	check-test-status \
	verify-smoke-artifacts \
	verify-core-artifacts \
	verify-full-artifacts \
	verify-full-rollback-artifacts \
	verify-full-clean-artifacts \
	run-smoke-tests \
	run-core-tests \
	run-full-tests \
	run-full-rollback-tests \
	run-full-clean-tests \
	run-all-tests \
	smoke-ubuntu-24.04 smoke-ubuntu-22.04 smoke-debian12 smoke-debian13 \
	core-ubuntu-24.04 core-ubuntu-22.04 core-debian12 core-debian13 \
	full-ubuntu-24.04 full-ubuntu-22.04 full-debian12 full-debian13 \
	full-rollback-ubuntu-24.04 full-rollback-ubuntu-22.04 full-rollback-debian12 full-rollback-debian13 \
	full-clean-ubuntu-24.04 full-clean-ubuntu-22.04 full-clean-debian12 full-clean-debian13

clean-test-state:
	bash ./clean-test-state.sh

clean-test-artifacts:
	bash ./clean-test-state.sh

clean-smoke-artifacts:
	bash ./clean-profile-artifacts.sh smoke

clean-core-artifacts:
	bash ./clean-profile-artifacts.sh core

clean-full-artifacts:
	bash ./clean-profile-artifacts.sh full

clean-full-rollback-artifacts:
	bash ./clean-profile-artifacts.sh full-rollback

clean-full-clean-artifacts:
	bash ./clean-profile-artifacts.sh full-clean

check-test-status:
	bash ./check-test-status.sh

verify-smoke-artifacts:
	$(ARTIFACT_CHECK) --profile smoke \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'
	$(PUBLIC_ARTIFACT_PRIVACY_CHECK) --profile smoke \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'

verify-core-artifacts:
	$(ARTIFACT_CHECK) --profile core \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'
	$(PUBLIC_ARTIFACT_PRIVACY_CHECK) --profile core \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'

verify-full-artifacts:
	$(ARTIFACT_CHECK) --profile full \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'
	$(PUBLIC_ARTIFACT_PRIVACY_CHECK) --profile full \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'

verify-full-rollback-artifacts:
	$(ARTIFACT_CHECK) --profile full-rollback \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'
	$(PUBLIC_ARTIFACT_PRIVACY_CHECK) --profile full-rollback \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'

verify-full-clean-artifacts:
	$(ARTIFACT_CHECK) --profile full-clean \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'
	$(PUBLIC_ARTIFACT_PRIVACY_CHECK) --profile full-clean \
		--expect 'ubuntu|24.04' \
		--expect 'ubuntu|22.04' \
		--expect 'debian12|$(DEBIAN12_IMAGE)' \
		--expect 'debian13|$(DEBIAN13_IMAGE)'

run-smoke-tests: clean-test-state clean-smoke-artifacts smoke-ubuntu-24.04 smoke-ubuntu-22.04 smoke-debian12 smoke-debian13 verify-smoke-artifacts

run-core-tests: clean-test-state clean-core-artifacts core-ubuntu-24.04 core-ubuntu-22.04 core-debian12 core-debian13 verify-core-artifacts

run-full-tests: clean-test-state clean-full-artifacts full-ubuntu-24.04 full-ubuntu-22.04 full-debian12 full-debian13 verify-full-artifacts

run-full-rollback-tests: clean-test-state clean-full-rollback-artifacts full-rollback-ubuntu-24.04 full-rollback-ubuntu-22.04 full-rollback-debian12 full-rollback-debian13 verify-full-rollback-artifacts

run-full-clean-tests: clean-test-state clean-full-clean-artifacts full-clean-ubuntu-24.04 full-clean-ubuntu-22.04 full-clean-debian12 full-clean-debian13 verify-full-clean-artifacts

run-all-tests: clean-test-state \
	clean-smoke-artifacts \
	smoke-ubuntu-24.04 smoke-ubuntu-22.04 smoke-debian12 smoke-debian13 verify-smoke-artifacts \
	clean-core-artifacts \
	core-ubuntu-24.04 core-ubuntu-22.04 core-debian12 core-debian13 verify-core-artifacts \
	clean-full-artifacts \
	full-ubuntu-24.04 full-ubuntu-22.04 full-debian12 full-debian13 verify-full-artifacts \
	clean-full-rollback-artifacts \
	full-rollback-ubuntu-24.04 full-rollback-ubuntu-22.04 full-rollback-debian12 full-rollback-debian13 verify-full-rollback-artifacts \
	clean-full-clean-artifacts \
	full-clean-ubuntu-24.04 full-clean-ubuntu-22.04 full-clean-debian12 full-clean-debian13 verify-full-clean-artifacts

smoke-ubuntu-24.04:
	$(VM_TEST) --platform ubuntu --image 24.04 --profile smoke --purge-on-cleanup

smoke-ubuntu-22.04:
	$(VM_TEST) --platform ubuntu --image 22.04 --profile smoke --purge-on-cleanup

smoke-debian12:
	$(VM_TEST) --platform debian12 --image $(DEBIAN12_IMAGE) --profile smoke --purge-on-cleanup

smoke-debian13:
	$(VM_TEST) --platform debian13 --image $(DEBIAN13_IMAGE) --profile smoke --purge-on-cleanup

core-ubuntu-24.04:
	$(VM_TEST) --platform ubuntu --image 24.04 --profile core --purge-on-cleanup

core-ubuntu-22.04:
	$(VM_TEST) --platform ubuntu --image 22.04 --profile core --purge-on-cleanup

core-debian12:
	$(VM_TEST) --platform debian12 --image $(DEBIAN12_IMAGE) --profile core --purge-on-cleanup

core-debian13:
	$(VM_TEST) --platform debian13 --image $(DEBIAN13_IMAGE) --profile core --purge-on-cleanup

full-ubuntu-24.04:
	$(VM_TEST) --platform ubuntu --image 24.04 --profile full --purge-on-cleanup

full-ubuntu-22.04:
	$(VM_TEST) --platform ubuntu --image 22.04 --profile full --purge-on-cleanup

full-debian12:
	$(VM_TEST) --platform debian12 --image $(DEBIAN12_IMAGE) --profile full --purge-on-cleanup

full-debian13:
	$(VM_TEST) --platform debian13 --image $(DEBIAN13_IMAGE) --profile full --purge-on-cleanup

full-rollback-ubuntu-24.04:
	$(VM_TEST) --platform ubuntu --image 24.04 --profile full-rollback --purge-on-cleanup

full-rollback-ubuntu-22.04:
	$(VM_TEST) --platform ubuntu --image 22.04 --profile full-rollback --purge-on-cleanup

full-rollback-debian12:
	$(VM_TEST) --platform debian12 --image $(DEBIAN12_IMAGE) --profile full-rollback --purge-on-cleanup

full-rollback-debian13:
	$(VM_TEST) --platform debian13 --image $(DEBIAN13_IMAGE) --profile full-rollback --purge-on-cleanup

full-clean-ubuntu-24.04:
	$(VM_TEST) --platform ubuntu --image 24.04 --profile full-clean --purge-on-cleanup

full-clean-ubuntu-22.04:
	$(VM_TEST) --platform ubuntu --image 22.04 --profile full-clean --purge-on-cleanup

full-clean-debian12:
	$(VM_TEST) --platform debian12 --image $(DEBIAN12_IMAGE) --profile full-clean --purge-on-cleanup

full-clean-debian13:
	$(VM_TEST) --platform debian13 --image $(DEBIAN13_IMAGE) --profile full-clean --purge-on-cleanup
