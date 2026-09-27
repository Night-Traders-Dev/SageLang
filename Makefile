# ═══════════════════════════════════════════════════════════════════════════════
# SageLang — root Makefile
# All targets delegate to core/. Build output: core/sage
# To build: make  |  To test: make test  |  To install: sudo make install
# Builds in parallel, one job per core; `make JOBS=1` for a serial build.
# ═══════════════════════════════════════════════════════════════════════════════

CORE := core
# One job per core unless the caller says otherwise. core/Makefile applies
# the same default on its own; this keeps the root's delegation explicit.
NPROC := $(shell nproc 2>/dev/null || echo 1)
JOBS ?= $(NPROC)

# Pass through every goal to core/Makefile
.DEFAULT_GOAL := all
.PHONY: all

all:
	@$(MAKE) -C $(CORE) -j$(JOBS)

test-all:
	@$(MAKE) -C $(CORE) test-all

benchmarks:
	@$(MAKE) -C $(CORE) benchmarks

# Forward any target that isn't "all"
%:
	@$(MAKE) -C $(CORE) $@
