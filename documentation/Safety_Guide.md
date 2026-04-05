# SageLang Safety System Guide

SageLang v2.1 introduces a compile-time safety system that provides six major guarantees: **Ownership & Move Semantics**, **Borrow Checking**, **Lifetime Tracking**, **Option Types (No Nulls)**, **Fearless Concurrency**, and **Unsafe Barriers**.

## Design Philosophy

The safety system is a **decoupled static analysis pass**. It runs on the AST after parsing and before code generation. The C, LLVM, and native assembly backends never see the borrow checker — by the time code reaches a backend, it has already been proven safe.

SageLang defaults to C-like behavior (maximum freedom for device drivers, bootloaders, kernels). Safety is **opt-in** via two mechanisms.

## Invoking Safety

### A. CLI Flag (Global Control)

```bash
# Strict safety: entire file is ownership/borrow checked
sage --strict-safety script.sage

# Safety analysis only (report errors, don't run)
sage safety script.sage
```

When `--strict-safety` is passed, the compiler enforces ownership, borrow exclusivity, lifetime validity, and nil prohibition across the entire file. If any safety error is detected, compilation aborts before execution.

### B. Doc-Comment Annotation (Granular Control)

Mark individual functions as safe using a `@safe` doc comment:

```sage
## @safe
proc process(data):
    # Ownership and borrow rules enforced here
    let result = transform(data)   # 'data' is moved
    # print data                    # ERROR: use after move
    return result
end
```

Functions without `@safe` annotation run in classic mode.

### C. Unsafe Blocks

Raw pointer math and unchecked operations must be quarantined in `unsafe:` blocks when safety is active:

```sage
unsafe:
    # Low-level memory operations allowed here
    let ptr = alloc(4096)
    memset(ptr, 0, 4096)
end
```

## Enforcement Matrix

| `--strict-safety` | `@safe` Annotation | Behavior |
|---|---|---|
| OFF | Not used | Classic SageLang. No safety checks. |
| OFF | Used | Functions with `@safe` are checked; others run freely. |
| ON | Used | Full enforcement. `@safe` functions + `unsafe:` blocks audited. |
| ON | Not used | Full enforcement. Raw pointer ops without `unsafe:` are errors. |

## 1. Ownership & Move Semantics

Every value has a single owner. When a value is assigned to another variable or passed to a function, ownership **moves** — the original variable becomes invalid.

```sage
## @safe
proc example():
    let data = [1, 2, 3]
    let moved = data        # ownership moves to 'moved'
    # print data            # ERROR: use of moved value 'data'
    print moved             # OK
end
```

### Copy Types

Primitive types (numbers, booleans, strings) implement the **Copy** trait and are implicitly copied instead of moved:

```sage
## @safe
proc copy_example():
    let x = 42
    let y = x       # copied, not moved
    print x          # OK — x is still valid
    print y          # OK
end
```

### Explicit Ownership Transfer

Use `safety.own()` to document ownership transfer:

```sage
import safety

let buffer = [0, 0, 0, 0]
let owned = safety.own(buffer)    # explicit move
```

## 2. Borrow Checking

The borrow checker enforces that at any point in time, a scope has **either one mutable reference OR multiple immutable references**, but never both.

```sage
## @safe
proc borrow_example():
    let data = [1, 2, 3]
    let ref1 = data         # immutable borrow
    let ref2 = data         # second immutable borrow — OK
    # let mut_ref = data    # ERROR: cannot mutably borrow while immutably borrowed
end
```

Use `safety.ref()` and `safety.mut_ref()` to annotate borrow intent:

```sage
import safety

let original = [10, 20]
let borrowed = safety.ref(original)     # immutable borrow
let mutable = safety.mut_ref(original)  # mutable borrow
```

## 3. Lifetime Tracking

The safety pass tracks how long references remain valid. A reference cannot outlive the data it points to:

```sage
## @safe
proc dangling():
    let outer_ref = nil
    if true:
        let local = [1, 2, 3]
        outer_ref = local   # ERROR: reference outlives 'local'
    end
    # local is destroyed here; outer_ref would dangle
end
```

## 4. Option Types (No Nulls)

In safe contexts, `nil` is prohibited. Use `Option[T]` instead:

```sage
import safety

# Instead of: let result = nil
let result = safety.None()

# Instead of: let result = value
let result = safety.Some(42)

# Safe access:
if safety.is_some(result):
    let val = safety.unwrap(result)
    print val
end

# With default:
let val = safety.unwrap_or(result, 0)

# Chaining:
let doubled = safety.map(result, proc(x): return x * 2 end)
```

### Option API

| Function | Description |
|---|---|
| `Some(value)` | Wrap a value in an Option |
| `None()` | Create an empty Option |
| `is_some(opt)` | Check if Option contains a value |
| `is_none(opt)` | Check if Option is empty |
| `unwrap(opt)` | Extract value (panics if None) |
| `unwrap_or(opt, default)` | Extract value or return default |
| `unwrap_or_else(opt, fn)` | Extract value or compute default |
| `map(opt, fn)` | Transform contained value |
| `and_then(opt, fn)` | Flat-map (fn returns Option) |
| `or_else(opt, fn)` | Return self or compute fallback |
| `filter(opt, pred)` | Keep value only if predicate holds |
| `option_to_str(opt)` | Convert to "Some(...)" or "None" |

## 5. Fearless Concurrency

Types must implement **Send** (safe to transfer between threads) or **Sync** (safe to share between threads) to be used in concurrent contexts.

```sage
import safety

let shared_data = {"counter": 0}
shared_data = safety.mark_send(shared_data)  # OK to send to threads
shared_data = safety.mark_sync(shared_data)  # OK to share between threads

# The safety pass checks thread_spawn calls:
# thread_spawn(worker, shared_data)  # Requires shared_data is Send
```

Primitives (numbers, strings, booleans) are always `Send`.

## 6. Unsafe Barriers

The `unsafe:` block explicitly quarantines dangerous operations:

```sage
## @safe
proc kernel_map(phys_addr, size):
    unsafe:
        # Raw pointer operations allowed inside unsafe
        let page = alloc_page()
        map_memory(phys_addr, page, size)
        return page
    end
end
```

When `--strict-safety` is active, raw pointer operations outside `unsafe:` blocks produce hard errors.

## Safety Diagnostics

The safety pass produces rich error messages:

```
error[use-after-move]: use of moved value 'data' (moved to 'result' at line 5)
  --> script.sage:8
  = help: value was moved because it does not implement Copy

error[borrow-conflict]: cannot borrow 'buffer' as mutable: already borrowed as immutable
  --> script.sage:12
  = help: an immutable reference exists; cannot create mutable reference

error[no-nil]: nil is not allowed in safe context; use Option[T] instead
  --> script.sage:3
  = help: wrap the value in Some(value) or use None
```

## Architecture

```
Source → Lexer → Parser → AST → [Safety Pass] → [Optimization Passes] → Backend
                                      ↑
                          Decoupled analysis library
                          (include/safety.h + src/c/safety.c)
```

The safety pass:
- **Does not transform** the AST (read-only analysis)
- **Does not affect** the backend (invisible to C/LLVM/ASM codegen)
- **Runs as Pass 1** in the pass pipeline (after type checking, before optimizations)
- Has a matching **self-hosted implementation** (`src/sage/safety.sage`)

## Files

| Path | Description |
|---|---|
| `include/safety.h` | Safety system header (data structures, API) |
| `src/c/safety.c` | C implementation of the safety analysis pass |
| `src/sage/safety.sage` | Self-hosted safety analyzer |
| `lib/safety.sage` | Safety library (Option type, ownership markers, thread traits) |
| `tests/28_safety/` | Safety test suite |
