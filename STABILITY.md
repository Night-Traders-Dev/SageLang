# Sage Stability Policy

## Version 2.0 — Specification Lock

Sage 2.0 freezes the core language semantics. This document defines the stability
guarantees, deprecation policy, and conformance expectations.

## Semantic Versioning

Sage follows semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes to language semantics or removal of features.
- **MINOR**: New features, new syntax, new builtins (backward-compatible).
- **PATCH**: Bug fixes, performance improvements, documentation updates.

## Stability Guarantees (from 2.0 onward)

The following are **stable** and will not change without a major version bump:

1. **Truthiness**: Only `false` and `nil` are falsy. `0`, `""`, `[]` are truthy.
2. **Equality**: Value equality for all types (structural for instances, arrays, dicts).
3. **Operator precedence**: As defined in Spec §4.
4. **Lexical scoping**: Methods see their defining environment.
5. **Indentation syntax**: INDENT/DEDENT block structure.
6. **Core types**: Nil, Bool, Int, Float, String, Array, Dict, Tuple, Bytes, Function.
7. **Control flow**: if/elif/else, while, for/in, match/case, try/catch/finally, defer.
8. **Class model**: Single inheritance, `super.init()` (auto-self), `__str__`, `__eq__`.
9. **Module system**: `import`, `from X import Y`, dot-path modules.
10. **Type annotations**: Optional, gradual typing with `sage check`.

## Deprecation Policy

- Deprecated features will emit warnings for at least one minor release.
- Removal requires a major version bump.
- Migration guides will accompany any breaking changes.

## Backend Conformance

All conforming backends (interpreter, C backend, LLVM backend, native codegen)
must produce identical observable behavior for the conformance test suite
(`tests/40_conformance/`). Differences in:

- Optimization strategy
- Object layout
- Internal representation
- Compilation speed

are permitted, provided they do not alter language-visible behavior.

## Conformance Testing

Run the conformance suite:

```
bash tests/run_conformance.sh
```

This tests identical programs across interpreter, C backend, and LLVM backend.
