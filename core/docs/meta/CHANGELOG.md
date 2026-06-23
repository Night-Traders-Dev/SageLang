# Changelog

All notable changes to this project will be documented in this file.

## [3.8.6] - 2026-06-22
- **Extend FFI argument type patterns**: Added support for `int`, `long`, and `void` return types in FFI argument type patterns.
- **C compile backend fixes**: Pad default params with `nil` in `--compile` mode, fix native module name matching (`math` vs `_math`).
- **sagemake**: Exclude meta documentation files (CHANGELOG.md, UPDATES.md, ROADMAP.md) from version propagation to prevent version history flattening.

## [3.8.5] - 2026-06-21
- **Bitwise shift fixes**: `>>` and `<<` now use unsigned arithmetic throughout all backends (interpreter, compiler C codegen, AOT, LLVM, bytecode VM), fixing arithmetic sign-extension on values ≥ 2⁶³ and negative overflow from `<<` (core bugfix).
- **Array concatenation (`+`)**: `[1,2] + [3,4]` now returns `[1,2,3,4]` instead of `nil` in the interpreter, C codegen runtime, and bytecode VM.
- **`range(start, end, step)`**: The `range` builtin now accepts 3 arguments (start, end, step) with positive and negative step support.
- **`io.readbytes` non-seekable file support**: `/dev/urandom` and other non-seekable files now read correctly by falling back to chunked reads when `fseek` fails. Fixed in interpreter stdlib, C codegen runtime, and LLVM runtime.
- **`range` C codegen**: Added `sage_range3` runtime helper for 3-arg range calls.

## [3.8.4] - 2026-06-18
- **MIPS Target Support**: Added backend compiler and assembly generation support for MIPS 74K / BCM5357 (O32 ABI compliant code generation, ELF output, target parsing).
- **MIPS Library Submodule**: Created and added `sagelang-lib-mips` submodule under `core/lib/mips`.

## [3.8.3] - 2026-06-17
- **Standard Library Overhaul**: Implemented `__init__.sage` support for directory-based packages, allowing cleaner imports like `import blockchain` instead of requiring full paths.
- **Library Stabilization**: Fixed hundreds of syntax errors (missing colons, outdated `end` keywords) across the entire standard library (`std`, `net`, `os`, `crypto`, `ml`, `llm`, `metal`, `graphics`, `agent`).
- **Version Bump**: Finalized v3.8.3 release.
- **Modularization**: Refactored core libraries into standalone repositories managed by Git submodules.
- **Benchmarks**: Refreshed benchmark charts and metrics.

## [3.8.2] - 2026-06-16
- **General Improvements**: Various performance and stability improvements.

## [3.8.1] - 2026-06-14
- **Performance**: Significant VM optimizations and toolchain hardening.

## [3.5.0] - 2026-05-29
- **Security**: Sandbox security guards and structural uniqueness checks.

## [3.0.0] - 2026-03-01
- **Initial Release**: Core interpreter and compiler stability achieved.
