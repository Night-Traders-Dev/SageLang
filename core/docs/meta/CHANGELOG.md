# Changelog

All notable changes to SageLang are documented in this file, newest first.

Versions are assigned monotonically by release date. Releases prior to the
v3.0.0 stability baseline (2026-03-01) are numbered `0.x` by development phase.
The `sagemake` build tool excludes this file (and `ROADMAP.md`) from version
propagation so the per-entry version history is never flattened again.

---

## [4.0.7] - 2026-07-15

### JIT Compiler Command & Self-Extracting Runner
- **Command support**: Allowed compiling a binary using `sage --jit hello.sage -o hello_jit` directly, matching other compilation modes.
- **Self-extracting runner**: Fixed the self-extracting JIT executable runner to execute the embedded script payload rather than starting the REPL.

---

## [4.0.6] - 2026-07-15

### AOT & Compiler Fixes
- **Memory safety**: Resolved buffer overflows and global scope issues in the AOT (Ahead-of-Time) compiler.
- **Built-in functions**: Added missing string and array built-in implementations (`s_replace`, `s_clock`, `s_split`, `s_ord`, `s_chr`, `s_join`) to the AOT backend.
- **Combined JIT-AOT**: Perfected JIT-guided AOT (`sage --aot --jit <file>`).
- **Cross-compilation**: Added full cross-compilation support via GCC cross-compilers.

---

## [4.0.5] - 2026-07-12

### Version Bump
- Bumped SageLang version to 4.0.5 across the codebase.

---

## [4.0.4] - 2026-07-12

### Standard Library & Hardening
- **`crypto.hmac`**: Resolved $O(N^2)$ Algorithmic Complexity DoS vulnerability (CWE-400) in `to_hex` by refactoring it to collect hex characters in an array and run `join` once in $O(N)$ linear time.
- **`crypto` auditing**: Confirmed all other core crypto functions (`to_hex` in `hash.sage` & `password.sage`, `split_colon`, `random_string`, and `uuid4`) are utilizing the $O(N)$ linear-time array-and-join pattern to prevent resource exhaustion attacks.

### Parser & Core
- **Multi-line assignments**: Fixed multiple parser/compiler errors caused by multi-line let statements without parentheses or line continuations (e.g. in `hash.sage` and `rand.sage`). All assignments were refactored to single-line declarations.

### Testing
- **`sys_info` unit test**: Converted `sys_info.sage` to dynamically load the version string from the project's single-source `VERSION` file, making the test fully version-independent and preventing future version-bump test failures.

---

## [4.0.3] - 2026-07-07

### Standard Library
- **`io.writebytes` / `io.appendbytes`**: Now accept `Bytes` values in addition to `Array`, enabling native binary I/O with the `Bytes` type.
- **`io.readbytes`**: Now returns a `Bytes` value instead of an `Array`, matching the documented behavior.
- **`value.h`**: Added `IS_BYTES(v)` and `AS_BYTES(v)` macros for consistent type checking and access of `Bytes` values.

### Parser
- **Qualified type annotations**: `parse_type_annotation()` now consumes dotted names (`module.Type`), enabling `let fs: vfs.VFS = vfs.VFS(dev)` syntax.

---

## [4.0.2] - 2026-07-05

### Install System — OIS v2.0 Overhaul
- **CMake-first build**: Default build system is CMake with `-DBUILD_SAGE=ON` (self-hosted mode); falls back to Make if CMake is unavailable. Override with `--cmake` or `--make` flags.
- **`make -C core install` always**: Installation always uses the Makefile install target (matching sagemake behavior), since CMake with `-DBUILD_SAGE=ON` defines no install targets. CMake-built binaries are copied from `core/build_sage/` first to avoid a redundant rebuild.
- **Library exclusion**: New `--no-lib-<name>` flags (e.g. `--no-lib-ml`, `--no-lib-cuda`, `--no-lib-blockchain`) remove specific lib subdirectories post-install. `--minimal` excludes all optional libs (`blockchain`, `graphics`, `os`, `net`, `crypto`, `ml`, `cuda`, `llm`, `agent`, `chat`, `android`, `transpiler`, `metal`, `rich`) plus `VULKAN=0 SAGE_NO_NET=1`.
- **Shader control**: `--no-shaders` skips GLSL→SPIR-V compilation for all 43 shader modules.
- **Feature flags**: `--no-vulkan`, `--no-gpu`, `--no-curl`, `--no-ssl` wire the corresponding Makefile variables (`VULKAN=0`, `SAGE_NO_NET=1`).
- **System-scope only**: Removed all user-scope (non-sudo) install paths. OIS now always installs to `/usr/local` with `sudo`.
- **POSIX-sh compliance**: All shell scripts pass `bash -n` syntax check. Removed `updater.sh` as redundant.
- **Non-interactive mode**: `--yes` / `-y` flag for unattended installs.

---

## [4.0.1] - 2026-07-15

### Hardening & Security
- **Binary-safe I/O**: Refactored `net.c` and `stdlib.c` to use `val_string_take_len`, ensuring binary-safe handling of strings containing null bytes in `tcp_recv`, `io_readfile`, and `sys_shell_exec`.
- **Resource Limits**: Enforced a global `SAGE_MAX_READ_SIZE` (100MB) limit across all I/O and networking modules to mitigate memory exhaustion DoS attacks (CWE-400).
- **Algorithmic Complexity DoS (ReDoS) Mitigation**: Optimized `net.url` and `agent.sandbox` by replacing $O(N^2)$ string concatenation with linear-time patterns (array-push + `join()`, `slice()`), resulting in up to 3000x speedup for large inputs.
- **Compiler Security**: Added bounds checks for constant pool allocations and SGVM chunk limits in `main.c` and `sgvm_compiler.c`.

### API & Standard Library
- **New Native Built-ins**: Added `int()` (truncation), `array_repeat()`, `string_count()`, `string_repeat()`, and `addressof_raw()` to the core language.
- **Memory API Refinement**: `mem_read` and `mem_write` now require a type string argument ("byte", "int", "double", "string") for explicit width control and bounds checking.
- **Networking**: Hardened `tcp_send` and `tcp_sendall` to be length-aware, using `SAGE_STRING_LEN()` instead of `strlen()`.

### Performance
- **Property Access Optimization**: Implemented length-aware dictionary and instance field lookups, bypassing temporary allocations during property resolution.
- **Iterator Speedup**: Converted `take` and `nth` in `core/lib/iter.sage` to use `for` loops, yielding ~2x performance gains.

---

## [4.0.0] - 2026-07-02

### Self-Hosted Toolchain Parity
- **`sage.sage` — debug print cleanup**: Removed five stray diagnostic `print` statements from `mode_run` (`"mode_run: parsing..."`, `"mode_run: parsing done. optimizing..."`, `"mode_run: setting error context..."`, `"mode_run: exec_program..."`, `"mode_run: done."`). These polluted stdout on every interpreter invocation. The function is otherwise unchanged: parse → optional optimization passes → set error context → new interpreter → exec.
- **`net.sage` — new self-hosted net stub module**: The C backend (`net.c`) provides full BSD-socket networking (TCP, UDP, `connect`, `bind`, `listen`, `accept`, `send`, `recv`, `sendto`, `recvfrom`, hostname resolution, non-blocking mode, `SO_REUSEADDR`, high-level `tcp_connect`/`tcp_listen`). No self-hosted counterpart existed, meaning `import net` would fail under the interpreter. `net.sage` now mirrors every public symbol in `net.c` exactly — returning `NET_UNAVAILABLE` (-1) or `nil` with an explanatory `net_strerror()` message — so the self-hosted and C-backend module APIs are identical. Exposes `create_net_module()` for registration by `stdlib.sage`.
- **`stdlib.sage` — merge conflict resolved**: `create_sys_module` contained an unresolved three-way merge conflict (`<<<<<<< HEAD` / `=======` / `>>>>>>>`). The conflict is resolved: version is `"3"` (consistent with `sage.sage`'s `VERSION` constant), platform is `"sage-self-hosted"`, and all sys procs (`args`, `exit`, `getenv`, `clock`, `sleep`, `exec`, `shell_exec`, `call`) are wired into the module dict.
- **`stdlib.sage` — net module registered**: `import net` added to the module header; a thin `create_net_module()` wrapper delegates to `net.create_net_module()`; `g_stdlib_registry["net"]` is now populated in `init_stdlib()` so any self-hosted Sage code using `import net` gets the parity stub rather than a module-lookup failure.

---

## [3.9.8] - 2026-06-29
- **Anonymous `proc` expressions (proc literals)**: Inline procs can now be passed as arguments to higher-order functions: `signal.once(bus, "event", proc(data): print data end)`. Supports both single-line (`proc(x): body end`) and multi-line block bodies. Closures capture the enclosing environment. `EXPR_PROC` added to the AST, parser, and self-hosted interpreter.

## [3.9.7] - 2026-06-29
- **Lily Transpiler**: `--compile-to-lily` / `--compile-from-lily` CLI flags for round-trip Sage ↔ Lily transpilation via the `transpiler.lily` submodule.
- **Linux signals**: Added missing POSIX signal constants and stubs to `linux/syscalls.sage`; enhanced signal handling.
- **Sentinel DoS mitigation**: Bounded O(N) crypto and file operations to prevent resource-exhaustion attacks.
- **net.url optimization**: Replaced allocation-heavy patterns with `slice()`/`join()` for faster URL parsing.
- **metal_vm**: `MV_NUM` now uses `int64_t` Q32.32 fixed-point under `SAGE_BARE_METAL` (`mv_num_fp`), dropping the `double`/FPU dependency for rv64 freestanding targets.
- **C sgvm_compiler**: Fixed `#` comment handling in the C-based SGVM compiler.

## [3.9.6] - 2026-06-28
- **CLI**: Added `--compile-to-lily` and `--compile-from-lily` flags.
- **metal_vm**: Q32.32 fixed-point number support for bare-metal RV64 (see 3.9.7).
- **Submodule**: Integrated completed `SageToLilyTranspiler` and Lily frontend stubs.

## [3.9.5] - 2026-06-28
- **Binary-safe I/O**: Hardened binary safety across standard library I/O and networking modules.
- **Networking**: Centralized resource limits and fixed multiple-definition error for net modules when `SAGE_NO_NET` is defined.
- **POSIX signals**: Enhanced signal support in `os.linux.syscalls`.

## [3.9.0] - 2026-06-26
- **C backend FFI**: Full FFI support for `--compile` mode (conditioned to desktop targets only).
- **ffi**: Added `int`-arg variant for string return type in compiled FFI.
- **Sentinel**: Fixed resource exhaustion in I/O and shell execution.
- **Compiler**: Added package directory (`__init__.sage`) support to `resolve_module_path_for_compiler`.
- **Rich**: Added `sagelang-lib-rich` submodule (Panel/Table rendering) to build pipeline.

## [3.8.7] - 2026-06-26
- **One-line Install System (OIS)**: Integrated OIS installer for seamless building and dependency management across Linux, macOS, FreeBSD, and WSL2.
- **REPL**: Added `:stats` command for real-time GC and memory monitoring; hardened REPL path validation to prevent unauthorized access.
- **C Codegen Primitives**: Added native support for FFI, atomic operations, and POSIX semaphores in the C backend.
- **$O(1)$ Dictionary Lookups**: Constant-time size lookups for dictionaries.
- **Native Array Reversal**: Replaced interpreted loops with a native C implementation (~105x speedup).
- **Structural Equality in Search**: `array_contains` and `array_index_of` use structural equality for class instances via native code.
- **String Length Optimization**: $O(1)$ string length retrieval by caching sizes in the GC header.
- **Sandbox Guards**: Hardened tab/whitespace token checks in the security sandbox to prevent bypasses.
- **Path Validation**: Improved path sanitization in the core interpreter and REPL.
- **Keywords**: `super` and `end` added to the Guide Quick Reference.

## [3.8.6] - 2026-06-22
- **Extend FFI argument type patterns**: Support for `int`, `long`, and `void` return types in FFI argument type patterns.
- **C compile backend fixes**: Pad default params with `nil` in `--compile` mode; fix native module name matching (`math` vs `_math`).
- **Tooling**: `sagemake` excludes meta documentation files (`CHANGELOG.md`, `ROADMAP.md`) from version propagation to prevent version history flattening.
- **Bugfixes**: 28 memory-safety, concurrency, and correctness fixes.

## [3.8.5] - 2026-06-21
- **Bitwise shift fixes**: `>>` and `<<` now use unsigned arithmetic throughout all backends (interpreter, compiler C codegen, AOT, LLVM, bytecode VM), fixing sign-extension on values ≥ 2⁶³ and negative overflow from `<<`.
- **Array concatenation (`+`)**: `[1,2] + [3,4]` now returns `[1,2,3,4]` instead of `nil` in the interpreter, C codegen runtime, and bytecode VM.
- **`range(start, end, step)`**: The `range` builtin now accepts 3 arguments with positive and negative step support (`sage_range3` C codegen helper).
- **`io.readbytes` non-seekable file support**: `/dev/urandom` and other non-seekable files read correctly via chunked reads when `fseek` fails (interpreter stdlib, C codegen runtime, LLVM runtime).
- **`math.printm()`**: Matrix printing across Sage, C, and Assembly backends (x86_64, aarch64, rv64).
- **`--math-work`**: CLI flag for configuring math execution modes.

## [3.8.4] - 2026-06-18
- **MIPS Target Support**: Backend compiler and assembly generation for MIPS 74K / BCM5357 (O32 ABI compliant code generation, ELF output, target parsing for `--target mips / mips32 / mips74k`).
- **MIPS Assembly Generator**: `emit_asm_vinst_mips` with full support for loading float/double constants, globals, printing, arithmetic, branching, jumps, and builtin calls. Freestanding ELF writer updated with `EM_MIPS` (0x08).
- **MIPS Library Submodule**: Created `sagelang-lib-mips` under `core/lib/mips` with `README.md`, `CONTRIBUTING.md`, register configuration mappings, and integration tests.

## [3.8.3] - 2026-06-17
- **Standard Library Overhaul**: `__init__.sage` support for directory-based packages, allowing cleaner imports like `import blockchain` instead of full paths.
- **Library Stabilization**: Fixed hundreds of syntax errors (missing colons, outdated `end` keywords) across the entire standard library (`std`, `net`, `os`, `crypto`, `ml`, `llm`, `metal`, `graphics`, `agent`).
- **Modularization**: Refactored core libraries into standalone repositories managed by Git submodules.
- **Benchmarks**: Refreshed benchmark charts and metrics.

## [3.8.2] - 2026-06-16
- **General Improvements**: Various performance and stability improvements across backends.

## [3.8.1] - 2026-06-14
- **Circular Imports**: Partial module loads in `module.c`; circular dependencies resolve via access to partially initialized state.
- **Full `super` Support**: `EXPR_SUPER` in C and LLVM backends; compiled binaries support proper inheritance and parent method calls. Optional explicit `self` in `super.init(self, args)`.
- **`end` Soft Keyword**: `end` can be used as an identifier/variable name while still acting as a block terminator.
- **Modulo Float Support**: Self-hosted compiler uses `fmod()` for `%`, preserving floating-point semantics across all runtimes.
- **String Interning**: Global string interning table in the runtime and GC, reducing memory usage for duplicate strings.
- **AST "Quickened" Nodes**: Self-optimizing interpreter nodes that cache type information and use fast paths for numeric operations.
- **Loop Mutation**: Loop variable mutation across all backends; modifying the loop variable affects the iteration count.
- **C Backend Scoping**: Fixed module-level `let` variables not marked as GC roots in C-compiled binaries.
- **Native Builtin Expansion**: `int()`, `abs()`, `sqrt()` math primitives plus `ffi_*`, `atomic_*`, `sem_*` concurrency builtins. Expanded `SageTag`/`SageValue` for `CLIB`, `POINTER`, `THREAD`, `MUTEX`, `FUNCTION`. Fixed top-level function-reference loading.
- **VM Optimization**: Threaded dispatch (computed gotos), register-backed stack pointer, cached IP/bytecode/constant-pool pointers.
- **Native VM OOP**: `BC_OP_CLASS`, `BC_OP_METHOD`, `BC_OP_INHERIT`, `BC_OP_GET_PROPERTY`, `BC_OP_SET_PROPERTY` natively in the VM (no AST fallback).
- **Native VM Exceptions**: `BC_OP_SETUP_TRY`, `BC_OP_END_TRY`, `BC_OP_RAISE` with VM-maintained exception handler stack.
- **Native VM Imports**: `BC_OP_IMPORT` for native module loading/linking.
- **Self-Hosted VM Toolchain**: `sgvmc.sage` (SGVM compiler) and `sgvm.sage` (MetalVM runner) ported to pure SageLang.
- **Verbose flag**: `--verbose` / `-v` gates internal compiler diagnostics.

## [3.8.0] - 2026-06-09
- **`sys.call`**: Dynamic native/closure invocation.
- **MetalVM Opcode Parity**: Full opcode parity (OOP, Exceptions, GPU) in MetalVM.
- **SGVM Self-Hosting (in progress)**: SGVM backend refactoring to emit binary `.sgvm` artifacts directly; standalone toolchain portability work.
- **memfs_rmdir fix**: `vfs_rmdir` no longer allows removing non-empty directories constructed via `memfs_write`.

## [3.7.9] - 2026-06-09
- **REPL `:stats`**: Real-time GC (mode, collections, objects, pauses), memory usage (live bytes, total allocated), interpreter stack depth, and process CPU time.

## [3.7.0] - 2026-06-08
- **Interpreter search path**: Hardened search path logic (duplicate-path prevention, budget increased to 64).
- **MetalVM native bridging**: High-performance native bridging for SageMetal VM (Math, IO, Sys, Regex).

## [3.6.0] - 2026-06-05
- **Interpreter hardening**: Search path hardening and MetalVM native bridging foundations.

## [3.5.1] - 2026-05-29
- **Hotfix**: Restored `errno.strerror` documentation — fixed detached/misformatted comment that prevented `proc strerror` from being recognized as documented (`# #` → `##`, removed blank line for adjacency; satisfies linter S003 and restores `doc(errno.strerror)`).

## [3.5.0] - 2026-05-29
- **Security**: Sandbox security guards and structural uniqueness checks.
- **Structural value equality in `unique`**: Refactored `unique(values)` in `arrays.sage` to resolve colliding composite string representations (e.g. dictionaries stringifying to `"<dict>"`) using fallback lists and structural `==` checks.
- **Safe non-hanging repeating**: Fixed memory corruption and hangs in `strings.repeat` and `repeat_value` by cloning arrays prior to extension (no unsafe aliasing).
- **Whitespace safety in sandbox module guards**: Token-level lexical helper `is_import_token_present` detects any whitespace separators (including `\t`) while ignoring comments and string literals.

## [3.4.4] - 2026-05-20
- **Hotfix**: Critical `mutex_lock` bug — incorrectly called `metal.core.io_wait()` instead of the bound name `core` under contention. Ensures mutex stability on bare-metal/simulation targets.

## [3.4.3] - 2026-05-15
- **Self-Hosted Compiler Parity**: `parse_struct` in the self-hosted parser (C-style value types in pure Sage); synchronized self-hosted AST with C backend additions (Async, Structs, Advanced Imports).
- **Documentation Refactoring**: Major SageLang Book and system guides update for the 3.4.x architecture.
- **Concurrency refinement**: Validated `sage_thread.c` for platform-agnostic threading (pthreads on desktop/Android, safe stubs on RP2040); GC safety via Thread Registry and stack-root protection; refined `EXPR_AWAIT` and `STMT_ASYNC_PROC`.

## [3.4.2] - 2026-05-10
- **REPL Expansion**: `:doc <name>`, `:edit [file]`, `:ls [dir]`, `:cat <file>`, `:sh <command>`, `:search <pattern>`, `:clear-history`.
- **Type Checker**: Return type tracking and validation against `return` statements.
- **Linter**: S003 (missing docstring) and S005 (multiple statements per line) rules.
- **LSP**: `textDocument/hover` provides documentation for user-defined procedures via docstrings; unified `g_hover_docs` in `diagnostic.c` as single source of truth across REPL, LSP, and compiler diagnostics.

## [3.4.1] - 2026-05-07
- **Performance**: Length-aware dictionary lookups and direct token pointers in method dispatch (~15% speedup).

## [3.4.0] - 2026-05-05
- **AOT Compiler Security**: Replaced fixed 4096-byte buffers in `aot_emit` with dynamic allocation; pre-calculated string lengths for `CALL`, `ARRAY`, `DICT`, `TUPLE`; strict OOM checks.
- **Interpreter Memory Protection**: `AST_GC_PUSH/POP` and `AST_GC_PUSH_ENV/POP_ENV` protect intermediate values/environments; GC root pointers moved to thread-local (`__thread`) storage; Thread Registry for safe root marking during concurrent GC.
- **Inline Caching**: ~27% speedup on loop-heavy benchmarks via inline caching for `EXPR_VARIABLE` and `EXPR_SET`.
- **Graphics Security**: Fixed predictable temp filename vulnerability (CWE-377) via `mkstemps`.
- **Gas Metering**: `vm_gas_limit_set`, `vm_gas_used_get`, `vm_gas_limit_get`.
- **Discord Bot Library**: Core support and documentation for the `discord` library suite.
- **IRQ Management**: Safe double-registration guards and nested interrupt depth tracking in `lib/metal/irq.sage`.
- **Blockchain**: Enhanced staking smart contract robustness; `VAL_VM_PROGRAM` type for stable bytecode compilation/distribution.
- **Sentinel security & performance refinement** across AOT and interpreter.

## [3.3.0] - 2026-04-20
- **Kotlin/Android Backend** (`--emit-kotlin`, `--compile-android`):
  - Generators (`yield` → Kotlin `sequence { yield() }`, `Sequence<SageVal>`), async/await (`suspend fun`, `kotlinx.coroutines`), native `super.method()` dispatch, FFI/memory (`ByteBuffer.allocateDirect`, `System.loadLibrary`), type specialization (`-O2+` emits native `Double`/`String`/`Boolean`), Jetpack Compose codegen (`import android.compose`).
  - Full expression/statement/control-flow transpilation; classes with inheritance; pattern matching (`match`/`case` → `when`); exceptions; collections; structs → `data class`, enums → `enum class`, traits → `interface`; optimization passes `-O1`–`-O3`.
  - Android project generator: transpiled Kotlin, `SageRuntime.kt`, `AndroidManifest.xml`, `build.gradle.kts`, Material 3 theming, AppCompat, Internet permission; `MainActivity` captures Sage stdout.
  - `SageRuntime.kt`: sealed `Value` class with Num/Str/Bool/Nil/Arr/Dict/Tup/Obj/Fn/Gen/Ptr variants; full arithmetic/comparison/logical/bitwise dispatch; collection and string methods; reflection-based method dispatch; JVM GC integration.
  - Android UI library (`lib/android/`): `app.sage` (App, UIContext, Intent, Storage, HttpClient), `compose.sage` (declarative Compose UI).
  - REPL `:emit-kotlin`; `tests/42_kotlin/`; `examples/android_hello.sage`.
- **9 backends** now available: AST interpreter, bytecode VM, C, LLVM IR, native (x86-64/aarch64/rv64), JIT, AOT, Kotlin/Android.
- **All Kotlin backend limitations resolved**: generators, async, super, FFI, type specialization, Compose.

## [3.2.8] - 2026-04-18
- **SageMetal VM** (`src/c/metal_vm.c`, `include/metal_vm.h`): Freestanding bytecode interpreter — no malloc, no libc, no OS. Fixed-size static pools (512-slot value stack, 32KB string pool, 64KB heap, 1024 constants); 16-byte `MetalValue`; flat-array scope chain; array/dict pools; host-callback I/O (write_char, read_char, write_port, read_port, map_mmio); single-step mode (`metal_vm_step`) for cooperative multitasking; FNV-1a hashed O(1) scope resolution. Compiles freestanding: `gcc -ffreestanding -nostdlib -c metal_vm.c`.
- **Metal Standard Library** (`lib/metal/`): `metal.core` (putchar, puts, port I/O, MMIO, cli/sti/hlt, bump allocator, panic/assert), `metal.serial` (NS16550A UART x86 COM1-4 + PL011 ARM), `metal.irq` (PIC 8259A remap, EOI, mask/unmask, handler dispatch), `metal.timer` (PIT 8254, sleep_ms, stopwatch), `metal.gpio` (MMIO GPIO, pin modes, digital read/write).
- **Makefile target**: `make metal-vm` builds the freestanding Metal VM object.

## [3.2.7] - 2026-04-16
- **Hybrid JIT/AOT Default Runtime** (`SAGE_RUNTIME_AUTO`): Auto resolves to JIT profiling on hosted platforms, AST interpreter on bare-metal (`SAGE_PLATFORM_PICO`). JIT profiling silent in auto mode; override with `--runtime ast|bytecode|jit|aot`.
- **Pragmas**: `@nojit`, `@noaot`, `@noprofile` for per-function JIT/AOT control; `stmt_has_pragma()` helper.
- **Bare-metal safety**: Auto runtime detects `SAGE_PLATFORM_PICO` and falls back to AST — no `fork()`/`system()`/dynamic linking.

## [3.2.6] - 2026-04-15
- **Documentation Refresh + Benchmark Expansion**: README overhaul (JIT description, super call docs, recursion depth), concurrency in README (atomics, semaphores, condvars, rwlocks, SMP/multicore/hyperthreading); benchmark expansion (JIT Profiled, AOT, JIT+AOT lanes); execution backends table expanded 7 → 10.

## [3.2.5] - 2026-04-14
- **Hybrid JIT/AOT in self-hosted interpreter**: Per-function profiling (call counts, argument type tracking); hot function detection (50+ calls); monomorphic type inference; type-feedback-guided interpretation (100% fast-path rate for hot monomorphic functions); loop specialization (while-loops profile first 8 iterations); `_profile_call()`, `_get_profile()`, `_is_specialized()`, `_all_numbers()`; always-on profiling with zero overhead for cold functions.
- **Vulkan/OpenGL Android GPU support**: Android graphics library (`lib/android/graphics.sage`) — `GPUContext`, `GPUSurface`, `GLESContext`; Vulkan-style API; OpenGL ES 3.0 convenience layer; render pass/shader/synchronization abstractions; Android Surface management.
- **30+ Kotlin transpiler mappings**: CPU/SMP, atomics, semaphores, strings, paths, misc; expanded `SageRuntime.kt`.

## [3.2.4] - 2026-04-12
- **Full Concurrency**: C-level primitives (`sage_thread.h/c`) — condition variables, read-write locks, POSIX semaphores, mutex trylock, true `__atomic` operations (load/store/add/sub/CAS/exchange/fetch_and/fetch_or), CPU topology (`sage_cpu_count`, `sage_cpu_physical_cores`, `sage_cpu_has_hyperthreading`), thread affinity (`sage_thread_set_affinity`, `sage_thread_get_core`); all with RP2040 stubs.
- **Native builtins registered**: CPU, affinity, atomics, semaphores.
- **SMP/Multicore library** (`lib/os/smp.sage`): topology detection, core affinity, per-CPU data structures, multicore work distribution (`parallel_for_cores`, `on_all_cores`), IPI simulation (`send_to_core`).
- **Tests**: `smp_test.sage`, `atomic_native_test.sage`, `semaphore_test.sage`.

## [3.2.3] - 2026-04-11
- **Native C interpreter optimizations**: Cached `EnvNode.name_length` (avoids `strlen` per lookup); `env_get`/`env_define`/`env_assign` use `memcmp` with length pre-check; inlined `eval_expr` (recursion depth checked at `interpret()` boundaries); for-loop slot caching; `values_equal` string pointer-equality fast path.
- **Self-hosted interpreter optimizations**: O(1) dict dispatch table for `eval_binary` (all 15 operators); `eval_call` depth check at call boundary; inlined `eval_expr`.
- **Book update** (`docs/sagelang-book.md`): Part VIc (GC), Part VId (Kotlin/Android), Part VIe (Performance Optimization); CLI Reference updated (`--emit-kotlin`, `--compile-android`, GC flags, runtime modes, REPL commands).

## [3.2.2] - 2026-04-10
- **Self-hosted interpreter optimizations** (metaprogramming-driven): Pre-allocated signal singletons (`result_normal(nil)`, `result_break()`, `result_continue()` return cached dicts); native dispatch table (`call_native()` O(1) dict lookup replacing 180-line if/elif); shape constructors built as single dict literals; `register_native()` single-expression dict literal.
- **Performance library** (`lib/perf.sage`): Frozen signal singletons, dispatch table builders, flat environment cache, shape object factories, fast numeric operations, loop specialization helpers, string interning pool.
- **Cross-backend benchmark** (`benchmarks/backend_compare.sage`): 8 workloads (fibonacci, loop sum, array ops, string concat, dict ops, prime sieve, nested loops, LCG hash); `run_backend_compare.sh` runner; `generate_backend_chart.py` SVG chart generator.

## [3.2.1] - 2026-04-08
- **Performance Optimizations + Kotlin Fixes**: see 3.2.2/3.3.0 for merged detail.

## [3.2.0] - 2026-04-05
- **ORC Garbage Collector** (`--gc:orc`): Nim-inspired Optimized Reference Counting with Lins' trial deletion cycle collector. Three-phase trial deletion (mark PURPLE, mark trial-decrement to WHITE, collect confirmed cycles). Recommended for complex object graphs (linked lists, trees, circular references). More aggressive cycle collection than ARC (every 500 vs 1000 decrements). `gc_set_orc()` / `gc_mode()` returns `"orc"`.
- Three GC modes now available: `--gc:tracing` (default), `--gc:arc`, `--gc:orc`.
- ARC convenience macros (`ARC_RETAIN`, `ARC_RELEASE`, `ARC_ASSIGN`) work in both ARC and ORC modes.
- GC stats show mode name and ORC-specific metrics (epoch, cycle collections, cycles freed).
- Updated `GC_Guide.md`; new test `tests/20_gc/orc_mode.sage`.

## [3.1.2] - 2026-03-24
- **FAT module**: Native `fat` module with FAT8/12/16/32 boot-sector parsing + initial bare-metal/OSdev/UEFI native target profiles.
- **LLVM constant imports**: Resolved cross-module `from X import Y` constant imports (including aliases) at compile time for both C and self-hosted LLVM backends.

## [3.1.1] - 2026-03-20
- **Specification Lock**: Core language semantics frozen (see `STABILITY.md`).
- **REPL JIT/AOT**: `:runtime jit` and `:runtime aot` modes for interactive JIT profiling and AOT compilation.
- **Version unification**: `VERSION` file is the single source of truth; `net.c` User-Agent and Makefile help target now use `SAGE_VERSION_STR` / `$(SAGE_VERSION)` (previously hardcoded).
- **Usage string**: `--jit`, `--aot`, `--aot --jit`, and `check` commands.

## [3.1.0] - 2026-03-18
- **Phase 17**: Backpropagation with Adam optimizer for transformer training; cuBLAS GPU acceleration (RTX 4060: `cublasSgemm` FP32); NPU support (Qualcomm Hexagon, Samsung Exynos, ARM NEON, RISC-V Vector); C-only trainer `make train-c` (auto-detects GPU/NEON/RVV); TurboQuant, AutoResearch, GGUF import modules; `super.init()` and `->` arrow operator; models directory reorganized; SageMake unified build system (`./sagemake build|train|chatbot|all`); new Makefile targets `chatbot-native`, `all-models`. 241 tests passing.

## [3.0.19] - 2026-03-18
- **Phase 15: Vulkan Graphics Library + Self-Hosted Ports**:
  - **C Native Module** (`src/c/graphics.c`, ~2600 lines): Handle-table Vulkan design; `SAGE_HAS_VULKAN` auto-detection via pkg-config; context lifecycle, buffers, images (1D/2D/3D, 13 formats), samplers, SPIR-V shaders, descriptors, compute/graphics pipelines, render passes & framebuffers, commands, synchronization (fences/semaphores), submission (graphics + compute queues); 100+ Vulkan enum constants.
  - **Sage-Level Libraries**: `lib/vulkan.sage` (builder-pattern API), `lib/gpu.sage` (high-level helpers: `run_compute`, `create_ping_pong`, `print_info`).
  - **Self-Hosted Ports**: `diagnostic.c` → `diagnostic.sage` (53 tests), `gc.c` → `gc.sage` (45 tests), `heartbeat.c` → `heartbeat.sage` (44 tests).
  - **Professional Rendering** (~4000 lines): Input handling (GLFW key/mouse), swapchain recreation, uniform buffers, offscreen rendering, texture loading (stb_image PNG/JPG/BMP/TGA), mipmaps, indirect draw/dispatch, 3D textures, cubemaps, multi-vertex binding, MRT render passes, byte upload, shader hot-reload, screenshot.
  - **Rendering Libraries** (16 files, ~2300 lines): `math3d`, `mesh`, `renderer`, `postprocess` (HDR/bloom/tonemapping), `pbr` (Cook-Torrance), `shadows` (cascade), `deferred` (G-buffer/SSAO/SSR), `gltf`, `taa`, `scene`, `material`, `asset_cache`, `frame_graph`, `debug_ui`.
  - **GLSL Shaders** (27 SPIR-V modules): PBR, bloom, shadows, skybox, N-body, stars, nebula, planet.
  - **Demos** (6 GPU examples): `gpu_window`, `gpu_triangle`, `gpu_hello3d`, `gpu_cube`, `gpu_phong`, `gpu_particles` (65536 GPU compute particles).
  - **Build & Test**: `VULKAN` Make variable (auto/1/0), GLFW auto-detection, stb_image vendored; 1567+ self-hosted tests passing (285 GPU tests).

## [3.0.18] - 2026-03-17
- **LLVM Backend: Runtime Library & Compile-to-Executable**: Standalone C runtime (`src/c/llvm_runtime.c`) implementing 40+ `sage_rt_*` functions (value constructors, arithmetic, comparison, logical, bitwise, collections, property access, conversion, I/O). ABI fix (`%SageValue = type { i32, i64 }`); variable assignments; global/local distinction; `collect_local_names()` pass; block termination tracking; bitwise operators; class support; exception handling; linker integration (`--compile-llvm` auto-discovers `obj/llvm_runtime.o`). New Test 22b validates end-to-end executable generation. 1425+ tests passing.
- **Phase 14 Complete**: Security & performance audit (30 fixes across 14 files).

## [3.0.17] - 2026-03-16
- **Interpreter Safety Hardening (Fuzz-Driven)**: `MAX_STRING_LENGTH 4096` (parse-time error instead of SIGSEGV on long strings); `MAX_LOOP_ITERATIONS 1000000` (catchable exception instead of hang); null function-pointer guards on `VAL_FUNCTION`/`VAL_NATIVE` call paths; type-safe accessor macros `SAGE_AS_STRING`/`SAGE_AS_NUMBER`/`SAGE_AS_BOOL` (safe defaults on type mismatch). 144 interpreter + 28 compiler + 1168 self-hosted tests passing.

## [3.0.16] - 2026-03-10
- **Documentation Refresh, CLI Reference, and REPL Commands**: README build parameter reference (Make + CMake); full `sage` CLI parameter reference; `SageLang_Guide.md` mirrored to current build/CLI/REPL surface. New REPL commands: `:vars [prefix]`, `:type <expr>`, `:load <file>`, `:reset`, `:pwd` / `:cd <dir>`, `:gc`; expanded `:help`; `--emit-asm`/`--compile-native` advertise `-g`.

## [3.0.15] - 2026-03-09
- **Networking Modules & cJSON Port** (`src/net.c`, ~850 lines): Four native modules backed by libcurl and OpenSSL:
  - `socket` (15 functions + constants): POSIX socket operations (create, bind, listen, accept, connect, send, recv, sendto, recvfrom, close, setopt, poll, resolve, nonblock); `AF_INET`, `AF_INET6`, `SOCK_STREAM`, `SOCK_DGRAM`, `SOCK_RAW`, `IPPROTO_TCP`, `IPPROTO_UDP`.
  - `tcp` (9 functions): High-level TCP with automatic buffering (connect, listen, accept, send, recv, sendall, recvall, recvline, close).
  - `http` (9 functions): HTTP/HTTPS client via libcurl (get, post, put, delete, patch, head, download, escape, unescape); returns `{status, body, headers}`; options for timeout, follow, verify, user_agent, headers, cainfo.
  - `ssl` (13 functions): OpenSSL TLS bindings (context, load_cert, wrap, connect, accept, send, recv, shutdown, free, free_context, error, peer_cert, set_verify).
  - **cJSON Port** (`lib/json.sage`, ~1050 lines): Complete 1:1 port of Dave Gamble's cJSON — parse, print (formatted/compact/buffered), creation (13), query (7), type checks (10), array modification (5), object modification (8), helpers (9), utility (7), Sage extras (`cJSON_ToSage`, `cJSON_FromSage`). 88 new JSON tests.
  - **Build**: `-lcurl -lssl -lcrypto` added to LDFLAGS; PkgConfig for libcurl/openssl in CMake.

## [3.0.14] - 2026-03-09
- **Build System: CMake and Make Support for Self-Hosted Builds**: `make sage-boot FILE=<file>`, `make test-selfhost` (lexer/parser/interpreter/bootstrap), `make test-all`, `make cmake-sage`, `make cmake-sage-build`. CMake options: `BUILD_SAGE=ON` (self-hosted `sage_boot`/`test_selfhost`), `BUILD_PICO=ON`, `ENABLE_DEBUG`, `ENABLE_TESTS`. Self-hosted sources in `src/sage/`.

## [3.0.13] - 2026-03-09
- **Phase 13 Complete: Self-Hosting**: Self-hosted Sage interpreter written entirely in SageLang. Lexer (`lexer.sage`, ~300 lines), Parser (`parser.sage`, ~700 lines, 12 precedence levels), Interpreter (`interpreter.sage`, ~920 lines), `token.sage`, `ast.sage`, `sage.sage` bootstrap. New native builtins: `type()`, `chr()`, `ord()`, `startswith()`, `endswith()`, `contains()`, `indexof()`. Test suites: lexer 12/12, parser 130/130, interpreter 18/18, bootstrap 18/18. (GC must be disabled for self-hosted code via `gc_disable()`.)

## [3.0.12] - 2026-03-09
- **Phase 12 Complete: Tooling Ecosystem**: REPL (`sage`/`--repl`) with multi-line blocks, error recovery, `:help`/`:quit`/`:vars`/`:type`/`:load`/`:reset`/`:pwd`/`:cd`/`:gc`; Code Formatter (`sage fmt`, `sage fmt --check`); Linter (`sage lint`, 13 rules: E001-E003 errors, W001-W005 warnings, S001-S005 style); Syntax Highlighting (TextMate grammar, VSCode extension); LSP Server (`sage --lsp`, standalone `sage-lsp`) with diagnostics, completion, hover, formatting. 112 interpreter + 28 compiler tests passing.

## [3.0.11] - 2026-03-09
- **Phase 11 Complete: Concurrency & Parallelism**: Native stdlib modules (`math`, `io`, `string`, `sys`); Thread module (`thread.spawn`, `thread.join`, `thread.mutex`, `thread.lock`, `thread.unlock`, `thread.sleep`, `thread.id`; GC protected with pthread mutex); Async/Await (`async proc`, `await`, `STMT_ASYNC_PROC`, `EXPR_AWAIT`; calling async proc spawns background thread); LLVM backend expansion (dict/tuple literals, slices, property access, for-in, break/continue with loop label stack); native codegen expansion (for-in, break/continue). 112 interpreter + 24 compiler tests passing.

## [3.0.10] - 2026-03-09
- **Phase 10 Complete: Compiler Development**: Full compiler pipeline with three backends — C codegen (complete language coverage), LLVM IR (`--emit-llvm`/`--compile-llvm`), native assembly (`--emit-asm`/`--compile-native` for x86-64, aarch64, rv64). Optimization passes: type checking (`-O1+`), constant folding (`-O1+`), dead code elimination (`-O2+`), function inlining (`-O3`). Debug info via `-g`. 24 compiler tests passing.

## [3.0.9] - 2026-03-08
- **Phase 9.5: C Struct Interop**: `struct_def(fields)`, `struct_new(def)`, `struct_get`/`struct_set`, `struct_size(def)` with proper C ABI alignment. Types: `char`, `byte`, `short`, `int`, `long`, `float`, `double`, `ptr`. 4 new tests in `tests/25_structs/`. 100 tests across 25 categories.

## [3.0.8] - 2026-03-08
- **Phase 9.4: Inline Assembly (Multi-Architecture)**: `asm_exec(code, ret_type, ...args)` (compile + execute on host; return types `int`/`double`/`void`; up to 4 numeric args via ABI registers), `asm_compile(code, arch, output_path)` (cross-compile to object file; `x86_64`/`aarch64`/`rv64`), `asm_arch()` (host architecture). Implementation via `.s` → `as` → `.o` → `gcc -shared` → `.so` → `dlopen`/`dlsym`; System V ABI. 5 new tests in `tests/24_assembly/`. 96 tests across 24 categories.

## [3.0.7] - 2026-03-08
- **Phase 9.3: Raw Memory Operations**: `mem_alloc(size)` (zero-initialized, up to 64MB), `mem_free(ptr)` (invalidates pointer), `mem_read(ptr, offset, type)` / `mem_write(ptr, offset, type, val)` (types: `byte`/`int`/`double`/`string`), `mem_size(ptr)`, `addressof(val)`. New `VAL_POINTER` value type with bounds checking and use-after-free prevention. 5 new tests in `tests/23_memory/`. 91 tests across 23 categories.

## [3.0.6] - 2026-03-08
- **Phase 9.2: Foreign Function Interface (FFI)**: `ffi_open(path)`, `ffi_call(lib, func, ret_type, ...args)` (`double`/`int`/`long`/`string`/`void`; 0–3 args), `ffi_sym(lib, name)`, `ffi_close(lib)`. New `VAL_CLIB` value type wrapping `dlopen` handle; `-ldl` added to linker flags. 3 new tests in `tests/22_ffi/`. 86 tests across 22 categories.

## [3.0.5] - 2026-03-08
- **Phase 9: Bitwise Operators**: `&` (AND), `|` (OR), `^` (XOR), `~` (NOT), `<<` (left shift), `>>` (right shift). C-style precedence: `~` (unary) → `<<`/`>>` → `&` → `^` → `|` → `and`/`or`. New tokens `TOKEN_AMP`/`PIPE`/`CARET`/`TILDE`/`LSHIFT`/`RSHIFT`. 6 new tests in `tests/21_bitwise/`. 83 tests across 21 categories.

## [3.0.4] - 2026-03-08
- **Phase 8.5: Security & Performance Hardening**: Recursion depth limits (interpreter 1000 frames, parser 500 nesting); OOM safety (`SAGE_ALLOC`/`SAGE_REALLOC` abort-on-failure wrappers); `gc_pin()`/`gc_unpin()` API; module path traversal validation (`realpath` containment); iterative lexer (`scan_token` no longer recursive). Performance: hash-table dictionaries (FNV-1a, open-addressing, linear probing, 75% load factor, backward-shift deletion); O(n) string `join`/`replace`; `size_t` string lengths; environment GC integration (O(1) mark checks). Module system completion: `import mod`, `import mod as alias`, `from mod import x, y [as z]`, circular dependency detection, module caching. 77 tests across 20 categories via `tests/run_tests.sh` (`# EXPECT:` / `# EXPECT_ERROR:`).

## [3.0.0] - 2026-03-01
- **Initial Release**: Core interpreter and compiler stability achieved. Specification established.

## [0.8.0] - 2025-12-28
- **Phase 8: Module System (60%)**: Function closure support in `FunctionValue`; module infrastructure (parsing, loading, caching); search path system for module resolution.

## [0.7.0] - 2025-11-29
- **Phase 7: Advanced Control Flow (100%)**: Generators with `yield`/`next`; exception handling (`try`/`catch`/`finally`/`raise`); loop control (`for`-in, `break`, `continue`).

## [0.6.0] - 2025-11-28
- **Phase 6: Object-Oriented Programming (100%)**: Classes with `init`, methods, `self` binding; single inheritance with method overriding; property access and assignment.

## [0.5.0] - 2025-11-27
- **Phase 5: Advanced Data Structures (100%)**: Arrays, dictionaries, tuples; array slicing, string methods; 20+ native functions added.

## [0.4.0] - 2025-11-27
- **Phase 4: Garbage Collection (100%)**: Mark-and-sweep GC with configurable threshold; `gc_collect()`, `gc_stats()`, `gc_enable()`, `gc_disable()`.
