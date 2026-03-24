# SageLang Garbage Collector Guide

## Overview

SageLang uses a **concurrent tri-color mark-sweep** garbage collector with **SATB (Snapshot-At-The-Beginning) write barriers**, designed for sub-millisecond stop-the-world (STW) pauses.

## Design Goals

- **Sub-millisecond STW pauses**: Only two brief STW phases (root scan ~50-200us, remark ~20-50us)
- **Concurrent marking**: The mark phase runs alongside the mutator (application code)
- **Concurrent sweeping**: Dead objects are freed in small batches without stopping the mutator
- **Thread-safe**: All GC operations are mutex-protected for multi-threaded Sage programs
- **Works across all backends**: C interpreter, LLVM compiled, bytecode VM, and self-hosted

## Collection Phases

```text
Phase 1: ROOT SCAN (STW, ~50-200us)
    |  Snapshot all roots (environments, VM stack, modules)
    |  Shade root objects GRAY, enable write barrier
    v
Phase 2: CONCURRENT MARK (no STW)
    |  Process gray objects from mark stack
    |  Shade children gray, turn parent black
    |  Mutator runs freely; write barrier catches overwrites
    v
Phase 3: REMARK (STW, ~20-50us)
    |  Re-scan roots for new references
    |  Drain barrier-shaded objects
    |  Disable write barrier
    v
Phase 4: CONCURRENT SWEEP (no STW)
    |  Free WHITE objects in small batches (256 per step)
    |  Reset surviving objects to WHITE for next cycle
    v
IDLE (wait for next trigger)
```

## Tri-Color Invariant

Every object has one of three colors:

| Color | Meaning | State |
|-------|---------|-------|
| **WHITE** | Not yet reached by marker | Candidate for collection |
| **GRAY** | Reachable, but children not yet scanned | On the mark stack |
| **BLACK** | Reachable, all children scanned | Will survive this cycle |

The key invariant: **no BLACK object points directly to a WHITE object**. The SATB write barrier maintains this invariant during concurrent marking.

## SATB Write Barrier

When the mutator overwrites a reference field during concurrent marking, the **old value** is shaded gray before the write occurs:

```c
// Before: slot contains old_value (may be white)
// After:  slot contains new_value
GC_WRITE_BARRIER(old_value);  // shade old_value gray if white
slot = new_value;
```

This ensures the old value remains reachable for the current GC cycle, preventing premature collection. The trade-off is slight over-retention (floating garbage survives one extra cycle), which is acceptable for latency-sensitive applications.

### Write Barrier Insertion Points

| Location | Operation | Barrier |
|----------|-----------|---------|
| `env_define()` | Update existing variable | `GC_WRITE_BARRIER(old_value)` |
| `env_assign()` | Assign up scope chain | `GC_WRITE_BARRIER(old_value)` |
| `array_set()` | Overwrite array element | `GC_WRITE_BARRIER(old_element)` |
| `dict_set()` | Update existing dict entry | `GC_WRITE_BARRIER(old_value)` |
| `instance_set_field()` | Set instance property | Via `dict_set` barrier |

## Allocated-Black Invariant

Objects allocated during concurrent marking are born **BLACK**. This means they automatically survive the current GC cycle without needing to be traced. This avoids the need to track new allocations specially during marking.

## GC Triggering

Collection is triggered automatically when either threshold is exceeded:

- **Object count**: `gc.object_count >= gc.next_gc_objects`
- **Byte count**: `gc_live_bytes() >= gc.next_gc_bytes`

Thresholds adapt after each collection based on reclamation ratio:
- Low reclamation (<12.5%): shrink padding (collect sooner)
- High reclamation (>100% of live): grow padding (collect less often)

## API Reference

### Control Functions

```sage
gc_collect()    # Trigger a full collection cycle
gc_enable()     # Enable automatic GC
gc_disable()    # Disable automatic GC (manual collect still works)
```

### Statistics

```sage
let stats = gc_stats()
print stats["collections"]       # Number of GC cycles run
print stats["num_objects"]        # Current live object count
print stats["current_bytes"]      # Current managed memory in bytes
print stats["objects_freed"]      # Objects freed in last cycle
```

### Pinning

Pinning suppresses auto-collection during multi-step allocations where intermediate state may not be rooted:

```c
gc_pin();
// ... allocate multiple objects that reference each other ...
gc_unpin();
```

### Debug Mode

```c
gc_enable_debug();   // Print phase timing to stderr
gc_disable_debug();
```

With debug enabled, each collection prints:
```
[GC] Collection #42: root=150us mark=2300us remark=35us sweep=800us total=3285us freed=1247
```

## Performance Characteristics

| Metric | Target | Typical |
|--------|--------|---------|
| Root scan STW | < 500us | 50-200us |
| Remark STW | < 200us | 20-50us |
| Total STW per cycle | < 1ms | 70-250us |
| Mark throughput | N/A (concurrent) | ~500K objects/sec |
| Sweep throughput | N/A (concurrent) | ~1M objects/sec |
| Write barrier overhead | < 5% | ~2-3% |

## Implementation Files

| File | Role |
|------|------|
| `include/gc.h` | GCHeader, GC struct, mark stack, write barrier macros, phase constants |
| `src/c/gc.c` | Core implementation: phases, marking, sweeping, barriers, timing |
| `src/c/env.c` | Write barriers on `env_define` and `env_assign` |
| `src/c/value.c` | Write barriers on `array_set` and `dict_set` |
| `src/sage/gc.sage` | Self-hosted GC interface (phase constants, stats formatting) |

## Comparison with Previous GC

| Feature | Old GC | New GC |
|---------|--------|--------|
| Algorithm | Stop-the-world mark-sweep | Concurrent tri-color mark-sweep |
| STW pause | Entire mark + sweep | Root scan + remark only |
| Write barrier | None | SATB (snapshot-at-the-beginning) |
| New object color | Unmarked | Born BLACK during marking |
| Mark tracking | Single `marked` bit | Tri-color (WHITE/GRAY/BLACK) |
| Mark processing | Recursive | Explicit mark stack |
| Sweep mode | Full pass | Incremental (256 objects/step) |
| Pause timing | Not tracked | Nanosecond-precision per phase |
| Thread safety | Global mutex | Global mutex + barrier flag |
