# SageLang Updates

## March 9, 2026 - Phase 11 Complete: Concurrency & Parallelism

Phase 11 brings threading, async/await, native standard library modules, and expanded compiler backends.

### Native Standard Library Modules

- **`math` module** - `sqrt`, `sin`, `cos`, `tan`, `floor`, `ceil`, `abs`, `pow`, `log`, `pi`, `e`
- **`io` module** - `readfile`, `writefile`, `appendfile`, `exists`, `remove`, `rename`
- **`string` module** - `char`, `ord`, `startswith`, `endswith`, `contains`, `repeat`, `reverse`
- **`sys` module** - `args`, `exit`, `platform`, `version`, `env`, `setenv`
- Native module infrastructure: `create_native_module()` pre-loads modules into cache before file resolution

### Thread Module

- **`thread.spawn(proc, args...)`** - Spawn a new thread running a procedure with pre-evaluated arguments
- **`thread.join(t)`** - Wait for thread completion and return its result
- **`thread.mutex()`** - Create a mutex for synchronization
- **`thread.lock(m)` / `thread.unlock(m)`** - Lock and unlock mutexes
- **`thread.sleep(ms)`** - Sleep for milliseconds
- **`thread.id()`** - Get current thread identifier
- **GC thread safety** - Garbage collector protected with pthread mutex

### Async/Await

- **`async proc` syntax** - Declares an asynchronous procedure (sets `is_async` flag on FunctionValue)
- **`await` expression** - Joins async thread and retrieves the return value
- Calling an async proc automatically spawns a background thread via `thread_spawn_native`
- New AST nodes: `STMT_ASYNC_PROC`, `EXPR_AWAIT`
- Lexer: `async` and `await` keywords
- All compiler passes updated: pass.c, constfold.c, dce.c, inline.c, typecheck.c

### LLVM Backend Expansion

- Dictionary literals, tuple literals, slice expressions
- Property access (`EXPR_GET`) and property assignment (`EXPR_SET`)
- `for...in` loops using `sage_rt_array_len` + counter + `sage_rt_index`
- `break` and `continue` with loop label stack (`loop_cond_labels[]`, `loop_end_labels[]`, `loop_depth`)
- 11 new runtime function declarations (dict, tuple, slice, get/set, array_len, range)

### Native Codegen Expansion

- `for...in` loops using `VINST_CALL_BUILTIN("len")` + counter + `VINST_INDEX`
- `break` and `continue` with loop label stack in `ISelContext`
- Updated `STMT_WHILE` to push/pop loop labels

### Files Modified

- `src/stdlib.c` - Thread module functions, native module infrastructure
- `src/module.c` - `register_stdlib_modules()`, `create_native_module()`
- `include/module.h` - Thread module declaration
- `include/token.h` - `TOKEN_ASYNC`, `TOKEN_AWAIT`
- `include/ast.h` - `AwaitExpr`, `EXPR_AWAIT`, `STMT_ASYNC_PROC`
- `src/ast.c` - Constructors and free functions for new nodes
- `src/lexer.c` - `async`/`await` keyword recognition
- `src/parser.c` - `async_proc_declaration()`, `await` in `unary()`
- `include/value.h` - `is_async` field on FunctionValue
- `src/value.c` - Initialize `is_async = 0`
- `src/interpreter.c` - Async proc execution, await joining, thread spawning
- `src/llvm_backend.c` - Loop labels, dict/tuple/slice/get/set/for-in/break/continue
- `include/codegen.h` - Loop label stack in ISelContext
- `src/codegen.c` - For-in loops, break/continue with loop labels
- `src/pass.c`, `src/constfold.c`, `src/dce.c`, `src/inline.c`, `src/typecheck.c`, `src/compiler.c` - New node handling

### Test Suite

- 4 new tests in `tests/27_threads/`: basic spawn, thread args, mutex, thread ID
- 3 new tests in `tests/28_async/`: basic async, async args, async parallel
- 5 new tests in `tests/26_stdlib/`: math, io, string, sys modules
- Total: 112 interpreter tests across 28 categories + 24 compiler tests, all passing

---

## March 9, 2026 - Phase 10 Complete: Compiler Development

Full compiler pipeline with three backends: C codegen, LLVM IR, and native assembly.

- C backend: complete coverage of all language features (classes, modules, exceptions, builtins)
- LLVM IR backend: `--emit-llvm` / `--compile-llvm` with runtime declarations
- Native assembly backend: `--emit-asm` / `--compile-native` for x86-64, aarch64, rv64
- Optimization passes: type checking (`-O1+`), constant folding (`-O1+`), dead code elimination (`-O2+`), function inlining (`-O3`)
- Debug information: `-g` flag
- 24 compiler tests, all passing

---

## March 8, 2026 - Phase 9 Complete: Low-Level Programming

Phase 9 is now complete with all 5 sub-features implemented.

### Phase 9.5: C Struct Interop

- **`struct_def(fields)`**: Define C struct layout from `["name", "type"]` pairs with proper alignment
- **`struct_new(def)`**: Allocate zeroed struct instance
- **`struct_get(ptr, def, field)`** / **`struct_set(ptr, def, field, val)`**: Read/write fields
- **`struct_size(def)`**: Get total struct size (including padding)
- Types: `"char"`, `"byte"`, `"short"`, `"int"`, `"long"`, `"float"`, `"double"`, `"ptr"`
- Proper C ABI alignment: each field aligned to natural boundary, tail padding to max alignment
- 4 new tests in `tests/25_structs/`
- Total: 100 tests across 25 categories, all passing

---

## March 8, 2026 - Phase 9.4: Inline Assembly (Multi-Architecture)

SageLang can now compile and execute raw assembly code, with support for x86-64, aarch64, and RISC-V 64 architectures.

### Assembly Functions

- **`asm_exec(code, ret_type, ...args)`**: Compile and execute assembly on the host architecture. Return types: `"int"`, `"double"`, `"void"`. Up to 4 numeric arguments passed via ABI registers.
- **`asm_compile(code, arch, output_path)`**: Cross-compile assembly to an object file. Architectures: `"x86_64"`, `"aarch64"`, `"rv64"`.
- **`asm_arch()`**: Returns the host architecture name (e.g., `"x86_64"`)

### Implementation Details

- Assembly is compiled via temp files: `.s` → `as` → `.o` → `gcc -shared` → `.so` → `dlopen`/`dlsym`
- Escape sequences `\n` and `\t` processed in code strings (since SageLang strings are raw)
- Cross-compilation uses `aarch64-linux-gnu-as` / `riscv64-linux-gnu-as` toolchains
- System V ABI calling convention: integer args in rdi/rsi/rdx/rcx (x86-64), x0-x3 (aarch64), a0-a3 (rv64)
- Double args passed via xmm0-3 (x86-64), d0-3 (aarch64), fa0-3 (rv64)
- Temp files cleaned up after execution

### Files Modified

- `src/interpreter.c` — `asm_exec`, `asm_compile`, `asm_arch` native functions with multi-arch support

### Test Suite

- 5 new tests in `tests/24_assembly/`: basic ops, arguments, doubles, arch detection, cross-compilation
- Total: 96 tests across 24 categories, all passing

---

## March 8, 2026 - Phase 9.3: Raw Memory Operations

SageLang now supports direct memory allocation, reading, and writing for low-level programming.

### Memory Functions

- **`mem_alloc(size)`**: Allocate zero-initialized raw memory (up to 64MB), returns a pointer value
- **`mem_free(ptr)`**: Free allocated memory and invalidate the pointer
- **`mem_read(ptr, offset, type)`**: Read a value at ptr+offset. Types: `"byte"`, `"int"`, `"double"`, `"string"`
- **`mem_write(ptr, offset, type, val)`**: Write a value at ptr+offset. Types: `"byte"`, `"int"`, `"double"`
- **`mem_size(ptr)`**: Get the size of an allocation
- **`addressof(val)`**: Get the memory address of any value (as a number)

### Implementation Details

- New `VAL_POINTER` value type with `PointerValue` struct tracking raw pointer, size, and ownership
- Bounds checking prevents reads/writes past the end of owned allocations
- Memory is zero-initialized via `calloc` for safety
- Allocation capped at 64MB to prevent abuse
- `mem_free` invalidates the pointer (sets to NULL) to prevent use-after-free

### Files Modified

- `include/value.h` — `PointerValue` struct, `VAL_POINTER` enum, macros, constructor
- `src/value.c` — `val_pointer()` constructor, print/equality support
- `src/interpreter.c` — 6 memory native functions registered in `init_stdlib()`

### Test Suite

- 5 new tests in `tests/23_memory/`: alloc/free, byte ops, int/double ops, addressof, byte buffer
- Total: 91 tests across 23 categories, all passing

---

## March 8, 2026 - Phase 9.2: Foreign Function Interface (FFI)

SageLang can now call functions in shared C libraries via `dlopen`/`dlsym`.

### FFI Functions

- **`ffi_open(path)`**: Open a shared library (`.so`/`.dylib`/`.dll`), returns a library handle
- **`ffi_call(lib, func, ret_type, ...args)`**: Call a function in the library. `ret_type` is `"double"`, `"int"`, `"long"`, `"string"`, or `"void"`
- **`ffi_sym(lib, name)`**: Check if a symbol exists in the library (returns `true`/`false`)
- **`ffi_close(lib)`**: Close the library handle

### Implementation Details

- New `VAL_CLIB` value type wraps `dlopen` handle and library name
- `ffi_call` supports 0–3 arguments, with numeric and string argument types
- Uses `#pragma GCC diagnostic` to safely cast `void*` to function pointers (POSIX-guaranteed)
- Added `-ldl` to linker flags

### Files Modified

- `include/value.h` — `CLibValue` struct, `VAL_CLIB` enum, macros, constructor
- `src/value.c` — `val_clib()` constructor, print/equality support
- `src/interpreter.c` — 4 FFI native functions registered in `init_stdlib()`
- `Makefile` — `-ldl` added to `LDFLAGS`

### Test Suite

- 3 new tests in `tests/22_ffi/`: math library calls, libc string functions, symbol checking
- Total: 86 tests across 22 categories, all passing

---

## March 8, 2026 - Phase 9: Bitwise Operators (First Low-Level Feature)

The first feature of Phase 9 (Low-Level Programming): full bitwise operator support.

### Bitwise Operators

- **`&` (AND)**: Integer bitwise AND — `5 & 3` → `1`
- **`|` (OR)**: Integer bitwise OR — `5 | 3` → `7`
- **`^` (XOR)**: Integer bitwise XOR — `5 ^ 3` → `6`
- **`~` (NOT)**: Integer bitwise complement — `~0` → `-1`
- **`<<` (Left Shift)**: Shift bits left — `1 << 4` → `16`
- **`>>` (Right Shift)**: Shift bits right — `16 >> 2` → `4`

### Implementation Details

- Operators work on integer values (doubles truncated to `long long` for bitwise ops)
- Correct C-style operator precedence: `~` (unary) → `<<`/`>>` → `&` → `^` → `|` → `and`/`or`
- Unary `~` handled at same precedence level as unary `-` and `not`

### Files Modified

- `include/token.h` — New tokens: `TOKEN_AMP`, `TOKEN_PIPE`, `TOKEN_CARET`, `TOKEN_TILDE`, `TOKEN_LSHIFT`, `TOKEN_RSHIFT`
- `src/lexer.c` — Lex `&`, `|`, `^`, `~`, `<<`, `>>`; updated `<`/`>` to check for shift first
- `src/parser.c` — New precedence levels: `shift()`, `bitwise_and()`, `bitwise_xor()`, `bitwise_or()`; unary `~` in `unary()`
- `src/interpreter.c` — Evaluate all 6 bitwise operators in `eval_binary()`

### Test Suite

- 6 new tests in `tests/21_bitwise/`: AND, OR, XOR, NOT, shifts, combined operations
- Total: 83 tests across 21 categories, all passing

---

## March 8, 2026 - Phase 8.5: Security & Performance Hardening

A comprehensive audit and hardening pass across the entire interpreter codebase, plus completion of the Phase 8 module system.

### Security Fixes

- **Recursion depth limits**: Interpreter capped at 1000 frames, parser at 500 nesting levels. Exceeding limits raises a clean exception instead of crashing.
- **OOM safety**: All `malloc`/`realloc` calls replaced with `SAGE_ALLOC`/`SAGE_REALLOC` wrappers that abort with a diagnostic message on failure. No code path can dereference a NULL allocation.
- **GC pinning**: New `gc_pin()`/`gc_unpin()` API prevents garbage collection during multi-step allocations (e.g., `instance_create`, `class_create`), fixing a class of use-after-free bugs.
- **Module path traversal**: Module names are validated to reject `/`, `\`, and `..`. Resolved paths are checked with `realpath()` to ensure they stay within search directories.
- **Iterative lexer**: `scan_token()` converted from recursive to iterative, eliminating potential stack overflow on files with many consecutive blank lines or comments.

### Performance Improvements

- **Hash table dictionaries**: Dictionaries rewritten from O(n) linear scan to O(1) amortized hash table using FNV-1a hashing, open-addressing with linear probing, 75% load factor growth, and backward-shift deletion.
- **O(n) string operations**: `string_join()` and `string_replace()` rewritten with write-pointer approach, replacing O(n^2) repeated `strcat`/`memmove`.
- **`size_t` string lengths**: String length calculations use `size_t` instead of `int` to prevent overflow on large strings.
- **Environment GC integration**: Environments now participate in mark-and-sweep GC via an `int marked` flag on `Env`, replacing the O(n^2) `MarkedEnv` linked list with O(1) mark checks. Unreachable environments are freed during GC sweep instead of only at shutdown.

### Module System (Phase 8 Completion)

- All three import forms fully working: `import mod`, `import mod as alias`, `from mod import x, y`
- `from mod import x as alias` supported
- Module attribute access via dot notation (`mod.value`, `mod.func()`)
- Circular dependency detection via `is_loading` flag
- Module caching prevents redundant loads

### Test Suite

- New `tests/` directory with 77 automated tests across 20 categories
- Bash test runner (`tests/run_tests.sh`) with `# EXPECT:` and `# EXPECT_ERROR:` patterns
- Categories: variables, arithmetic, comparison, logical, strings, control flow, loops, functions, arrays, dicts, tuples, classes, inheritance, exceptions, generators, modules, closures, builtins, edge cases, GC
- All 77 tests passing

### Files Modified

- `include/gc.h` - Safe allocation macros, pin API
- `include/value.h` - DictEntry hash field for hash table
- `include/env.h` - `int marked` flag, `env_sweep_unmarked()`, `env_clear_marks()`
- `src/gc.c` - Pin support, dict hash table iteration, env sweep integration, O(1) env marking
- `src/value.c` - Hash table dict ops, GC pinning in allocators, O(n) string ops, size_t lengths
- `src/interpreter.c` - Recursion depth counter, safe allocations, size_t string concat
- `src/parser.c` - Parser depth counter, safe allocations
- `src/lexer.c` - Iterative scan_token loop
- `src/module.c` - Path validation, realpath containment, safe allocations
- `src/env.c` - Marked flag init, sweep/clear functions, safe allocations
- `src/main.c` - ftell error check, safe allocations

---

## December 28, 2025 - Phase 8: Module System (60%)

- Added function closure support to FunctionValue struct
- Module infrastructure: parsing, loading, caching
- Search path system for module resolution

## November 29, 2025 - Phase 7: Advanced Control Flow (100%)

- Generators with yield/next fully working
- Exception handling: try/catch/finally/raise
- Loop control: for-in, break, continue

## November 28, 2025 - Phase 6: Object-Oriented Programming (100%)

- Classes with init, methods, self binding
- Single inheritance with method overriding
- Property access and assignment

## November 27, 2025 - Phase 5: Advanced Data Structures (100%)

- Arrays, dictionaries, tuples
- Array slicing, string methods
- 20+ native functions added

## November 27, 2025 - Phase 4: Garbage Collection (100%)

- Mark-and-sweep GC with configurable threshold
- gc_collect(), gc_stats(), gc_enable(), gc_disable()
