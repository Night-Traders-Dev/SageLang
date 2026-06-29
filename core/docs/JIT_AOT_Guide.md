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

## AOT Compiler

`sage --aot file.sage -o binary`

Ahead-of-time compilation with static type inference. Generates self-contained
C with type-specialized fast paths for `Int+Int`, `String+String`, and
known-type comparisons. Compiles to a native binary via `cc -O2`.

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
