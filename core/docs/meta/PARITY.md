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
- **Self-hosted *compiled* output:** 9 / 28 (**32 %**) — the emitted-C backend
  covers a substantially smaller language subset and has one correctness-critical
  bug (short-circuit evaluation).

## Dynamic results (run_parity.sh)

```
PARITY : 01 04 07 08 11 16 17 22 24 25 27            (11 cases)
SHI gap: 10 first-class fns   14 match guards  15 div-by-zero catchability
         18 generator print/iteration 21 aliased from-import 28 defer order
SHC gap: 02 string slice/index/contains  03 SHORT-CIRCUIT ORDER (bug)
         05 array concat/slice  06 dict_delete→gcc-fail  09 for-in→gcc-fail
         12 default params→gcc-fail     13 closures→gcc-fail
         19 comptime folding   20 int()/tonumber  23 bytes API
         26 chr/ord/negative-index  28 defer dropped
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

## Closed during this audit

- `elif` mis-parsed as a fresh top-level `if` (self-hosted parser lacked the
  C parser's elif-chaining check) — fixed in `parser.sage`.
- Dict printing omitted key quotes (`{k: 1}` vs `{"k": 1}`) — fixed in
  `value_to_string`.
- `val_tag` was registered for user programs without a `_native_dispatch`
  handler → "Unknown native function" — handler added.

## Recommendations (priority order)

1. **Fix short-circuit emission** in `compiler.sage` (`and`/`or` evaluate both
   sides) — correctness, not just parity.
2. Port the missing runtime helpers to the emitted-C prelude: string
   slice/index/contains/chr/ord, array concat/slice, bytes API, `int()`/
   `tonumber`, comptime folding, defer unwinding.
3. Extend `cc_emit_stmt` coverage: for-in loops, dict ops, default parameters,
   anonymous procs/closures, match.
4. First-class functions in the self-hosted call path (arity resolution when a
   param holds a function value).
5. Match guards in `parser.sage`; unify parse-error formatting.
6. Generator printing/iteration protocol alignment.
7. Builtin completion: forward unknown `_native_dispatch` names to host
   natives automatically; add serialize/thread families or document them as
   C-host-only.
