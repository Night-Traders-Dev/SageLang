## os.sync — Synchronization Primitives for SageOS
##
## Provides mutexes and other synchronization tools for concurrent
## and multi-core execution.

import metal.core

## Mutex structure -
##   state - pointer to an atomic value (0 = unlocked, 1 = locked)
##   owner - core ID or thread ID of the current holder (optional)

## Create a new mutex.
proc mutex_create():
    let m = {}
    m["state"] = atomic_new(0)
    return m
end

## Attempt to acquire the mutex without blocking.
## Returns true if acquired, false otherwise.
proc mutex_try_lock(m):
    return atomic_cas(m["state"], 0, 1)
end

## Acquire the mutex, busy-waiting until it becomes available.
proc mutex_lock(m):
    while not mutex_try_lock(m):
        # On bare-metal, we might want to hint the CPU or wait for an interrupt.
        # For the simulation, we can just yield or halt briefly.
        core.io_wait()
    end
end

## Release the mutex.
proc mutex_unlock(m):
    atomic_store(m["state"], 0)
end
