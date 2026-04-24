## os.smp — SMP, Multicore, and Hyperthreading Support for Sage
##
## Provides CPU topology detection, core affinity, per-CPU data structures,
## and multicore work distribution primitives.
##
## All functions delegate to C-level sage_thread_* primitives that use
## sysconf, /proc/cpuinfo, sched_setaffinity, and sched_getcpu.

import thread

## ============================================================
## CPU Topology Detection
## ============================================================

## Returns the number of logical processors (including hyperthreads)
proc cpu_count():
    return cpu_count()

## Returns the number of physical cores (excluding hyperthreads)
proc physical_cores():
    return cpu_physical_cores()

## Returns true if hyperthreading (SMT) is detected
proc has_hyperthreading():
    return cpu_has_hyperthreading()

## Returns a dict describing the CPU topology
proc topology():
    let logical = cpu_count()
    let physical = cpu_physical_cores()
    let ht = cpu_has_hyperthreading()
    return {
        "logical_cpus": logical,
        "physical_cores": physical,
        "hyperthreading": ht,
        "threads_per_core": logical / physical,
        "current_core": thread_get_core()
    }

## ============================================================
## Core Affinity
## ============================================================

## Pin the current thread to a specific core
proc pin_to_core(core_id):
    return thread_set_affinity(core_id)

## Get the core the current thread is running on
proc current_core():
    return thread_get_core()

## ============================================================
## Per-CPU Data Structures
## ============================================================

## Create a per-CPU array (one slot per logical CPU)
proc per_cpu_array(initial_value):
    let n = cpu_count()
    let arr = []
    let i = 0
    while i < n:
        push(arr, initial_value)
        i = i + 1
    return arr

## Get the value for the current CPU
proc per_cpu_get(arr):
    let core = thread_get_core()
    if core >= 0 and core < len(arr):
        return arr[core]
    return arr[0]

## Set the value for the current CPU
proc per_cpu_set(arr, value):
    let core = thread_get_core()
    if core >= 0 and core < len(arr):
        arr[core] = value

## ============================================================
## Multicore Work Distribution
## ============================================================

## Distribute work across N cores. Spawns one thread per core,
## each running worker_fn(core_id, work_slice).
## Returns array of results.
proc parallel_for_cores(items, worker_fn):
    let n = cpu_count()
    let total = len(items)
    if total == 0:
        return []
    let chunk_size = total / n
    if chunk_size == 0:
        chunk_size = 1
        n = total
    let threads = []
    let i = 0
    while i < n:
        let start = i * chunk_size
        let end = start + chunk_size
        if i == n - 1:
            end = total
        if start >= total:
            break
        let slice_items = slice(items, start, end)
        let t = thread.spawn(worker_fn, i, slice_items)
        push(threads, t)
        i = i + 1
    # Join all threads and collect results
    let results = []
    i = 0
    while i < len(threads):
        let result = thread.join(threads[i])
        push(results, result)
        i = i + 1
    return results

## Run a function on every core in parallel.
## Returns array of results, one per core.
proc on_all_cores(fn):
    let n = cpu_count()
    let threads = []
    let i = 0
    while i < n:
        let t = thread.spawn(fn, i)
        push(threads, t)
        i = i + 1
    let results = []
    i = 0
    while i < len(threads):
        push(results, thread.join(threads[i]))
        i = i + 1
    return results

## ============================================================
## IPI Simulation (Inter-Processor Interrupt)
## ============================================================
## On hosted environments, IPIs are simulated via thread signaling.
## On bare-metal, these would map to actual APIC/GIC IPIs.

## Send a "task" to a specific core (spawns thread pinned to that core)
proc send_to_core(core_id, fn):
    let wrapper = proc(cid, work_fn):
        pin_to_core(cid)
        return work_fn()
    return thread.spawn(wrapper, core_id, fn)

## ============================================================
## CPU Feature Detection Helpers
## ============================================================

## Get architecture string
proc arch():
    return asm_arch()

## Detect SIMD support (architecture-dependent)
proc has_simd():
    let a = asm_arch()
    if a == "x86_64":
        return true
    if a == "aarch64":
        return true
    return false

## Print topology summary
proc print_topology():
    let t = topology()
    print("CPU Topology:")
    print("  Logical CPUs:      " + str(t["logical_cpus"]))
    print("  Physical Cores:    " + str(t["physical_cores"]))
    print("  Hyperthreading:    " + str(t["hyperthreading"]))
    print("  Threads/Core:      " + str(t["threads_per_core"]))
    print("  Current Core:      " + str(t["current_core"]))
    print("  Architecture:      " + arch())
