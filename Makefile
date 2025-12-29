# SageLang Makefile
# For those who prefer Make over CMake
# Note: CMakeLists.txt is recommended for Pico builds

# ============================================================================
# Configuration
# ============================================================================

CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic -O2 -D_POSIX_C_SOURCE=200809L
LDFLAGS = -lm -lpthread

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
    $(SRC_DIR)/env.c \
    $(SRC_DIR)/gc.c \
    $(SRC_DIR)/interpreter.c \
    $(SRC_DIR)/lexer.c \
    $(SRC_DIR)/module.c \
    $(SRC_DIR)/parser.c \
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
    $(INC_DIR)/env.h \
    $(INC_DIR)/gc.h \
    $(INC_DIR)/interpreter.h \
    $(INC_DIR)/lexer.h \
    $(INC_DIR)/module.h \
    $(INC_DIR)/token.h \
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
