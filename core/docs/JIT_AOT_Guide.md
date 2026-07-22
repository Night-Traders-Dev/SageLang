# JIT & AOT Compilation Guide

SageLang ships a hybrid JIT/AOT compilation stack with profile-guided type
specialization, available across the C interpreter and the self-hosted
interpreter.

## JIT Profiler

`sage --jit file.sage`

The interpreter instruments every function with per-function profiling counters
and type feedback. Hot functions (100+ calls) are detected; argument and return
types are classified (`int`, `float`, `string`, `bool`, `mixed`). Profiling
data is reported for AOT optimization.

## JIT Self-Extracting Executables

`sage --jit file.sage -o binary`

SageLang can bundle a script and all its transitive non-native module dependencies into a single, self-extracting JIT executable. This is achieved by recursively discovering imports from the parse tree, serializing the module sources into the ELF binary, and inserting them into the module cache at runtime.

This allows for easy distribution of SageLang applications without needing to manage a complex directory structure for custom libraries.

## AOT Compiler

`sage --aot file.sage -o binary`

Ahead-of-time compilation with static type inference. Generates self-contained C11 code with type-specialized fast paths for `Int+Int`, `String+String`, and known-type comparisons, then compiles to a standalone native binary via `cc -O2`.

As of **v4.1.1**, the AOT compiler supports:
- **Full Class Compilation (`STMT_CLASS`)**: Generates C constructor functions (`s_ClassName`), method dispatch tables on `sage_dict` instances, and implicit `s_self` binding for method bodies.
- **Built-in Protection & Symbol Deduplication**: Tracks builtin function signatures (`builtin_count`) to avoid duplicate emissions during flattened standard library module imports (`io.sage`, `sys.sage`).
- **Scope-Safe `val_native` Wrapping**: Distinguishes user-defined function pointers from local variables shadowing builtin names (e.g. `let keys = dict_keys(...)`).
- **Dynamic Property & Method Invocation**: Automatically translates method calls (`obj.method(...)`) to `sage_call(sage_get_property(obj, "method"), argc, args)`.
- **Recursive `comptime:` Traversal**: Forward declares variables and procedures inside `comptime:` blocks (`aot_forward_declare_stmt`) at global static C scope.

### Cross-Compilation

Because the AOT compiler translates Sage code to standalone C11 source code, it serves as the primary avenue for seamless cross-compilation. To cross-compile a SageLang application:

1. Generate the raw C file by omitting the `-o` flag and redirecting stdout:
   `sage --aot file.sage > program.c`
2. Compile the resulting C file with a target-specific cross compiler:
   `aarch64-linux-gnu-gcc -std=c11 -O2 program.c -o program-aarch64 -lm`

## Combined Mode (Profile-Guided AOT)

`sage --aot --jit file.sage -o binary`

Runs the program once to collect JIT type feedback, then feeds that data to the
AOT compiler for better specialization.

## Runtime Selection

Override the runtime explicitly with `--runtime ast|bytecode|jit|aot`. In auto
mode (`SAGE_RUNTIME_AUTO`):

- Hosted platforms (desktop, Android, server) → JIT profiling (silent, no banner)
- Bare-metal (`SAGE_PLATFORM_PICO`) → AST interpreter (no `fork()`/`system()`/dynamic linking)

Explicit `--jit` shows diagnostics.

## Pragmas / Decorators

Per-function JIT/AOT control via pragmas:

- `@nojit` — skip JIT profiling for the decorated function
- `@noaot` — skip AOT compilation for the decorated function
- `@noprofile` — skip all profiling for the decorated function

`stmt_has_pragma()` is the interpreter helper for pragma checking.

## Self-Hosted Hybrid Specialization

The self-hosted interpreter (`src/sage/interpreter.sage`) implements its own
profile-guided specialization — always-on with no flags needed:

- Per-function call counting and argument type tracking in `_profiles`
- Hot function detection (50+ calls marked "specialized")
- Monomorphic type inference (tracks whether all calls pass the same types)
- Type-feedback-guided interpretation — hot monomorphic functions always hit the
  number fast path in `eval_binary` (100% fast-path rate vs ~70% without profiling)
- Loop specialization — while-loops profile the first 8 iterations; if the body
  is simple (no `break`/`return`/`continue`), switches to a fast loop that skips
  signal checking entirely
- Primitives: `_profile_call()`, `_get_profile()`, `_is_specialized()`, `_all_numbers()`

## Performance Library

`lib/perf.sage` provides reusable optimization primitives: frozen signal
singletons, dispatch table builders, flat environment cache, shape object
factories (function/class/instance/native/generator/env), fast numeric
operations (bypass type dispatch), loop specialization helpers, and a string
interning pool.

## Benchmarks

- `benchmarks/backend_compare.sage` — 8 workloads (fibonacci, loop sum, array
  ops, string concat, dict ops, prime sieve, nested loops, LCG hash) across all
  native backends.
- `benchmarks/run_backend_compare.sh` — shell runner with timing and checksum
  verification.
- `scripts/generate_backend_chart.py` — SVG chart generator from live results.
- `make benchmark-python` — Sage vs CPython 3.x on 10 workloads.

See `core/docs/meta/BENCHMARKS.md` for results and `core/docs/meta/OPT_STATUS.md`
for the optimization work log.
