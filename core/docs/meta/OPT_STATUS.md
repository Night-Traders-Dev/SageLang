# SageLang Optimization Status

## Objective
The primary goal is to address a ~100x performance discrepancy between SageLang's execution environments (AST Interpreter, Bytecode VM, C-Compiled Backend) and the MossVM standard. 

## Work Completed

1. **C Infrastructure (`core/src/c/env.c`)**
   - Implemented thread-local `Env` and `EnvNode` pools (`thread_env_pool`, `thread_node_pool`) to eliminate the heavy reliance on `malloc`/`free` and global mutexes during environment creation and destruction.
   - Refactored `env_sweep_unmarked` to recycle nodes into these thread-local pools.

2. **Bytecode VM Refactor (`core/src/vm/vm.c`, `core/src/vm/bytecode.c`)**
   - Introduced a proper `CallFrame` mechanism to the Bytecode VM to prevent relying on recursive C function calls for Sage function execution.
   - Replaced dynamic string-based lookups with direct slot index lookups using new opcodes `BC_OP_GET_LOCAL` and `BC_OP_SET_LOCAL`.
   - Updated the bytecode compiler (`compile_stmt`, `compile_expr`, `bytecode_compile_function_body`) to track local variables and scope depth, converting let assignments and `EXPR_VARIABLE` to use slots when within a function.
   - Updated `STMT_FOR` compilation to use slots for loop iteration variables within function boundaries.

3. **C-Backend Arithmetic Fast-paths (`core/src/c/compiler.c`)**
   - Inlined basic arithmetic operations (`+`, `-`, `*`, `/`, `<`, `<=`, `>`, `>=`, `==`, `!=`) into the generated C code using macros (e.g., `SAGE_ADD`, `SAGE_SUB`). These macros perform type checks and evaluate inline if both operands are numbers, bypassing the overhead of function calls (`sage_add`).
   - Removed an unintended `Mutation Fix` in `compiler.c` and `interpreter.c` for `STMT_FOR` loops that incorrectly treated the iteration variable as a numeric loop index instead of an array element value.
4. **Test Suite Resolution**
   - Resolved the `sys_info` unit test failure by changing it to dynamically load the version from the single-source `VERSION` file, making it version-independent.
   - Verified that `arrays_basic` and all other 336 unit tests pass successfully.

## Current Issues (Stuck On)

1. **C Backend Compilation Corrupts the Source/Hangs**
   - Emitting C code for `backend_compare.sage` (e.g., `sage --compile testsuite/benchmarks/backend_compare.sage -o .tmp_bench -O3`) generates a binary that hangs indefinitely or is killed by the OOM killer (`Killed`).
   - Investigating the raw C output occasionally shows binary corruption or stray null bytes (`stray ‘\211’ in program`) when compiling `compiler.c` using the new `SAGE_ADD`/`SAGE_SUB` fast-path macros, suggesting a buffer overflow, misaligned pointer, or deep recursive inline macro loop during code generation. 
   - `for_loop.sage` succeeds without hanging, implying the infinite loop/hanging behavior is specific to deep recursion (Fibonacci) or something the `backend_compare.sage` does.

## Next Steps

1. **Debug C-Compiled Backend Hang**
   - Isolate which benchmark loop in `backend_compare.sage` is hanging when compiled to C.
   - Audit the `SAGE_ADD`/`SAGE_SUB` macro definitions in the emitted C code for any unintentional recursive loop when handling `sage_load_slot` vs `sage_assign_slot`.
2. **Fix Remaining Backend/Codegen Issues**
   - Ensure the `for_loop` semantic removal (`Mutation Fix`) correctly evaluates array elements in the Bytecode VM and C codegen.
3. **Self-Hosted VM (`sgvm_vm.sage`)**
   - Implement the planned flat-array slot variables for `MetalVM` local scopes to bypass dictionary lookups.