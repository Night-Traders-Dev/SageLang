# Concurrency Guide

SageLang provides true multicore concurrency with threads, async/await, atomic
operations, POSIX semaphores, condition variables, read-write locks, and
SMP/hyperthreading detection.

## Threads

- `thread.spawn(proc, args...)` — Spawn a new thread running a procedure with pre-evaluated arguments
- `thread.join(t)` — Wait for thread completion and return its result
- `thread.mutex()` — Create a mutex for synchronization
- `thread.lock(m)` / `thread.unlock(m)` — Lock and unlock mutexes
- `thread.sleep(ms)` — Sleep for milliseconds
- `thread.id()` — Get current thread identifier
- **GC thread safety** — Garbage collector protected with pthread mutex

## Async / Await

- `async proc name():` — Declares an asynchronous procedure (sets `is_async` flag); calling it automatically spawns a background thread via `thread_spawn_native`
- `await future` — Joins the async thread and returns the result
- AST nodes: `STMT_ASYNC_PROC`, `EXPR_AWAIT`

```sage
async proc compute(x):
    return x * x

let future = compute(42)
print await future     # 1764
```

## Atomics (true `__atomic` builtins)

- `atomic_new(init)` — Create an atomic value
- `atomic_load(a)` — Atomically read
- `atomic_store(a, v)` — Atomically write
- `atomic_add(a, v)` — Atomic add
- `atomic_cas(a, exp, des)` — Compare-and-swap
- `atomic_exchange(a, v)` — Atomic exchange

Additional C-level operations: `sub`, `fetch_and`, `fetch_or`. Safe for
concurrent access across cores.

The `std.atomic` module is a thin wrapper over these builtins, so its
`atomic_int`, `atomic_flag`, and `create_spinlock` values are genuinely atomic
rather than simulated. `std.atomic.cas` maps to a single `atomic_cas`,
`test_and_set` to one `atomic_exchange`, `spin_lock` spins on a failed CAS, and
`spin_try_lock` is a single non-blocking CAS.

## Semaphores (POSIX)

- `sem_new(permits)` — Create a counting semaphore
- `sem_wait(s)` — Blocking wait (decrement)
- `sem_post(s)` — Post (increment)
- `sem_trywait(s)` — Non-blocking wait

## Condition Variables

`sage_cond_wait()`, `sage_cond_signal()`, `sage_cond_broadcast()` — C-level
`pthread_cond_t` primitives.

## Read-Write Locks

SageLang supports read-write locks both at the C VM runtime level (`sage_rwlock_rdlock()`, `sage_rwlock_wrlock()`) and in Sage OS primitives (`os.sync` / `std.rwlock`):

- **High-level std library (`import std.rwlock`)**: `create()`, `read_lock(l)`, `read_unlock(l)`, `write_lock(l)`, `write_unlock(l)`, `try_read_lock(l)`, `with_read(l, fn)`, `with_write(l, fn)`
- **Low-level OS synchronization (`import os.sync`)**: `rwlock_create()`, `rwlock_read_lock(l)`, `rwlock_read_unlock(l)`, `rwlock_try_read_lock(l)`, `rwlock_write_lock(l)`, `rwlock_write_unlock(l)`, `rwlock_try_write_lock(l)`

## SMP / Multicore Detection

- `cpu_count()` — Logical CPU count
- `cpu_physical_cores()` — Physical cores
- `cpu_has_hyperthreading()` — SMT detection
- `thread_set_affinity(core_id)` — Pin a thread to a core
- `thread_get_core()` — Current core index

The `lib/os/smp.sage` library provides higher-level multicore helpers:

- Topology: `topology()`, `cpu_count()`, `physical_cores()`, `has_hyperthreading()`
- Affinity: `pin_to_core(id)`, `current_core()`
- Per-CPU data: `per_cpu_array()`, `per_cpu_get()`, `per_cpu_set()`
- Work distribution: `parallel_for_cores(items, fn)`, `on_all_cores(fn)`
- IPI simulation: `send_to_core(core_id, fn)`

## Thread Safety

The GC mutex protects allocation and collection; environment list operations
are mutex-protected. All concurrency primitives have RP2040 stubs for
cross-platform compatibility.

The following shared runtime state is additionally synchronized, so a program
that spawns threads cannot corrupt the runtime itself:

| State | Protection |
| ----- | ---------- |
| LLVM runtime class and method registries | Mutex around register/lookup/resolve |
| LLVM runtime raw-memory registry | Mutex around alloc/read/write/free and cleanup registration |
| Emitted-C method table and class registry | Locked during dispatch and registration |
| GC mark-stack entry count | Atomic counter |
| GC mark phase (color transitions) | Atomic compare-and-swap |
| GC pin count | Atomic counter |
| GC string intern table | Bounded, and drained at shutdown |
| AST inline caches | Mutex on lookup and fill |
| VM generator and JIT state | Thread-local storage on hosted builds |
| Thread join | Atomic state machine |
| GC allocation accounting (`bytes_allocated` / `bytes_freed`) | Relaxed atomics; updated both under the GC mutex and lock-free from the growth path |
| Per-thread AST temp stacks | Atomic counts; a value pushed during concurrent mark is shaded (the write barrier cannot see stack pushes) |
| Per-thread stack-guard budget | Measured from the calling thread's real stack bounds, not `RLIMIT_STACK` |
| Interpreter GPU lifecycle (`initialize` / `shutdown`) | Serialized behind a recursive mutex; context bound to its owning thread |
| C GPU API (`gpu_api.c`, used by the LLVM runtime and ML backend) | Single lock around init/shutdown, the error string, device name, and platform override |

### GPU and Threads

**Do not drive the `gpu` module from more than one thread.** The interpreter's
GPU layer (`core/src/c/graphics.c`, the process-global `g_gpu_ctx`) is a single
shared context with ~135 native entry points and no per-call locking. This is
the same contract the underlying APIs impose: Khronos documents `VkDevice` and
OpenGL contexts as *externally synchronized*, meaning the application must
serialize access.

Since v4.2.9 the context is **bound to the thread that initialized it**, and
lifecycle calls are serialized behind a recursive mutex:

- `gpu.initialize()` / `gpu.shutdown()` from a thread other than the owner are
  refused with a diagnostic naming the offending call, instead of corrupting
  the context. Before this, the same code aborted with `SIGABRT` or crashed
  with `SIGSEGV` inside the Vulkan loader.
- The lock matters on its own: `g_gpu_ctx.initialized` only becomes true at the
  *end* of a successful init, so without mutual exclusion two threads could
  both observe "not initialized" and both build a context into the same
  globals.

The rest of the GPU surface (buffer/shader/pipeline creation, draw and submit)
is still not thread-safe. Confine all `gpu.*` calls to one thread — normally
the main thread — and hand results to workers through the normal concurrency
primitives (`channel`, `threadpool`, mutexes). Making the full surface
thread-safe is tracked as follow-up work.

The separate C GPU layer in `core/src/c/gpu_api.c` (used by the LLVM runtime
and the ML backend) does take an internal lock around its lifecycle and
error-state access.

### Verifying with ThreadSanitizer

A reproducible ThreadSanitizer build is available:

```bash
./sagemake --tsan              # CMake build into core/build_sage_tsan/
./sagemake --tsan --skip-tests # build only
```

`--tsan` configures a separate CMake tree, so it never clobbers the normal
build artifacts and both trees stay cache-warm. Equivalently, configure CMake
directly with `-DENABLE_TSAN=ON` (rejected on the Pico target), or use the Make
path with `CFLAGS_EXTRA`/`LDFLAGS_EXTRA`.

The thread, GC, async, JIT/AOT, and memory unit suites run clean under
ThreadSanitizer with this build.

## Standard Library Concurrency Modules

The `lib/std/` library also provides pure-Sage concurrency building blocks:
`atomic` (atomic ints/flags/spinlocks), `rwlock`, `condvar` (barriers/latches/
semaphores), `channel` (Go-style buffered channels), and `threadpool`
(work queue / parallel map / futures).
