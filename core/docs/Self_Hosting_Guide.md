# Self-Hosting Guide

Sage can run Sage programs through a self-hosted interpreter written entirely in
SageLang. The lexer, parser, interpreter, and full compiler toolchain have been
ported from C to Sage (Phase 13+).

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

## Bootstrap Coverage

Arithmetic, variables, control flow, functions, recursion, closures, classes,
inheritance, arrays, dicts, strings, try/catch, break/continue, bitwise
operators (`~`), and module imports with loop iteration limits.

## Module Imports

`import X`, `import X as Y`, `from X import a, b` with module caching and
multi-path search (`./`, `lib/`). Supports `__init__.sage` for directory-based
packages (v3.9.8+).

## Soft Keywords

`match`, `init`, `enum`, `struct`, and `trait` are "soft keywords" — usable as
variable names in expressions and assignments while still acting as keywords in
declarations (v3.9.8+). `end` is also a soft keyword (block terminator or
identifier).

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
