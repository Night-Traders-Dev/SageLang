# SageLang: Engineering Context & Instructions

SageLang is a systems programming language that combines the readability of Python (indentation-based blocks) with the performance and low-level control of C. It supports multiple execution backends, including a tree-walking interpreter, a bytecode VM, JIT/AOT compilation, and native code emission via C, LLVM, or direct assembly.

## Project Overview

- **Core Technology:** C (C11 standard) for the primary implementation; SageLang itself for the self-hosted compiler and standard library.
- **Backends:** C Codegen, LLVM IR, Native Assembly (x86-64, AArch64, RV64), Bytecode VM, JIT, AOT, and Kotlin/Android.
- **Memory Management:** Hybrid system with three GC modes: Concurrent Mark-Sweep (default), ARC (Automatic Reference Counting), and ORC (Optimized Reference Counting with cycle detection).
- **Graphics:** First-class Vulkan and OpenGL support with handle-based resource management.
- **OS Development:** Extensive support for bare-metal, UEFI, and Linux kernel development via `lib/os/`.
- **Machine Learning:** Native tensor operations, neural network layers, and GPU/SIMD acceleration (cuBLAS, NEON).

## Repository Structure

- `core/`: The heart of the project containing all source code, headers, and standard libraries.
  - `src/c/`: C implementation of the lexer, parser, interpreter, and backends.
  - `src/sage/`: Self-hosted SageLang implementation (bootstrap).
  - `src/vm/`: Bytecode virtual machine implementation.
  - `include/`: C header files.
  - `lib/`: Standard library modules written in SageLang (e.g., `std/`, `net/`, `os/`, `ml/`).
  - `tests/`: Extensive C and SageLang test suites.
  - `examples/`: Sample SageLang programs demonstrating various features.
- `models/`: ML models, training scripts, and the SageGPT chatbot implementation.
- `testsuite/`: Benchmarks and integration tests.
- `editors/`: Syntax highlighting and editor integration files.

## Core Development Commands

### Building and Installation
```bash
make            # Build 'sage' and 'sage-lsp' (delegates to core/Makefile)
make debug      # Build with debug symbols (-g -O0)
./sagemake all  # Unified build (auto-detects platform/GPU/NPU)
sudo make install # Install to /usr/local/bin and /usr/local/share/sage
```

### Running and Compiling
```bash
./sage script.sage              # Run using the default interpreter
./sage --runtime bytecode s.sage # Run using the bytecode VM
./sage --compile s.sage -o bin  # Compile to native binary via C backend
./sage --compile-llvm s.sage    # Compile via LLVM backend
./sage --jit s.sage             # Run with JIT profiling and compilation
```

### Testing
```bash
make test               # Run basic compiler and interpreter tests
make test-selfhost      # Run all self-hosted bootstrap tests
make test-all           # Run both C and self-hosted test suites
```

### Tooling
```bash
./sage fmt file.sage    # Format code in-place
./sage lint file.sage   # Run static linter
./sage --lsp            # Start the Language Server
```

## Engineering Conventions

### SageLang Syntax & Style
- **Indentation:** 4 spaces (standard). Blocks are defined by indentation, not braces.
- **Keywords:** `proc` (functions), `let` (variables), `class` (OOP), `yield` (generators).
- **Type Annotations:** Supported in the form `let x: Int = 42` or `proc add(a: Int, b: Int) -> Int:`.
- **Naming:** `snake_case` for variables and functions; `PascalCase` for classes and enums.

### C Implementation Style
- **Memory:** Use `safe_malloc` and `safe_free` wrappers (found in `gc.c`/`gc.h`) for GC-tracked allocations.
- **Types:** Value types are defined in `value.h` using the `Value` struct (union of types).
- **AST:** All AST nodes are defined in `ast.h` and constructed in `ast.c`.
- **Error Handling:** Use the diagnostic system in `diagnostic.c` for compiler errors and warnings.

### Standard Library Development
- Standard modules should be placed in `core/lib/` under appropriate subdirectories (e.g., `std/`, `net/`, `os/`).
- Documentation comments should start with `##` to be retrievable via the `doc()` builtin.
- Performance-critical paths should prefer built-in native functions (defined in `stdlib.c`) or `unsafe:` blocks if interacting with raw memory.

## Key Targets & Profiles
- **Bare-metal:** Use `--compile-bare --target x86_64` (emits `sage_entry`).
- **UEFI:** Use `--compile-uefi` (emits `efi_main`).
- **Pico:** Use `--compile-pico` for RP2040 support.
- **Android:** Use `--compile-android` to generate a Kotlin/Android project.

## Troubleshooting
- **Circular Imports:** Monitored via cycle detection; keep import graphs shallow where possible.
- **GC STW Pauses:** If STW pauses are too high, consider switching to `--gc:arc` or `--gc:orc`.
- **Recursion Limits:** The interpreter has a default depth limit of 1,000,000 to prevent stack overflow.
