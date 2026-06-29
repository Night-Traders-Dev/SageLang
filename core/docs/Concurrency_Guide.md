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

## Semaphores (POSIX)

- `sem_new(permits)` — Create a counting semaphore
- `sem_wait(s)` — Blocking wait (decrement)
- `sem_post(s)` — Post (increment)
- `sem_trywait(s)` — Non-blocking wait

## Condition Variables

`sage_cond_wait()`, `sage_cond_signal()`, `sage_cond_broadcast()` — C-level
`pthread_cond_t` primitives.

## Read-Write Locks

`sage_rwlock_rdlock()`, `sage_rwlock_wrlock()` — concurrent readers, exclusive
writers. Also `tryrdlock` / `trywrlock` / `unlock`.

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

## Standard Library Concurrency Modules

The `lib/std/` library also provides pure-Sage concurrency building blocks:
`atomic` (atomic ints/flags/spinlocks), `rwlock`, `condvar` (barriers/latches/
semaphores), `channel` (Go-style buffered channels), and `threadpool`
(work queue / parallel map / futures).
