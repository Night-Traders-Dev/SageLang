# Benchmark Analysis: NTD SageVM vs. MossVM

This document provides a performance comparison between Night-Traders-Dev's (NTD) SageVM and MilkmanAbi's (MA) MossVM.

## Performance Table

| Benchmark | MA MossVM (C, native) | MA Sage AST (host interpreter) | NTD SageVM SVM (self-hosted, real run) | NTD SageVM README claim |
| :--- | :--- | :--- | :--- | :--- |
| fib(22) | 56ms | 71ms | 6710ms | 2256ms |
| loop_sum(100k) | 20ms | 40ms | 12030ms | 4513ms |
| peak RSS, fib(22) | ~25MB | ~25MB | ~739MB | — |
| peak RSS, loop_sum | ~15MB | ~15MB | ~1.4GB | — |

## Summary Analysis

MA's MossVM (the native C bytecode VM) outperforms NTD's SageVM (the self-hosted VM written in Sage script on top of the original pre-fork NTD/SageLang interpreter) by roughly 120x on recursive calls and 600x on tight loops, using 30-100x less memory.

### Discrepancy Note
NTD's own README understates this gap by ~3x because its benchmark script silently falls back to the host's AST interpreter instead of actually running its VM. This has been confirmed in `run_bench.sh`, which contains: `Using 'ast' as it currently passes the tests where 'bytecode' fails`. The numbers above were gathered by rebuilding the NTD SageVM from source and running its real `sagevm` binary directly.

### Architectural Context
*   **MA MossVM**: A switch-dispatched bytecode loop over a tagged C struct, compiled to a real jump-table executable.
*   **NTD SageVM**: A VM class written in SageLang itself, dispatching opcodes through a linear `if`/`elif` chain and using Sage's dynamic dictionaries and arrays as its stack and registers, executed inside another tree-walking interpreter. This constitutes "interpretation squared."

These projects fulfill different roles: NTD's SageVM targets opcode-parity and portability for SageOS on top of the original SageLang, whereas MossVM aims for raw performance. The benchmark reflects the fundamental difference between a native C VM and a script-hosted meta-VM.

*Note: The RISC-V register variant (SRVM) from NTD, advertised as 30-40% faster, currently crashes on the same `fib` benchmark with a runtime type error and is not currently viable.*
