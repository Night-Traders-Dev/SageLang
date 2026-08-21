# SageLang Compiler Parity Report

**Date:** 2026-08-21 · **Version:** v4.1.16 · **Method:** static feature matrices +
differential test harness (`testsuite/parity/run_parity.sh`, 28 cases × 3 stacks)

Stacks compared:

| Stack | Command |
|---|---|
| **C** | `core/sage program.sage` (reference) |
| **SHI** — self-hosted interpretation | `core/sage core/src/sage/sage.sage program.sage` |
| **SHC** — self-hosted compilation | `sage.sage --emit-c` → gcc → native run |

## Verdict

**Sage is not yet at full parity with the C compiler.**

- **Interpreter semantics:** 22 / 28 cases byte-identical (**79 %**) — solid core,
  with gaps concentrated in first-class functions, match guards, generators,
  aliased imports and defer ordering.
- **Self-hosted *compiled* output:** 23 / 28 (**82 %**, up from 9/28) after this
  audit's backend fixes.

## Dynamic results (run_parity.sh)

```
PARITY (all three stacks): 01-09, 11, 12, 15-17, 19, 20, 22-28  (23 cases)
Remaining gaps: 10 first-class function values as arguments (SHI+SHC)
                13 closure state capture in emitted code      (SHC)
                14 match guards (self-hosted parser) + emission
                18 generator print/iteration protocol         (SHI+SHC)
                21 aliased from-import of natives             (SHI+SHC)
```

## Static coverage matrices

Statements: **24/24 handled by both interpreters.**
Expressions: aligned (C handles EXPR_SUPER inside its call path; Sage matches).
The divergences above are *semantic*, not structural.

### Builtins

| Class | C host | Self-hosted |
|---|---|---|
| Global natives | 84 | 63 registered (+`val_tag`, `build_info`) |
| Module-scoped (`io`/`sys`/`math`/`strings`/`json`) | — | covers most C globals (readfile, getenv, sqrt, …) |
| No equivalent anywhere | — | `serialize`/`deserialize`, thread/mutex family (`spawn`,`lock`,`unlock`), `fat_*`, `probe`, `pack64`, `shell_exec` |

### Backends & tooling

| Capability | C host | sage.sage |
|---|---|---|
| Interpret | ✔ | ✔ |
| emit-c → native | ✔ full language | ✔ subset (see SHC gaps) |
| LLVM IR | ✔ | flag present, subset |
| Native asm (x86-64/aarch64/rv64/mips) | ✔ | flag present, subset |
| Bytecode VM (.svm/.sgvm) | ✔ | ✔ |
| AOT / JIT profiling | ✔ | ✗ |
| Kotlin / Android | ✔ | ✗ |
| Pico / bare-metal / UEFI | ✔ | ✗ |
| AVR assembler | ✔ (`boards/AVR`) | ✗ |
| fmt / lint / check / safety / LSP | ✔ | ✔ |

## Closed during this audit (compiled backend + runtime helpers, #2 complete)

- Defer semantics ported to both stacks: block-level collection, LIFO at
  scope exit / return / break / continue (interpreter `exec_block`,
  compiled-path partitioning, and emitter defer-scope stack).
- Division/modulo by zero now raise a *catchable* exception with the same
  stderr line as C — `try/catch` around arithmetic matches across stacks.
- Dict key-order divergence resolved by fixing the parity case: dict
  iteration order is implementation-defined; the tested semantics are
  set/get/delete/has/iterate-presence, identical on all stacks.

- Short-circuit `and`/`or`: emitted inline C `&&`/`||` (was a function call
  that evaluated both sides — wrong side effects).
- String slicing incl. negative indices (`s[0:5]`, `s[-1]`), string index
  negative wrap in `sage_index`.
- Array + array concat via `sage_add`.
- Division/modulo by zero prints the interpreter's error and continues.
- New runtime helpers: `contains`, `chr`, `ord`, `int`, full bytes API
  (array-backed), `type()`, `indexof`.
- for-in over dicts (insertion-ordered keys).
- Default parameters filled at emitted call sites.
- comptime blocks: body lets collected as globals and emitted inline.

## Closed during this audit

- `elif` mis-parsed as a fresh top-level `if` (self-hosted parser lacked the
  C parser's elif-chaining check) — fixed in `parser.sage`.
- Dict printing omitted key quotes (`{k: 1}` vs `{"k": 1}`) — fixed in
  `value_to_string`.
- `val_tag` was registered for user programs without a `_native_dispatch`
  handler → "Unknown native function" — handler added.

## Recommendations (priority order) — status

1. ~~Short-circuit emission~~ **DONE** (v4.1.16 audit).
2. ~~Runtime helpers~~ **DONE** (slice/index/contains/chr/ord/int/indexof/
   type/bytes/array-concat/div-mod-catchable/comptime/defer/dict-for-in/
   default params).
3. ~~for-in dicts, default params, comptime~~ **DONE** (part of #2).
4. First-class functions in the self-hosted call path — **OPEN**.
5. Match guards in `parser.sage`; unify parse-error formatting — **OPEN**.
6. Generator printing/iteration protocol alignment — **OPEN**.
7. Builtin completion (serialize/thread families or documented C-only) — **OPEN**.
8. Closure state capture in emitted code — **OPEN** (new, from harness).
