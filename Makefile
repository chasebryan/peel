SHELL := /bin/bash
.DEFAULT_GOAL := help

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: help doctor policy verify negative extract smoke evidence check clean

help:
	@printf '%s\n' \
	  'PEEL Phase P0 targets:' \
	  '  make help      List every target and its contract.' \
	  '  make doctor    Validate the exact locked F*, KaRaMeL, Z3, and OCaml toolchain.' \
	  '  make policy    Reject proof bypasses and failure-masking mechanisms.' \
	  '  make verify    Verify interfaces, implementations, the example, and positive tests.' \
	  '  make negative  Require both illegal secret observations to fail for the expected type reason.' \
	  '  make extract   Verify and extract the real Peel.Byte executable core through KaRaMeL.' \
	  '  make smoke     Strictly compile generated C and run the deterministic public XOR test.' \
	  '  make evidence  Emit the canonical P0 evidence record after gates P0.1--P0.8 pass.' \
	  '  make check     Run doctor, policy, verify, negative, extract, smoke, and evidence in order.' \
	  '  make clean     Remove only the repository-local build/ directory.'

doctor:
	@"$(REPO_ROOT)/scripts/doctor.sh"

policy:
	@"$(REPO_ROOT)/scripts/policy-check.sh"

verify:
	@"$(REPO_ROOT)/scripts/verify.sh"

negative:
	@"$(REPO_ROOT)/scripts/negative.sh"

extract:
	@"$(REPO_ROOT)/scripts/extract-c.sh"

smoke:
	@"$(REPO_ROOT)/scripts/smoke-c.sh"

evidence:
	@python3 "$(REPO_ROOT)/scripts/evidence.py"

check:
	@$(MAKE) --no-print-directory doctor
	@$(MAKE) --no-print-directory policy
	@$(MAKE) --no-print-directory verify
	@$(MAKE) --no-print-directory negative
	@$(MAKE) --no-print-directory extract
	@$(MAKE) --no-print-directory smoke
	@$(MAKE) --no-print-directory evidence

clean:
	@repo_root="$(REPO_ROOT)"; \
	build_path="$(REPO_ROOT)/build"; \
	case "$${build_path}" in \
	  "$${repo_root}/build") ;; \
	  *) printf '%s\n' 'Refusing to clean an invalid build path.' >&2; exit 1 ;; \
	esac; \
	if [[ -e "$${build_path}" ]]; then rm -rf -- "$${build_path}"; fi
