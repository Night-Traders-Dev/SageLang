# SageLang Minimal OS Proof-of-Concept Documentation

## Overview
This document outlines the creation of a minimal, bootable Proof-of-Concept (PoC) OS using the SageLang toolchain. The goal was to establish a baseline for building OS kernels that align with the SageLang project's "Sage-First" development philosophy.

## Implementation Details
- **Architecture**: Bare-metal execution via SageVM.
- **Components**:
    - **Execution Engine**: `SageVM` (freestanding bytecode interpreter).
    - **Kernel**: Minimal `SageLang` bytecode (`kernel.sgvm`).
    - **Rootfs**: Traditional Unix-style hierarchy (`/bin`, `/etc`, `/dev`, `/lib`, `/proc`, `/sys`) prepared for future use.
- **Build System**: Orchestrated via `build.sh` using `sgvmc` (SageLang bytecode compiler).

## Challenges & Solutions

### 1. Toolchain Limitations
- **Challenge**: Initial attempts to compile `SageLang` (`.sage`) code directly to bare-metal failed because of missing runtime dependencies (`sage_rt_*`).
- **Solution**: Pivoted to using the `SageVM` bytecode pipeline. This allows running `SageLang` kernel logic on a freestanding bytecode interpreter, eliminating the need for native runtime shims.

### 2. VM Compatibility
- **Challenge**: The initial kernel implementation used native `asm()` blocks, which the `SageVM` compiler cannot process.
- **Solution**: Refactored the kernel to use high-level `print()` primitives, which are directly supported by `SageVM` and align with the "Pure Sage" goal.

## How to Run
1. **Build**: Run `./minimal_os/build.sh`.
2. **Run**: Execute `./minimal_os/run.sh` to "boot" the kernel bytecode using the SageVM interpreter.
