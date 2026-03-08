# SageLang Updates

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
