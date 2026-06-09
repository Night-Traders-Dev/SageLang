# ═══════════════════════════════════════════════════════════════════════════════
# SageLang — root Makefile
# All targets delegate to core/. Build output: core/sage
# To build: make  |  To test: make test  |  To install: sudo make install
# ═══════════════════════════════════════════════════════════════════════════════

CORE := core

# Pass through every goal to core/Makefile
.DEFAULT_GOAL := all
.PHONY: all

all:
	@$(MAKE) -C $(CORE)

# Forward any target that isn't "all"
%:
	@$(MAKE) -C $(CORE) $@
