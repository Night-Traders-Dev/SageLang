# SageLang Makefile
# For those who prefer Make over CMake
# Note: CMakeLists.txt is recommended for Pico builds

# ============================================================================
# Configuration
# ============================================================================

CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic -O2 -D_POSIX_C_SOURCE=200809L
LDFLAGS = -lm -lpthread -ldl

# Directories
SRC_DIR = src
INC_DIR = include
OBJ_DIR = obj
BIN_DIR = .
BOARD_DIR = boards

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
    $(SRC_DIR)/env.c \
    $(SRC_DIR)/gc.c \
    $(SRC_DIR)/inline.c \
    $(SRC_DIR)/interpreter.c \
    $(SRC_DIR)/lexer.c \
    $(SRC_DIR)/llvm_backend.c \
    $(SRC_DIR)/module.c \
    $(SRC_DIR)/parser.c \
    $(SRC_DIR)/pass.c \
    $(SRC_DIR)/stdlib.c \
    $(SRC_DIR)/typecheck.c \
    $(SRC_DIR)/value.c

MAIN_SOURCE = $(SRC_DIR)/main.c

# Optional heartbeat source
ifneq (,$(wildcard $(SRC_DIR)/heartbeat.c))
    CORE_SOURCES += $(SRC_DIR)/heartbeat.c
    $(info Including heartbeat.c with pthread support)
endif

# Headers
HEADERS = \
    $(INC_DIR)/ast.h \
    $(INC_DIR)/codegen.h \
    $(INC_DIR)/compiler.h \
    $(INC_DIR)/env.h \
    $(INC_DIR)/gc.h \
    $(INC_DIR)/interpreter.h \
    $(INC_DIR)/lexer.h \
    $(INC_DIR)/llvm_backend.h \
    $(INC_DIR)/module.h \
    $(INC_DIR)/pass.h \
    $(INC_DIR)/token.h \
    $(INC_DIR)/typecheck.h \
    $(INC_DIR)/value.h

# Optional heartbeat header
ifneq (,$(wildcard $(INC_DIR)/heartbeat.h))
    HEADERS += $(INC_DIR)/heartbeat.h
endif

# Object files
CORE_OBJECTS = $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(CORE_SOURCES))
MAIN_OBJECT = $(OBJ_DIR)/main.o
ALL_OBJECTS = $(CORE_OBJECTS) $(MAIN_OBJECT)

# Binary
TARGET = sage

# ============================================================================
# Build Rules
# ============================================================================

.PHONY: all clean run install uninstall help test examples

all: $(TARGET)

# Link executable
$(TARGET): $(ALL_OBJECTS)
	@mkdir -p $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
	@echo "✅ Built: $(TARGET)"
	@echo "   Run with: ./$(TARGET) examples/hello.sage"

# Compile source files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(HEADERS)
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -I$(INC_DIR) -c $< -o $@
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

# ============================================================================
# Installation
# ============================================================================

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/share/sage
DOCDIR = $(PREFIX)/share/doc/sage

install: $(TARGET)
	@echo "Installing SageLang to $(PREFIX)..."
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)
	install -d $(LIBDIR)/lib
	install -d $(LIBDIR)/examples
	cp -r lib/*.sage $(LIBDIR)/lib/
	cp -r examples/*.sage $(LIBDIR)/examples/
	install -d $(DOCDIR)
	install -m 644 README.md ROADMAP.md LICENSE $(DOCDIR)/
	@echo "✅ Installation complete"
	@echo "   Run with: sage <script.sage>"

uninstall:
	@echo "Uninstalling SageLang..."
	rm -f $(BINDIR)/$(TARGET)
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
	@echo "Test 23: Assembly Generation (host target)"
	@./$(TARGET) --emit-asm testing/compiler_smoke.sage -o .tmp/compiler_smoke.s && echo "✅ Pass (ASM emitted)" || echo "❌ Fail"
	@echo ""
	@echo "Test 24: Debug Info (-g flag)"
	@./$(TARGET) --compile testing/compiler_smoke.sage -o .tmp/compiler_smoke_debug -g
	@./.tmp/compiler_smoke_debug > .tmp/compiler_smoke_debug.out
	@diff -u testing/compiler_smoke.expected .tmp/compiler_smoke_debug.out && echo "✅ Pass" || echo "❌ Fail"

# ============================================================================
# Cleanup
# ============================================================================

clean:
	rm -rf $(OBJ_DIR) $(TARGET)
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
	@find src -name "*.c" | wc -l
	@echo "Header files:"
	@find include -name "*.h" | wc -l
	@echo "Total lines of C code:"
	@find src include -name "*.[ch]" | xargs wc -l | tail -1
	@echo ""
	@echo "Sage Example files:"
	@find examples -name "*.sage" | wc -l
	@echo "Total lines of Sage code:"
	@find examples -name "*.sage" | xargs wc -l | tail -1

# ============================================================================
# Help
# ============================================================================

help:
	@echo "SageLang Makefile - v0.8.0"
	@echo "=========================="
	@echo ""
	@echo "Build Targets:"
	@echo "  make              - Build sage executable (default)"
	@echo "  make debug        - Build with debug symbols"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make clean-all    - Remove all build directories"
	@echo ""
	@echo "Development:"
	@echo "  make run          - Run hello.sage example"
	@echo "  make examples     - Run all examples"
	@echo "  make run-<name>   - Run specific example (e.g., make run-fibonacci)"
	@echo "  make test         - Run basic tests"
	@echo "  make stats        - Show code statistics"
	@echo ""
	@echo "Installation:"
	@echo "  make install      - Install to /usr/local (use sudo)"
	@echo "  make uninstall    - Remove installation"
	@echo "  PREFIX=/path      - Custom install location"
	@echo ""
	@echo "CMake (Recommended for Pico):"
	@echo "  make cmake        - Setup CMake build"
	@echo "  make cmake-build  - Build with CMake"
	@echo "  make cmake-pico   - Setup Pico CMake build"
	@echo ""
	@echo "Examples:"
	@echo "  make                    # Build"
	@echo "  make run                # Run hello example"
	@echo "  make run-fibonacci      # Run fibonacci example"
	@echo "  sudo make install       # System-wide install"
	@echo "  make DEBUG=1            # Debug build"
	@echo "  make cmake-pico         # Setup Pico build"
	@echo ""
	@echo "For Pico builds, use CMake:"
	@echo "  mkdir build_pico && cd build_pico"
	@echo "  cmake -DBUILD_PICO=ON .."
	@echo "  make -j$$(nproc)"

# ============================================================================
# Phony Targets Declaration
# ============================================================================

.PHONY: all clean clean-all run examples test install uninstall \
        debug cmake cmake-build cmake-pico stats help
