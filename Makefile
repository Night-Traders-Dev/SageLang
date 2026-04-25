# SageLang Makefile
# For those who prefer Make over CMake
# Note: CMakeLists.txt is recommended for Pico builds

# ============================================================================
# Configuration
# ============================================================================

# Single-source version from VERSION file
SAGE_VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.0")

CC = gcc
PYTHON ?= python3
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic -O2 -D_POSIX_C_SOURCE=200809L -DSAGE_LIB_DIR='"/usr/local/share/sage/lib"' -DSAGE_VERSION_STR='"$(SAGE_VERSION)"'
# Platform-conditional linking: pthread only on desktop (not RP2040)
ifndef PICO_BUILD
LDFLAGS = -lm -lpthread -ldl
# Vulkan support: auto-detect or set VULKAN=1
VULKAN ?= auto
ifeq ($(VULKAN),auto)
    VULKAN_CHECK := $(shell pkg-config --exists vulkan 2>/dev/null && echo yes || echo no)
else ifeq ($(VULKAN),1)
    VULKAN_CHECK := yes
else
    VULKAN_CHECK := no
endif
ifeq ($(VULKAN_CHECK),yes)
    CFLAGS += -DSAGE_HAS_VULKAN
    LDFLAGS += -lvulkan
    $(info Vulkan support enabled)
    # GLFW detection for windowed mode
    GLFW_CHECK := $(shell pkg-config --exists glfw3 2>/dev/null && echo yes || echo no)
    ifeq ($(GLFW_CHECK),yes)
        CFLAGS += -DSAGE_HAS_GLFW $(shell pkg-config --cflags glfw3)
        LDFLAGS += $(shell pkg-config --libs glfw3)
        $(info GLFW windowed mode enabled)
    endif
else
    $(info Vulkan support disabled (stub mode))
endif
# OpenGL detection
OPENGL ?= auto
ifeq ($(OPENGL),auto)
    OPENGL_CHECK := $(shell pkg-config --exists gl 2>/dev/null && echo yes || echo no)
else ifeq ($(OPENGL),1)
    OPENGL_CHECK := yes
else
    OPENGL_CHECK := no
endif
ifeq ($(OPENGL_CHECK),yes)
    CFLAGS += -DSAGE_HAS_OPENGL $(shell pkg-config --cflags gl 2>/dev/null)
    LDFLAGS += $(shell pkg-config --libs gl 2>/dev/null || echo "-lGL")
    $(info OpenGL support enabled)
    # GLFW detection for OpenGL windowed mode (if not already detected for Vulkan)
    ifneq ($(GLFW_CHECK),yes)
        GLFW_CHECK := $(shell pkg-config --exists glfw3 2>/dev/null && echo yes || echo no)
        ifeq ($(GLFW_CHECK),yes)
            CFLAGS += -DSAGE_HAS_GLFW $(shell pkg-config --cflags glfw3)
            LDFLAGS += $(shell pkg-config --libs glfw3)
            $(info GLFW windowed mode enabled (for OpenGL))
        endif
    endif
else
    $(info OpenGL support disabled)
endif
else
LDFLAGS = -lm
endif

# Directories
SRC_DIR = src/c
VM_DIR = src/vm
INC_DIR = include
OBJ_DIR = obj
BIN_DIR = .
BOARD_DIR = boards
CHART_SCRIPT = scripts/generate_loc_charts.py

# Debug flags
DEBUG ?= 0
ifeq ($(DEBUG), 1)
    CFLAGS += -g -O0 -DDEBUG
    $(info Debug mode enabled)
endif

# ============================================================================
# Source Files
# ============================================================================

CORE_SOURCES = \
    $(SRC_DIR)/ast.c \
    $(SRC_DIR)/codegen.c \
    $(SRC_DIR)/compiler.c \
    $(SRC_DIR)/constfold.c \
    $(SRC_DIR)/dce.c \
    $(SRC_DIR)/diagnostic.c \
    $(SRC_DIR)/env.c \
    $(SRC_DIR)/formatter.c \
    $(SRC_DIR)/gc.c \
    $(SRC_DIR)/inline.c \
    $(SRC_DIR)/interpreter.c \
    $(SRC_DIR)/linter.c \
    $(SRC_DIR)/lexer.c \
    $(SRC_DIR)/module.c \
    $(SRC_DIR)/parser.c \
    $(SRC_DIR)/pass.c \
    $(SRC_DIR)/sage_thread.c \
    $(SRC_DIR)/stdlib.c \
    $(SRC_DIR)/typecheck.c \
    $(SRC_DIR)/safety.c \
    $(SRC_DIR)/value.c \
    $(SRC_DIR)/stubs.c \
    $(SRC_DIR)/aot.c \
    $(SRC_DIR)/kotlin_backend.c

VM_SOURCES = \
    $(VM_DIR)/bytecode.c \
    $(VM_DIR)/program.c \
    $(VM_DIR)/runtime.c \
    $(VM_DIR)/vm.c

MAIN_SOURCE = $(SRC_DIR)/main.c

# Optional heartbeat source
ifneq (,$(wildcard $(SRC_DIR)/heartbeat.c))
    CORE_SOURCES += $(SRC_DIR)/heartbeat.c
    $(info Including heartbeat.c)
endif

# Headers
HEADERS = \
    $(INC_DIR)/ast.h \
    $(INC_DIR)/codegen.h \
    $(INC_DIR)/compiler.h \
    $(INC_DIR)/diagnostic.h \
    $(INC_DIR)/env.h \
    $(INC_DIR)/formatter.h \
    $(INC_DIR)/gc.h \
    $(INC_DIR)/interpreter.h \
    $(INC_DIR)/lexer.h \
    $(INC_DIR)/linter.h \
    $(INC_DIR)/llvm_backend.h \
    $(INC_DIR)/lsp.h \
    $(INC_DIR)/module.h \
    $(INC_DIR)/pass.h \
    $(INC_DIR)/token.h \
    $(INC_DIR)/sage_thread.h \
    $(INC_DIR)/typecheck.h \
    $(INC_DIR)/safety.h \
    $(INC_DIR)/value.h \
    $(INC_DIR)/graphics.h \
    $(INC_DIR)/gpu_api.h \
    $(INC_DIR)/kotlin_backend.h

# Optional heartbeat header
ifneq (,$(wildcard $(INC_DIR)/heartbeat.h))
    HEADERS += $(INC_DIR)/heartbeat.h
endif

# Object files
CORE_OBJECTS = $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(CORE_SOURCES))
VM_OBJECTS = $(patsubst $(VM_DIR)/%.c,$(OBJ_DIR)/vm/%.o,$(VM_SOURCES))
MAIN_OBJECT = $(OBJ_DIR)/main.o
ALL_OBJECTS = $(CORE_OBJECTS) $(VM_OBJECTS) $(MAIN_OBJECT)

# LLVM runtime (compiled separately, linked with --compile-llvm output)
LLVM_RT_SOURCE = $(SRC_DIR)/llvm_runtime.c
LLVM_RT_OBJECT = $(OBJ_DIR)/llvm_runtime.o

# GPU API (compiled separately, linked with --compile-llvm output for GPU support)
GPU_API_SOURCE = $(SRC_DIR)/gpu_api.c
GPU_API_OBJECT = $(OBJ_DIR)/gpu_api.o

# Binaries
TARGET = sage
LSP_TARGET = sage-lsp
LSP_MAIN_SOURCE = $(SRC_DIR)/lsp_main.c
LSP_MAIN_OBJECT = $(OBJ_DIR)/lsp_main.o

# ============================================================================
# Build Rules
# ============================================================================

.PHONY: all clean run install uninstall help test examples charts pdf sage-boot sage-bench benchmark benchmark-chart

all: $(TARGET)

# Link executable
$(TARGET): $(ALL_OBJECTS)
	@mkdir -p $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
	@echo "✅ Built: $(TARGET)"
	@echo "   Run with: ./$(TARGET) examples/hello.sage"

# LSP server binary (standalone)
$(LSP_TARGET): $(LSP_MAIN_OBJECT) $(CORE_OBJECTS) $(VM_OBJECTS)
	@mkdir -p $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
	@echo "Built: $(LSP_TARGET)"

$(LSP_MAIN_OBJECT): $(LSP_MAIN_SOURCE) $(HEADERS)
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -I$(INC_DIR) -I$(VM_DIR) -c $< -o $@
	@echo "Compiled: $<"

# Compile source files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(HEADERS)
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -I$(INC_DIR) -I$(VM_DIR) -c $< -o $@
	@echo "Compiled: $<"

$(OBJ_DIR)/vm/%.o: $(VM_DIR)/%.c $(HEADERS)
	@mkdir -p $(OBJ_DIR)/vm
	$(CC) $(CFLAGS) -I$(INC_DIR) -I$(VM_DIR) -c $< -o $@
	@echo "Compiled: $<"

# ============================================================================
# Development Targets
# ============================================================================

# Run with hello world example
run: $(TARGET)
	@echo "Running hello.sage..."
	./$(TARGET) examples/hello.sage

# Run all examples
examples: $(TARGET)
	@echo "Running all examples..."
	@for file in examples/*.sage; do \
		echo ""; \
		echo "=== $$file ==="; \
		./$(TARGET) $$file || true; \
	done

# Run specific example
run-%: $(TARGET)
	@echo "Running examples/$*.sage..."
	./$(TARGET) examples/$*.sage

# Debug build
debug:
	$(MAKE) DEBUG=1

# Refresh repository metrics and benchmark charts for the README
charts: $(TARGET)
	@$(PYTHON) $(CHART_SCRIPT)
	@echo "Updated README metric and benchmark chart assets"

# Generate The Sage Programming Language PDF from the book markdown
BOOK_SRC = docs/sagelang-book.md
BOOK_PDF = docs/The_Sage_Programming_Language.pdf

pdf: $(BOOK_PDF)

$(BOOK_PDF): $(BOOK_SRC)
	@if command -v pandoc >/dev/null 2>&1 && command -v xelatex >/dev/null 2>&1; then \
		echo "Generating $(BOOK_PDF)..."; \
		pandoc $(BOOK_SRC) -o $(BOOK_PDF) --pdf-engine=xelatex 2>/dev/null; \
		echo "Generated $(BOOK_PDF)"; \
	else \
		echo "Skipping PDF generation (requires pandoc + xelatex)"; \
	fi

# Compile the Metal VM object (freestanding bytecode VM for bare-metal)
METAL_VM_SOURCE = src/c/metal_vm.c
METAL_VM_OBJECT = obj/metal_vm.o

$(METAL_VM_OBJECT): $(METAL_VM_SOURCE) include/metal_vm.h
	@mkdir -p obj
	$(CC) -std=c11 -ffreestanding -O2 -Wall -Wextra -Iinclude -c $(METAL_VM_SOURCE) -o $(METAL_VM_OBJECT)
	@echo "Compiled Metal VM (freestanding)"

metal-vm: $(METAL_VM_OBJECT)
	@echo "Metal VM object ready: $(METAL_VM_OBJECT)"

# Run a Sage program through the self-hosted interpreter.
SELFHOST_ENTRY = src/sage/sage.sage

sage-boot: $(TARGET)
	@if [ -z "$(FILE)" ]; then echo "Usage: make sage-boot FILE=path/to/file.sage"; exit 1; fi
	@./$(TARGET) $(SELFHOST_ENTRY) $(FILE)

# Benchmark self-hosted interpreter against native C interpreter
sage-bench: $(TARGET)
	@echo "=== Native C Interpreter ==="
	@time -p ./$(TARGET) benchmarks/backend_compare.sage 2>&1 | tail -1
	@echo ""
	@echo "=== Self-Hosted Sage Interpreter ==="
	@time -p ./$(TARGET) $(SELFHOST_ENTRY) benchmarks/backend_compare.sage 2>&1 | tail -1

# Run the cross-backend benchmark
benchmark: $(TARGET)
	@bash benchmarks/run_backend_compare.sh

benchmark-chart: $(TARGET)
	@$(PYTHON) scripts/generate_backend_chart.py

benchmark-python: $(TARGET)
	@echo "Running Sage vs Python 3 benchmarks..."
	@$(PYTHON) scripts/benchmark_vs_python.py --runs 5 --warmups 1

benchmark-python-md: $(TARGET)
	@$(PYTHON) scripts/benchmark_vs_python.py --runs 5 --warmups 1 --markdown

# ============================================================================
# Installation
# ============================================================================

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/share/sage
DOCDIR = $(PREFIX)/share/doc/sage

install: $(TARGET) $(LSP_TARGET)
	@echo "Installing SageLang to $(PREFIX)..."
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)
	install -m 755 $(LSP_TARGET) $(BINDIR)
	install -d $(LIBDIR)/lib
	install -d $(LIBDIR)/examples
	cp -r lib/*.sage $(LIBDIR)/lib/ 2>/dev/null || true
	cp -r lib/graphics $(LIBDIR)/lib/
	cp -r lib/os $(LIBDIR)/lib/
	cp -r lib/net $(LIBDIR)/lib/
	cp -r lib/crypto $(LIBDIR)/lib/
	cp -r lib/ml $(LIBDIR)/lib/
	cp -r lib/cuda $(LIBDIR)/lib/
	cp -r lib/std $(LIBDIR)/lib/
	cp -r lib/llm $(LIBDIR)/lib/
	cp -r lib/agent $(LIBDIR)/lib/
	cp -r lib/chat $(LIBDIR)/lib/
	cp -r examples/*.sage $(LIBDIR)/examples/
	install -d $(DOCDIR)
	install -m 644 README.md ROADMAP.md LICENSE $(DOCDIR)/
	@echo "✅ Installation complete"
	@echo "   Run with: sage <script.sage>"

uninstall:
	@echo "Uninstalling SageLang..."
	rm -f $(BINDIR)/$(TARGET) $(BINDIR)/$(LSP_TARGET)
	rm -rf $(LIBDIR)
	rm -rf $(DOCDIR)
	@echo "✅ Uninstallation complete"

# ============================================================================
# Testing
# ============================================================================

test: $(TARGET)
	@echo "Running basic tests..."
	@echo "Test 1: Lexer"
	@./$(TARGET) -c "let x = 42" && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 2: Expressions"
	@./$(TARGET) -c "print 2 + 2 * 3" && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 3: Functions"
	@./$(TARGET) testing/test.sage && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 4: Bundled Libraries"
	@./$(TARGET) testing/lib_suite.sage && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 5: Phase 10 C Backend"
	@mkdir -p .tmp
	@./$(TARGET) --emit-c testing/compiler_smoke.sage -o .tmp/compiler_smoke.c
	@./$(TARGET) --compile testing/compiler_smoke.sage -o .tmp/compiler_smoke
	@./.tmp/compiler_smoke > .tmp/compiler_smoke.out
	@diff -u testing/compiler_smoke.expected .tmp/compiler_smoke.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 6: Phase 10 Arrays"
	@./$(TARGET) --emit-c testing/compiler_arrays.sage -o .tmp/compiler_arrays.c
	@./$(TARGET) --compile testing/compiler_arrays.sage -o .tmp/compiler_arrays
	@./.tmp/compiler_arrays > .tmp/compiler_arrays.out
	@diff -u testing/compiler_arrays.expected .tmp/compiler_arrays.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 7: Phase 10 Pico Codegen"
	@./$(TARGET) --emit-pico-c examples/hello.sage -o .tmp/hello_pico.c && \
		grep -F -q '#include "pico/stdlib.h"' .tmp/hello_pico.c && \
		grep -F -q 'stdio_init_all();' .tmp/hello_pico.c && \
		grep -F -q 'sleep_ms(2000);' .tmp/hello_pico.c && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 8: Phase 10 For Loops"
	@./$(TARGET) --compile testing/compiler_for_loops.sage -o .tmp/compiler_for_loops
	@./.tmp/compiler_for_loops > .tmp/compiler_for_loops.out
	@diff -u testing/compiler_for_loops.expected .tmp/compiler_for_loops.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 9: Phase 10 Dictionaries"
	@./$(TARGET) --compile testing/compiler_dicts.sage -o .tmp/compiler_dicts
	@./.tmp/compiler_dicts > .tmp/compiler_dicts.out
	@diff -u testing/compiler_dicts.expected .tmp/compiler_dicts.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 10: Phase 10 Tuples"
	@./$(TARGET) --compile testing/compiler_tuples.sage -o .tmp/compiler_tuples
	@./.tmp/compiler_tuples > .tmp/compiler_tuples.out
	@diff -u testing/compiler_tuples.expected .tmp/compiler_tuples.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 11: Phase 10 Exceptions"
	@./$(TARGET) --compile testing/compiler_exceptions.sage -o .tmp/compiler_exceptions
	@./.tmp/compiler_exceptions > .tmp/compiler_exceptions.out
	@diff -u testing/compiler_exceptions.expected .tmp/compiler_exceptions.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 12: Phase 10 String Builtins"
	@./$(TARGET) --compile testing/compiler_strings.sage -o .tmp/compiler_strings
	@./.tmp/compiler_strings > .tmp/compiler_strings.out
	@diff -u testing/compiler_strings.expected .tmp/compiler_strings.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 13: Phase 10 Memory Builtins"
	@./$(TARGET) --compile testing/compiler_memory.sage -o .tmp/compiler_memory
	@./.tmp/compiler_memory > .tmp/compiler_memory.out
	@diff -u testing/compiler_memory.expected .tmp/compiler_memory.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 14: Phase 10 Struct Builtins"
	@./$(TARGET) --compile testing/compiler_structs.sage -o .tmp/compiler_structs
	@./.tmp/compiler_structs > .tmp/compiler_structs.out
	@diff -u testing/compiler_structs.expected .tmp/compiler_structs.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 15: Phase 10 Classes"
	@./$(TARGET) --compile testing/compiler_classes.sage -o .tmp/compiler_classes
	@./.tmp/compiler_classes > .tmp/compiler_classes.out
	@diff -u testing/compiler_classes.expected .tmp/compiler_classes.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 16: Phase 10 Modules"
	@./$(TARGET) --compile testing/compiler_modules.sage -o .tmp/compiler_modules
	@./.tmp/compiler_modules > .tmp/compiler_modules.out
	@diff -u testing/compiler_modules.expected .tmp/compiler_modules.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 17: Phase 10 Architecture Detection"
	@./$(TARGET) --compile testing/compiler_arch.sage -o .tmp/compiler_arch
	@./.tmp/compiler_arch > .tmp/compiler_arch.out
	@diff -u testing/compiler_arch.expected .tmp/compiler_arch.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 18: Constant Folding (-O1)"
	@./$(TARGET) --compile testing/compiler_constfold.sage -o .tmp/compiler_constfold -O1
	@./.tmp/compiler_constfold > .tmp/compiler_constfold.out
	@diff -u testing/compiler_constfold.expected .tmp/compiler_constfold.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 19: Dead Code Elimination (-O2)"
	@./$(TARGET) --compile testing/compiler_dce.sage -o .tmp/compiler_dce -O2
	@./.tmp/compiler_dce > .tmp/compiler_dce.out
	@diff -u testing/compiler_dce.expected .tmp/compiler_dce.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 20: Function Inlining (-O3)"
	@./$(TARGET) --compile testing/compiler_inline.sage -o .tmp/compiler_inline -O3
	@./.tmp/compiler_inline > .tmp/compiler_inline.out
	@diff -u testing/compiler_inline.expected .tmp/compiler_inline.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 21: Optimization Levels (-O0 through -O3)"
	@./$(TARGET) --compile testing/compiler_optlevels.sage -o .tmp/compiler_optlevels_o0 -O0
	@./.tmp/compiler_optlevels_o0 > .tmp/compiler_optlevels_o0.out
	@diff -u testing/compiler_optlevels.expected .tmp/compiler_optlevels_o0.out && echo "✅ -O0 Pass" || echo "❌ -O0 Fail"
	@./$(TARGET) --compile testing/compiler_optlevels.sage -o .tmp/compiler_optlevels_o1 -O1
	@./.tmp/compiler_optlevels_o1 > .tmp/compiler_optlevels_o1.out
	@diff -u testing/compiler_optlevels.expected .tmp/compiler_optlevels_o1.out && echo "✅ -O1 Pass" || echo "❌ -O1 Fail"
	@./$(TARGET) --compile testing/compiler_optlevels.sage -o .tmp/compiler_optlevels_o2 -O2
	@./.tmp/compiler_optlevels_o2 > .tmp/compiler_optlevels_o2.out
	@diff -u testing/compiler_optlevels.expected .tmp/compiler_optlevels_o2.out && echo "✅ -O2 Pass" || echo "❌ -O2 Fail"
	@./$(TARGET) --compile testing/compiler_optlevels.sage -o .tmp/compiler_optlevels_o3 -O3
	@./.tmp/compiler_optlevels_o3 > .tmp/compiler_optlevels_o3.out
	@diff -u testing/compiler_optlevels.expected .tmp/compiler_optlevels_o3.out && echo "✅ -O3 Pass" || echo "❌ -O3 Fail"
	@echo ""
	@echo "Test 22: LLVM IR Generation"
	@./$(TARGET) --emit-llvm testing/compiler_smoke.sage -o .tmp/compiler_smoke.ll && echo "✅ Pass (LLVM IR emitted)" || echo "❌ Fail"
	@echo ""
	@echo "Test 22b: LLVM Compile + Run"
	@if command -v clang >/dev/null 2>&1; then \
		./$(TARGET) --compile-llvm testing/compiler_smoke.sage -o .tmp/compiler_smoke_llvm && \
		./.tmp/compiler_smoke_llvm > .tmp/compiler_smoke_llvm.out && \
		diff -u testing/compiler_smoke.expected .tmp/compiler_smoke_llvm.out && echo "✅ Pass (LLVM compiled + ran)" || echo "❌ Fail"; \
	else \
		echo "⏭ Skip (clang not found)"; \
	fi
	@echo ""
	@echo "Test 22c: LLVM Features (arrays, dicts, for, string, recursion)"
	@if command -v clang >/dev/null 2>&1; then \
		./$(TARGET) --compile-llvm testing/llvm_features.sage -o .tmp/llvm_features && \
		./.tmp/llvm_features > .tmp/llvm_features.out && \
		diff -u testing/llvm_features.expected .tmp/llvm_features.out && echo "✅ Pass" || echo "❌ Fail"; \
	else \
		echo "⏭ Skip (clang not found)"; \
	fi
	@echo ""
	@echo "Test 23: Assembly Generation (host target)"
	@./$(TARGET) --emit-asm testing/compiler_smoke.sage -o .tmp/compiler_smoke.s && echo "✅ Pass (ASM emitted)" || echo "❌ Fail"
	@echo ""
	@echo "Test 24: Debug Info (-g flag)"
	@./$(TARGET) --compile testing/compiler_smoke.sage -o .tmp/compiler_smoke_debug -g
	@./.tmp/compiler_smoke_debug > .tmp/compiler_smoke_debug.out
	@diff -u testing/compiler_smoke.expected .tmp/compiler_smoke_debug.out && echo "✅ Pass" || echo "❌ Fail"
	@echo ""
	@echo "Test 25: REPL"
	@echo ":quit" | ./$(TARGET) --repl 2>&1 | grep -q "Sage REPL" && echo "✅ Pass (banner shown)" || (echo "❌ Fail (banner)"; exit 1)
	@echo "1 + 2" | ./$(TARGET) --repl 2>&1 | grep -q "sage> 3" && echo "✅ Pass (expression eval)" || (echo "❌ Fail (expression eval)"; exit 1)
	@echo ""
	@echo "Test 26: Formatter"
	@printf "let   x=1\nlet y =  2\n" > .tmp/fmt_test.sage
	@./$(TARGET) fmt .tmp/fmt_test.sage && echo "✅ Pass (fmt ran)" || (echo "❌ Fail (fmt)"; exit 1)
	@./$(TARGET) fmt --check .tmp/fmt_test.sage && echo "✅ Pass (--check clean)" || (echo "❌ Fail (--check)"; exit 1)
	@printf "let   x=1\nlet y =  2\n" > .tmp/fmt_dirty.sage
	@./$(TARGET) fmt --check .tmp/fmt_dirty.sage 2>&1; \
		test $$? -ne 0 && echo "✅ Pass (--check detects unformatted)" || (echo "❌ Fail (--check should fail)"; exit 1)
	@echo ""
	@echo "Test 27: Linter"
	@printf "proc badName():\n    let x = 1\n    print 42\n" > .tmp/lint_bad.sage
	@./$(TARGET) lint .tmp/lint_bad.sage 2>&1; \
		test $$? -ne 0 && echo "✅ Pass (lint found issues)" || (echo "❌ Fail (lint should find issues)"; exit 1)
	@printf "# Greet the user\nproc good_name():\n    print 42\n" > .tmp/lint_clean.sage
	@./$(TARGET) lint .tmp/lint_clean.sage && echo "✅ Pass (lint clean)" || (echo "❌ Fail (lint clean)"; exit 1)
	@echo ""
	@echo "Test 28: LSP"
	@python3 -c "\
	import sys; \
	msg = '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"capabilities\":{}}}'; \
	header = 'Content-Length: %d\r\n\r\n' % len(msg); \
	sys.stdout.write(header + msg); \
	sys.stdout.flush()" | timeout 5 ./$(TARGET) --lsp 2>/dev/null | head -c 4096 | grep -q '"sage-lsp"' && echo "✅ Pass" || (echo "❌ Fail"; exit 1)

# ============================================================================
# Self-Hosted Sage Build (Bootstrap)
# ============================================================================

# (sage-boot defined above in build section)

# Run all self-hosted tests
test-selfhost: $(TARGET)
	@echo ""
	@echo "=== Self-Hosted Lexer Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_lexer.sage
	@echo ""
	@echo "=== Self-Hosted Parser Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_parser.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Interpreter Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_interpreter.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Bootstrap Integration Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_bootstrap.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Formatter Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_formatter.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Linter Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_linter.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Value Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_value.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Pass Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_pass.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Constfold Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_constfold.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted DCE Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_dce.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Inline Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_inline.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Typecheck Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_typecheck.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Stdlib Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_stdlib.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Module Tests ==="
	@mkdir -p /tmp/sage_test_modules
	@cd src/sage && ../../$(TARGET) test/test_module.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted LLVM Backend Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_llvm_backend.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Codegen Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_codegen.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted C Compiler Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_compiler.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Error Reporting Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_errors.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted LSP Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_lsp.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Sage CLI Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_sage_cli.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Diagnostic Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_diagnostic.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted GC Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_gc.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted Heartbeat Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_heartbeat.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted GPU Module Tests ==="
	@cd src/sage && ../../$(TARGET) test/test_gpu.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted GPU Advanced Tests ==="
	@./$(TARGET) src/sage/test/test_gpu_advanced.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted GPU Features 1-18 Tests ==="
	@./$(TARGET) src/sage/test/test_gpu_features.sage 2>&1 | tail -3
	@echo ""
	@echo "=== Self-Hosted GPU Engine Tests ==="
	@./$(TARGET) src/sage/test/test_gpu_engine.sage 2>&1 | tail -3
	@echo ""
	@echo "✅ All self-hosted tests complete"

# Run individual self-hosted test suites
test-selfhost-lexer: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_lexer.sage

test-selfhost-parser: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_parser.sage

test-selfhost-interpreter: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_interpreter.sage

test-selfhost-bootstrap: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_bootstrap.sage

test-selfhost-formatter: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_formatter.sage

test-selfhost-linter: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_linter.sage

test-selfhost-value: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_value.sage

test-selfhost-pass: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_pass.sage

test-selfhost-constfold: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_constfold.sage

test-selfhost-dce: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_dce.sage

test-selfhost-inline: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_inline.sage

test-selfhost-typecheck: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_typecheck.sage

test-selfhost-stdlib: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_stdlib.sage

test-selfhost-module: $(TARGET)
	@mkdir -p /tmp/sage_test_modules
	cd src/sage && ../../$(TARGET) test/test_module.sage

test-selfhost-llvm-backend: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_llvm_backend.sage

test-selfhost-codegen: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_codegen.sage

test-selfhost-compiler: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_compiler.sage

test-selfhost-errors: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_errors.sage

test-selfhost-lsp: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_lsp.sage

test-selfhost-sage-cli: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_sage_cli.sage

test-selfhost-diagnostic: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_diagnostic.sage

test-selfhost-gc: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_gc.sage

test-selfhost-heartbeat: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_heartbeat.sage

test-selfhost-gpu: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_gpu.sage

test-selfhost-gpu-advanced: $(TARGET)
	./$(TARGET) src/sage/test/test_gpu_advanced.sage

test-selfhost-llvm-gpu: $(TARGET)
	cd src/sage && ../../$(TARGET) test/test_llvm_gpu.sage

# Run ALL tests (C + self-hosted)
test-all: test test-selfhost
	@echo ""
	@echo "✅ All C and self-hosted tests complete"

# ============================================================================
# Cleanup
# ============================================================================

# Kernel-style build configuration (uses kconfiglib)
menuconfig:
	@KCONFIG_CONFIG=.config $(PYTHON) scripts/kconfig_frontend.py menuconfig Kconfig
	@$(PYTHON) scripts/kconfig_to_make.py .config sage_config.mk
	@echo ""
	@echo "Configuration saved. Run 'make' to build."

# GUI config (if available)
guiconfig:
	@KCONFIG_CONFIG=.config $(PYTHON) scripts/kconfig_frontend.py guiconfig Kconfig
	@$(PYTHON) scripts/kconfig_to_make.py .config sage_config.mk

# Load saved config if it exists
-include sage_config.mk

# Compile all GLSL shaders to SPIR-V
shaders:
	@echo "Compiling shaders..."
	@cd examples/shaders && for f in *.vert *.frag *.comp; do \
		glslc "$$f" -o "$$f.spv" 2>&1 || echo "FAIL: $$f"; \
	done
	@echo "✅ Shaders compiled ($$(ls examples/shaders/*.spv | wc -l) modules)"

clean:
	rm -rf $(OBJ_DIR) $(TARGET) $(LSP_TARGET)
	@echo "✅ Cleaned build artifacts"

clean-all: clean
	rm -rf build build_pico
	@echo "✅ Cleaned all build directories"

# ============================================================================
# CMake Integration
# ============================================================================

cmake: clean
	@echo "Setting up CMake build..."
	mkdir -p build
	cd build && cmake ..
	@echo "✅ CMake configured. Run: cd build && make"

cmake-build: cmake
	cd build && make -j$$(nproc)
	@echo "✅ CMake build complete"
	@echo "   Run with: ./build/sage examples/hello.sage"

cmake-sage: clean
	@echo "Setting up CMake self-hosted Sage build..."
	mkdir -p build_sage
	cd build_sage && cmake -DBUILD_SAGE=ON ..
	@echo "✅ Sage CMake configured. Run: cd build_sage && make test_selfhost"

cmake-sage-build: cmake-sage
	cd build_sage && make -j$$(nproc) test_selfhost
	@echo "✅ Self-hosted tests complete"

cmake-pico: clean
	@echo "Setting up Pico build..."
	mkdir -p build_pico
	cd build_pico && cmake -DBUILD_PICO=ON ..
	@echo "✅ Pico CMake configured. Run: cd build_pico && make"

# ============================================================================
# Code Statistics
# ============================================================================

stats:
	@echo "SageLang Code Statistics"
	@echo "========================"
	@echo "C Source files:"
	@find src/c -name "*.c" | wc -l
	@echo "Header files:"
	@find include -name "*.h" | wc -l
	@echo "Total lines of C code:"
	@find src/c include -name "*.[ch]" | xargs wc -l | tail -1
	@echo ""
	@echo "Sage Example files:"
	@find examples -name "*.sage" | wc -l
	@echo "Total lines of Sage code:"
	@find examples -name "*.sage" | xargs wc -l | tail -1

# ============================================================================
# Help
# ============================================================================

help:
	@echo "SageLang Makefile - v$(SAGE_VERSION)"
	@echo "==========================="
	@echo ""
	@echo "Build Targets (C):"
	@echo "  make              - Build sage executable from C (default)"
	@echo "  make debug        - Build with debug symbols"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make clean-all    - Remove all build directories"
	@echo ""
	@echo "Self-Hosted (Sage):"
	@echo "  make sage-boot FILE=<f>  - Run a .sage file via self-hosted interpreter"
	@echo "  make test-selfhost       - Run all self-hosted tests (1567+ tests)"
	@echo "  make test-selfhost-lexer      - Run lexer tests only"
	@echo "  make test-selfhost-parser     - Run parser tests only"
	@echo "  make test-selfhost-interpreter - Run interpreter tests only"
	@echo "  make test-selfhost-bootstrap  - Run bootstrap tests only"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Run C compiler/interpreter tests"
	@echo "  make test-selfhost - Run self-hosted tests"
	@echo "  make test-all     - Run ALL tests (C + self-hosted)"
	@echo ""
	@echo "Development:"
	@echo "  make run          - Run hello.sage example"
	@echo "  make examples     - Run all examples"
	@echo "  make run-<name>   - Run specific example (e.g., make run-fibonacci)"
	@echo "  make charts       - Refresh README LOC charts"
	@echo "  make stats        - Show code statistics"
	@echo "  make menuconfig   - Configure build options (requires kconfiglib)"
	@echo "  make guiconfig    - GUI config editor (requires kconfiglib; Ubuntu may need python3-tk)"
	@echo ""
	@echo "Installation:"
	@echo "  make install      - Install to /usr/local (use sudo)"
	@echo "  make uninstall    - Remove installation"
	@echo "  PREFIX=/path      - Custom install location"
	@echo ""
	@echo "CMake:"
	@echo "  make cmake            - Setup CMake build (C)"
	@echo "  make cmake-build      - Build with CMake (C)"
	@echo "  make cmake-sage       - Setup CMake build (Sage self-hosted)"
	@echo "  make cmake-pico       - Setup Pico CMake build"
	@echo ""
	@echo "Examples:"
	@echo "  make                                  # Build from C"
	@echo "  make sage-boot FILE=hello.sage        # Run via self-hosted Sage"
	@echo "  make test-all                         # Run all tests"
	@echo "  sudo make install                     # System-wide install"
	@echo "  make DEBUG=1                          # Debug build"

# ============================================================================
# C-Only Model Trainer (SL-TQ-LLM)
# ============================================================================

train-c: src/c/train_sl_tq.c
	@TRAIN_FLAGS=""; \
	TRAIN_LIBS="-lm -lpthread"; \
	if pkg-config --exists cublas 2>/dev/null || [ -f /usr/include/cublas_v2.h ]; then \
		echo "  [cuBLAS] GPU acceleration enabled"; \
		TRAIN_FLAGS="$$TRAIN_FLAGS -DUSE_CUBLAS"; \
		TRAIN_LIBS="$$TRAIN_LIBS -lcublas -lcudart"; \
	fi; \
	if [ "$$(uname -m)" = "aarch64" ]; then \
		echo "  [NEON]   ARM64 SIMD enabled"; \
		TRAIN_FLAGS="$$TRAIN_FLAGS -DUSE_NEON"; \
	fi; \
	if [ "$$(uname -m)" = "riscv64" ]; then \
		echo "  [RVV]    RISC-V Vector enabled"; \
		TRAIN_FLAGS="$$TRAIN_FLAGS -DUSE_RVV -march=rv64gcv"; \
	fi; \
	echo "  Building train_sl_tq..."; \
	$(CC) -O3 -march=native $$TRAIN_FLAGS -o train_sl_tq src/c/train_sl_tq.c $$TRAIN_LIBS; \
	echo "Built: train_sl_tq"
	@echo "Usage: ./train_sl_tq [steps] [lr]"
	@echo "  Default: 50000 steps, lr=0.0003"
	@echo "  Desktop: ./train_sl_tq 200000 0.001  (cuBLAS GPU if available)"
	@echo "  Mobile:  ./train_sl_tq 50000 0.001   (ARM NEON on Termux/proot)"

# Train model via Sage interpreter (uses ml_native.train_step with backprop)
train-sage: $(TARGET)
	./$(TARGET) models/training/train_sl_tq_llm.sage

# Compile SageLLM chatbot via C backend
chatbot-c: $(TARGET)
	./$(TARGET) --compile models/chatbots/sagellm_chatbot.sage -o sagellm_chat
	@echo "Built: sagellm_chat (C backend)"

# Compile SageLLM chatbot via LLVM backend
chatbot-llvm: $(TARGET)
	./$(TARGET) --compile-llvm models/chatbots/sagellm_chatbot.sage -o sagellm_chat
	@echo "Built: sagellm_chat (LLVM backend)"

# Compile SageLLM chatbot via native assembly backend
chatbot-native: $(TARGET)
	./$(TARGET) --compile-native models/chatbots/sagellm_chatbot.sage -o sagellm_chat
	@echo "Built: sagellm_chat (native backend)"

# Compile SL-TQ-LLM generative chatbot via LLVM
sl-tq-chat: $(TARGET)
	./$(TARGET) --compile-llvm models/chatbots/sl_tq_llm_chat.sage -o sl_tq_chat
	@echo "Built: sl_tq_chat (LLVM backend)"

# Compile kernel for bare metal
kernel-bare: $(TARGET)
	./$(TARGET) --compile-bare models/chatbots/sagellm_chatbot.sage -o kernel.elf
	@echo "Built: kernel.elf (bare metal)"

# Compile UEFI application
kernel-uefi: $(TARGET)
	./$(TARGET) --compile-uefi models/chatbots/sagellm_chatbot.sage -o boot.efi
	@echo "Built: boot.efi (UEFI)"

# Run bare-metal kernel in QEMU (x86_64)
qemu-bare: kernel-bare
	qemu-system-x86_64 -machine q35 -m 64M -display none -serial stdio -no-reboot -kernel kernel.elf

# Run bare-metal kernel in QEMU (aarch64)
qemu-bare-arm64: $(TARGET)
	./$(TARGET) --compile-bare models/chatbots/sagellm_chatbot.sage -o kernel-arm64.elf --target aarch64
	qemu-system-aarch64 -machine virt -cpu cortex-a72 -m 64M -display none -serial stdio -no-reboot -kernel kernel-arm64.elf

# Run bare-metal kernel in QEMU with GDB (port 1234)
qemu-debug: kernel-bare
	@echo "Waiting for GDB on port 1234... (gdb -ex 'target remote :1234' kernel.elf)"
	qemu-system-x86_64 -machine q35 -m 64M -display none -serial stdio -no-reboot -kernel kernel.elf -gdb tcp::1234 -S

# Self-evolving training (progressive growth)
evolve:
	bash models/training/evolve_train.sh

# Download training datasets
datasets:
	bash models/data/download_datasets.sh all

# Build everything: sage + trainer + chatbot
all-models: $(TARGET) train-c chatbot-llvm sl-tq-chat
	@echo "All models built."

# ============================================================================
# Phony Targets Declaration
# ============================================================================

.PHONY: all clean clean-all run examples test install uninstall charts \
        debug cmake cmake-build cmake-sage cmake-sage-build cmake-pico \
        sage-boot test-selfhost test-selfhost-lexer test-selfhost-parser \
        test-selfhost-interpreter test-selfhost-bootstrap \
        test-selfhost-formatter test-selfhost-linter test-selfhost-value \
        test-selfhost-pass test-selfhost-constfold test-selfhost-dce test-selfhost-inline \
        test-selfhost-typecheck test-selfhost-stdlib test-selfhost-module \
        test-selfhost-llvm-backend test-selfhost-codegen test-selfhost-compiler \
        test-selfhost-errors test-selfhost-lsp test-selfhost-sage-cli \
        test-selfhost-diagnostic test-selfhost-gc test-selfhost-heartbeat test-selfhost-gpu test-selfhost-gpu-advanced \
        test-all stats help shaders menuconfig guiconfig \
        train-c train-sage chatbot-c chatbot-llvm chatbot-native sl-tq-chat all-models evolve datasets \
        kernel-bare kernel-uefi qemu-bare qemu-bare-arm64 qemu-debug
