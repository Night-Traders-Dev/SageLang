# Changelog

All notable changes to this project will be documented in this file.

## [3.8.3] - 2026-06-18
- **MIPS Target Support**: Added backend compiler and assembly generation support for MIPS 74K / BCM5357 (O32 ABI compliant code generation, ELF output, target parsing).
- **MIPS Library Submodule**: Created and added `sagelang-lib-mips` submodule under `core/lib/mips`.

## [3.8.3] - 2026-06-17
- **Standard Library Overhaul**: Implemented `__init__.sage` support for directory-based packages, allowing cleaner imports like `import blockchain` instead of requiring full paths.
- **Library Stabilization**: Fixed hundreds of syntax errors (missing colons, outdated `end` keywords) across the entire standard library (`std`, `net`, `os`, `crypto`, `ml`, `llm`, `metal`, `graphics`, `agent`).
- **Version Bump**: Finalized v3.8.3 release.
- **Modularization**: Refactored core libraries into standalone repositories managed by Git submodules.
- **Benchmarks**: Refreshed benchmark charts and metrics.

## [3.8.3] - 2026-06-16
- **General Improvements**: Various performance and stability improvements.

## [3.8.3] - 2026-06-14
- **Performance**: Significant VM optimizations and toolchain hardening.

## [3.8.3] - 2026-05-29
- **Security**: Sandbox security guards and structural uniqueness checks.

## [3.8.3] - 2026-03-01
- **Initial Release**: Core interpreter and compiler stability achieved.
