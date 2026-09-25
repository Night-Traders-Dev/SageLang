# Self-Hosting Guide

Sage can run Sage programs through a self-hosted interpreter written entirely in
SageLang. The lexer, parser, interpreter, and full compiler toolchain have been
ported from C to Sage (Phase 13+).

## Compiler Parity

The differential harness at `testsuite/parity/run_parity.sh` executes 28
feature cases through three stacks — the C interpreter, the self-hosted
interpreter, and binaries compiled by the self-hosted compiler
(`--emit-c` → gcc) — and compares their output byte for byte.

**All 28 cases are byte-identical across all three stacks** (v4.2.10).

This was 27/28 at v4.2.9: the self-hosted compiler did not implement *binding
patterns* in `match`, so a bare-identifier case pattern such as
`case n if n > 3:` was evaluated as an ordinary expression and reported
`Undefined variable 'n'` instead of binding `n` and taking the guarded branch.
Both the self-hosted interpreter and the self-hosted codegen now treat a
bare-identifier pattern as a binding, define it in a clause-scoped environment
(interpreter) or slot (codegen) before evaluating the guard, and keep `_` as a
wildcard that binds nothing. See `core/docs/meta/PARITY.md` for the full matrix
and the `--selfhost` mode of `sagemake` for one-command bootstrap verification.

## Running the Self-Hosted Interpreter

```bash
cd src/sage && ../../sage sage.sage program.sage
```

Or via Make:

```bash
make sage-boot FILE=examples/hello.sage
make test-selfhost
```

## Self-Hosted Components

| File | Lines | Description |
| ---- | ----- | ----------- |
| `src/sage/token.sage` | — | Token type constants |
| `src/sage/ast.sage` | — | Dict-based AST node constructors |
| `src/sage/lexer.sage` | ~300 | Indentation-aware tokenizer with dict-based keyword lookup |
| `src/sage/parser.sage` | ~700 | Recursive descent parser with 12 precedence levels |
| `src/sage/interpreter.sage` | ~1050 | Tree-walking evaluator with dict-based value representation |
| `src/sage/sage.sage` | — | Bootstrap entry point — runs target `.sage` files |
| `src/sage/typecheck.sage` | 228 | **Type checker** — tracks inferred and declared types (type annotations `let x: Int`, `proc f() : Int`, `proc f(x: Int)`). Supports `TypeMap.declared` dict and `annotation_to_kind` mapping. Infrastructure for let/return/param type validation. |

## Bootstrap Coverage

Arithmetic, variables, control flow, functions, recursion, closures, classes,
inheritance, arrays, dicts, strings, try/catch, break/continue, bitwise
operators (`~`), and module imports with loop iteration limits.

**Type annotations**: `let x: Int = ...`, `proc f() : Int`, `proc f(x: Int)` — type
declared/inferred tracking via `TypeMap.declared` dict and `annotation_to_kind`
mapping. **Fully implemented in parser and typecheck** (see parser.sage:45-54,
typecheck.sage:147-165). Type validation at let-binding, return statements,
and proc parameters.

## Module Imports

`import X`, `import X as Y`, `from X import a, b` with module caching and
multi-path search (`./`, `lib/`). Supports `__init__.sage` for directory-based
packages (v4.1.3+).

## Soft Keywords

`print`, `end`, `match`, `init`, `enum`, `struct`, and `trait` are "soft keywords" —
usable as variable, property, or method names in expressions and assignments while
still acting as keywords in declarations (v4.1.3+).

## Hybrid JIT/AOT Profiling

The self-hosted interpreter implements its own profile-guided specialization —
always-on with no flags. See [JIT_AOT_Guide.md](JIT_AOT_Guide.md) for details.

## Self-Hosted Test Suites

```bash
make test-selfhost-lexer
make test-selfhost-parser
make test-selfhost-interpreter
make test-selfhost-bootstrap
make test-selfhost-formatter
make test-selfhost-linter
make test-selfhost-value
make test-selfhost-pass
make test-selfhost-constfold
make test-selfhost-dce
make test-selfhost-inline
make test-selfhost-typecheck
make test-selfhost-stdlib
make test-selfhost-module
make test-selfhost-llvm-backend
make test-selfhost-llvm-gpu
make test-selfhost-codegen
make test-selfhost-compiler
make test-selfhost-errors
make test-selfhost-lsp
make test-selfhost-sage-cli
make test-all
```

Covers lexer, parser, interpreter, bootstrap, formatter, linter, value,
optimization passes (constfold/DCE/inline/typecheck), stdlib, module loading,
codegen, compiler, LSP, and CLI.

## Note

GC must be disabled for self-hosted code: `gc_disable()`.
