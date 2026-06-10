## SageLang Current GC: Full Analysis

### What's Actually There

The README describes three GC modes selectable at runtime:

**Mode 1: Tri-color SATB (default)**

```
4-phase collection:
  Root scan     (STW, ~50-200us)
  Concurrent mark  ← pthread-based
  Remark        (STW, ~20-50us)
  Concurrent sweep
```

SATB = Snapshot-At-The-Beginning. Before overwriting any reference, the old value is shaded gray so the concurrent marker can't miss it. This is Go's GC design essentially.

**Mode 2: ARC** (`--gc:arc`) — non-atomic reference counting, Nim-style, no cycle collection.

**Mode 3: ORC** (`--gc:orc`) — ARC + Lins' trial deletion cycle collector. Recommended for async/complex graphs.

---

### Problem Map

**1. The default GC is incompatible with bare-metal by design**

The concurrent mark phase requires a live pthread. The GC mutex requires `pthread_mutex_t`. `SageMetal VM` — the entire bare-metal target — has to call `gc_disable()` before doing anything. This is a hard architectural conflict, not a configuration issue.

```c
// Every bare-metal boot script has to open with this
gc_disable()
import metal.core
// ...
```

That's not a working bare-metal GC. That's no GC.

**2. SATB write barrier fires on every pointer store**

Every assignment to a reference field during the concurrent mark window shades the old value gray. In REPL sessions that create dense short-lived objects — expression temporaries, loop variables, intermediate strings — this fires constantly. The barrier has non-trivial overhead when the mutation rate is high.

**3. Allocation is free-list based**

Tri-color mark-sweep doesn't compact. Objects are allocated from a free list; over long REPL sessions this fragments. Fragmentation hurts both allocation speed (longer free-list walks) and cache locality (objects of a function call scattered across heap).

**4. No generational structure**

The entire heap is scanned every collection cycle. The REPL workload is dominated by nursery-age objects — a `for` loop over 10,000 elements creates 10,000 integer values, most dying within the same expression. A flat tri-color scan treats these identically to long-lived class definitions.

**5. Self-hosted interpreter requires `gc_disable()`**

```
# Self-hosted code requirement from README
GC must be disabled for self-hosted code (gc_disable())
```

This is a significant correctness signal. Some reference pattern in the self-hosted interpreter confuses the current GC — likely pointer aliasing through `dict`-based values that the marker misidentifies. This means the most important non-trivial SageLang program can't run under the default GC.

**6. Three separate GC codepaths = maintenance overhead**

ARC, ORC, and tri-color SATB are three fundamentally different algorithms. Each has its own write barrier logic, allocation path, and `gc_collect()` behavior. Any change to the value system (adding a new `VAL_*` type, changing layout) has to be reflected in all three.

---

### Why Immix Fits SageLang

**The core insight:** Immix's block/line structure is heap-layout-first, algorithm-second. It separates "how memory is organized" from "how liveness is determined." That lets you plug in different marking strategies — STW for bare-metal, concurrent for REPL — while sharing the same allocator and heap structure.

**1. Block/line heap maps directly to bare-metal**

```
32KB blocks — pre-allocated from a fixed pool at boot
  └── 256 × 128B lines per block
       └── bump pointer within a line
```

On SageOS/SageMetal, you carve the heap out of the physical memory map once at boot. No `malloc`, no `sbrk`, no OS calls. The block pool is just a region of memory you've reserved.

```c
// Conceptual bare-metal Immix init
static uint8_t sage_heap[512 * 1024];  // 512KB pool
immix_init(sage_heap, sizeof(sage_heap));
```

**2. Bump-pointer allocation replaces free-list**

Current: `malloc()` or a linked free list — variable cost, fragmentation-prone.  
Immix: pointer bump within the current line — O(1), cache-local.

```c
// Allocation in Immix
if (cursor + size <= line_end) {
    ptr = cursor;
    cursor += size;      // bump, that's it
    return ptr;
}
// Else: find next free line, reset cursor
```

For the REPL that creates thousands of short-lived values per second, this is a significant win.

**3. Per-line mark bits = coarser, faster scan**

Current: each of SageLang's 16 `VAL_*` types has a mark bit in its header. Scanning visits every object.  
Immix: each 128B line has one mark byte. A line with any live object is retained; a line with no live objects is reclaimed as a unit.

```c
// Per-block line bitmap
uint8_t line_marks[256];  // one byte per line in the block
```

This collapses 128 bytes of objects into a single byte check during sweep. For blocks full of dead small objects (typical REPL garbage), sweep becomes a `memset`.

**4. STW mode for bare-metal — zero infrastructure**

Without evacuation and without concurrent marking, Immix is just:

```
1. Mark roots (stop)
2. Walk reachable objects, mark their lines
3. Find unmarked lines → they're free (resume)
4. Reset line marks
```

No threads. No barriers. No mutexes. Perfectly viable on SageMetal with a 264KB RP2040 heap.

**5. Optional evacuation for REPL defragmentation**

When running hosted, you can add opportunistic evacuation during the mark phase: if a block has mostly dead lines and a few survivors, copy the survivors to a fresh block and reclaim the old one. This is how Immix handles fragmentation that mark-sweep can't.

For bare-metal, you skip evacuation entirely — objects can't move because of C FFI raw pointers (`VAL_POINTER`, `VAL_CLIB`).

---

### Gap Analysis: Current vs. Immix

| Aspect | Current (tri-color SATB) | Immix (proposed) |
|---|---|---|
| Allocation path | Free list / `malloc` | Bump-pointer in line |
| Bare-metal viable | ❌ — requires `gc_disable()` | ✅ — STW mode, no threads |
| Write barrier | SATB on every pointer store | None (STW) / snapshot (concurrent) |
| Fragmentation | Accumulates over REPL sessions | Structural — line granularity |
| Generational support | None | Add nursery as small block overlay |
| Scan granularity | Per-object (all 16 `VAL_*` types) | Per-line (128B units) |
| Defragmentation | None | Opportunistic evacuation (hosted only) |
| Self-hosted compat | Broken — needs `gc_disable()` | Needs validation, but likely better |
| Thread infra needed | Yes (pthread, mutex) | No (STW), optional (concurrent) |
| GC modes to maintain | 3 (tracing, ARC, ORC) | 1 unified + optional RC overlay |
| Code surface | ~3× duplicated per-mode logic | Single allocator, swappable marker |

---

### Proposed Architecture

```
SageLang GC v2: Pluggable Marker over Immix Heap
─────────────────────────────────────────────────

Shared:
  immix_heap.c      ← block/line allocator, bump pointer
  gc_roots.c        ← root set management (stack, env, globals)
  gc_marks.c        ← line bitmap ops (set, test, sweep)

Marker backends (compile-time or runtime flag):
  gc_stw.c          ← stop-the-world for SageMetal/bare-metal
  gc_concurrent.c   ← SATB concurrent for hosted REPL
  gc_arc.c          ← ARC for --gc:arc (same heap, RC metadata)

Build targets:
  --compile-bare / SageMetal:  SAGE_GC=stw    → gc_stw.c
  --runtime bytecode/ast:      SAGE_GC=conc   → gc_concurrent.c
  --gc:arc:                    SAGE_GC=arc    → gc_arc.c
```

The key change: **all three modes share the same Immix heap**. The allocator, the block/line structure, and the sweep logic are identical. Only the mark phase differs.

---

### Migration Path

Since SageLang already has a clean GC public API (`gc_collect()`, `gc_stats()`, `gc_enable()`, `gc_disable()`, `gc_mode()`), a drop-in internal replacement is realistic:

1. Implement `immix_alloc()` as a replacement for the current `gc_alloc()` — bump-pointer in the current line, find-new-line on overflow
2. Add per-block line bitmaps alongside existing per-object mark bits (or replace them)
3. Implement `immix_mark_stw()` — roots → mark lines, no threads
4. Wire `--compile-bare` / SageMetal to use `immix_mark_stw()` unconditionally
5. Replace the SATB concurrent marker with Immix's snapshot-based concurrent marker
6. Remove the `gc_disable()` requirement from self-hosted code once the new marker validates correctly

The self-hosted `gc_disable()` issue is worth isolating first — if you can identify which value pattern confuses the current GC, that informs whether the bug is in the write barrier, the root scan, or the value graph traversal. Immix's simpler line-level marking would likely sidestep it.

Here is a comprehensive `PLAN.md` for implementing and migrating SageLang to Immix:

***

```markdown
# PLAN.md — SageLang GC v2: Immix Migration

**Target:** Replace the tri-color SATB / ARC / ORC triad with a unified
Immix heap, shared across all three build targets (SageMetal, hosted REPL,
`--gc:arc`). The public GC API (`gc_collect`, `gc_stats`, `gc_enable`,
`gc_disable`, `gc_mode`) remains unchanged.

---

## Phase 0 — Baseline Measurement & Archaeology

Before writing a single new file, capture ground-truth numbers and isolate
the known bugs. Every future claim about improvement needs a before/after
delta.

### 0.1 — Instrument the Current Allocator

Add counters to the existing `gc_alloc()` path:

```c
typedef struct {
    uint64_t alloc_calls;
    uint64_t alloc_bytes;
    uint64_t free_list_walk_steps; // steps per alloc_call
    uint64_t collections;
    uint64_t live_bytes_after_collect;
    uint64_t barrier_fires;        // SATB write barrier invocations
} GCStats;
```

Expose via `gc_stats()`. Run the REPL against a benchmark (dense loop,
10 000-element list, string concatenation chain) and record baseline
numbers. These are your migration success criteria.

### 0.2 — Isolate the Self-Hosted `gc_disable()` Bug

Create a minimal reproducer: the smallest SageLang program that crashes
or produces wrong results under the default GC without `gc_disable()`.
Binary-search through the self-hosted interpreter until you find the
specific `VAL_*` type or dict-traversal pattern that confuses the marker.
Document it in `bugs/satb-self-hosted.md`. This feeds Phase 3 directly.

### 0.3 — Map Every Allocation Site

`grep -rn gc_alloc` across the VM codebase. Categorise each site:
- **Short-lived temporaries** (loop vars, expression intermediates)
- **Medium-lived frames** (function call stack frames, env dicts)
- **Long-lived roots** (class definitions, module globals)

This tells you which block/line sizes matter most in practice.

---

## Phase 1 — Immix Heap Core (`immix_heap.c`)

This is the foundation everything else builds on. No marking logic yet —
just the allocator and block/line data structures.

### 1.1 — Block and Line Layout

```c
// immix_config.h
#define IMMIX_BLOCK_SIZE   (32 * 1024)      // 32 KB
#define IMMIX_LINE_SIZE    128               // bytes
#define IMMIX_LINES_PER_BLOCK (IMMIX_BLOCK_SIZE / IMMIX_LINE_SIZE)  // 256

// Block header lives in the first few lines of the block
typedef struct ImmixBlock {
    uint8_t  line_marks[IMMIX_LINES_PER_BLOCK]; // 256 bytes
    uint8_t  block_mark;                        // live/dead
    uint8_t  evacuation_candidate;              // hosted only
    uint16_t free_lines;                        // count of unmarked lines
    struct ImmixBlock *next;                    // free-block list link
    uint8_t  data[];                            // actual object data
} ImmixBlock;
```

The line mark array lives inside the block itself, so a bare-metal
static array of blocks requires no separate metadata region.

### 1.2 — Heap Initialization

Two init paths, same internal layout:

```c
// Hosted: ask the OS
void immix_init_hosted(size_t initial_bytes);

// Bare-metal: caller supplies a pre-carved memory region
void immix_init_static(void *pool, size_t pool_size);
```

`immix_init_static` on SageMetal looks like:

```c
static uint8_t sage_heap[512 * 1024];   // RP2040: 264KB usable SRAM
immix_init_static(sage_heap, sizeof(sage_heap));
```

The pool is divided into `N = pool_size / IMMIX_BLOCK_SIZE` blocks.
All blocks start on the free-block list. Cursor and limit start at NULL —
no current block until first allocation.

### 1.3 — Bump-Pointer Allocation

```c
// Thread-local allocator state (or global for bare-metal single-core)
typedef struct {
    uint8_t *cursor;        // next free byte in current line
    uint8_t *line_end;      // end of current line (cursor + 128)
    ImmixBlock *current_block;
    int current_line;
} ImmixAllocator;

void *immix_alloc(ImmixAllocator *a, size_t size) {
    if (size > IMMIX_LINE_SIZE) {
        return immix_alloc_large(size);   // overflow object: spans lines
    }
    if (a->cursor + size <= a->line_end) {
        void *ptr = a->cursor;
        a->cursor += size;
        return ptr;
    }
    return immix_alloc_slow(a, size);   // find next free line
}
```

`immix_alloc_slow` scans the current block's `line_marks` for the next
unmarked line, resets cursor/line_end, and retries. If the block is
exhausted, it pulls the next free block from the pool.

### 1.4 — Large Object Handling

Any object larger than `IMMIX_LINE_SIZE` (128 bytes) gets its own
span of contiguous lines. The object header records how many lines it
occupies. This is rare for SageLang values (most `VAL_*` types are
well under 128 bytes), but `VAL_STRING` with large payloads and
`VAL_ARRAY` headers need it.

### 1.5 — Deliverables for Phase 1

- `src/gc/immix_heap.c` + `include/immix_heap.h`
- `src/gc/immix_config.h` (sizes, compile-time flags)
- Unit test: allocate 1000 objects, verify no overlap, verify cursor
  advances correctly, verify slow path triggers on line overflow.

---

## Phase 2 — STW Marker (`gc_stw.c`) — SageMetal Target First

Start with the simplest marker. No threads, no barriers, just roots →
mark → sweep. This validates the heap structure before adding complexity.

### 2.1 — Root Set

```c
// gc_roots.c
typedef struct GCRootList {
    SageValue **roots;
    size_t      count;
    size_t      capacity;
} GCRootList;

void gc_root_push(SageValue **slot);
void gc_root_pop(SageValue **slot);
void gc_root_scan(MarkFn mark_fn);   // called by each marker backend
```

Stack roots are registered explicitly on function entry/exit. This is
already how SageLang works — extend to also handle env dicts and
module globals in a single unified pass.

### 2.2 — Mark Phase

```c
// gc_stw.c
static void mark_value(SageValue *v);

static void mark_object(SageValue *v) {
    // find the block and line this pointer lives in
    ImmixBlock *block = immix_block_of(v);
    int line = immix_line_of(block, v);

    if (block->line_marks[line]) return;   // already marked
    block->line_marks[line] = 1;

    // conservative: mark next line too if object could cross boundary
    if ((uint8_t*)v + sage_value_size(v) > immix_line_start(block, line+1))
        block->line_marks[line + 1] = 1;

    // recurse into children based on VAL_* tag
    switch (v->type) {
        case VAL_DICT:    mark_dict(v);   break;
        case VAL_LIST:    mark_list(v);   break;
        case VAL_FUNC:    mark_func(v);   break;
        case VAL_CLOSURE: mark_closure(v); break;
        // VAL_INT, VAL_FLOAT, VAL_BOOL, VAL_NONE: no children
        // VAL_POINTER, VAL_CLIB: mark header only, don't follow raw ptr
    }
}
```

The key insight for `VAL_POINTER` / `VAL_CLIB`: mark the SageLang header
object (so it isn't swept), but never chase the raw C pointer. This is
precisely why evacuation is disabled for bare-metal — raw C pointers
can't be updated if the object moves.

### 2.3 — Sweep Phase

```c
static void sweep_blocks(void) {
    for each block in all_blocks:
        block->free_lines = 0;
        for (int i = 0; i < IMMIX_LINES_PER_BLOCK; i++) {
            if (!block->line_marks[i]) {
                block->free_lines++;
                // line is available — no action needed, bump alloc will use it
            }
        }
        // reset marks for next cycle
        memset(block->line_marks, 0, IMMIX_LINES_PER_BLOCK);
        if (block->free_lines == IMMIX_LINES_PER_BLOCK)
            return_block_to_free_list(block);
}
```

That's the entire sweep. No per-object free-list insertion, no header
patching — just counting bytes in a bitmap and possibly a `memset`.

### 2.4 — Wire to `gc_collect()`

```c
// gc.c — the public API
void gc_collect(void) {
#if SAGE_GC == GC_STW
    gc_root_scan(mark_object);
    sweep_blocks();
#elif SAGE_GC == GC_CONC
    // Phase 3
#elif SAGE_GC == GC_ARC
    // Phase 4
#endif
}
```

### 2.5 — SageMetal Integration

Remove `gc_disable()` from every bare-metal boot script and replace with:

```c
// metal/boot.c
immix_init_static(sage_heap, sizeof(sage_heap));
gc_set_mode(GC_STW);
// no gc_disable() needed — STW mode is valid for bare-metal
```

### 2.6 — Deliverables for Phase 2

- `src/gc/gc_stw.c` + `src/gc/gc_roots.c`
- `src/gc/gc_marks.c` (shared `immix_block_of`, `immix_line_of`,
  `immix_line_start` helpers)
- SageMetal boot no longer calls `gc_disable()`
- All existing bare-metal tests pass under `SAGE_GC=stw`

---

## Phase 3 — Self-Hosted Interpreter Fix

The self-hosted interpreter bug identified in Phase 0.2 is fixed here,
before tackling the concurrent marker. Reason: the STW marker is simple
enough that if the bug persists, it's definitively in the root scan or
value graph — not the barrier.

### 3.1 — Run Self-Hosted Under STW

Enable the self-hosted interpreter with `SAGE_GC=stw`. If it crashes:
- Check `gc_root_scan` — are env dicts being registered as roots?
- Check `mark_dict` — is every key and value in a `VAL_DICT` being
  recursively marked?
- Check `VAL_FUNC` and `VAL_CLOSURE` — are upvalue references being
  followed?

### 3.2 — Fix and Document

Any fix here also fixes the failure under the future concurrent marker
since both share `gc_roots.c`. Document the root cause in
`bugs/satb-self-hosted.md` (opened in Phase 0.2).

---

## Phase 4 — Concurrent Marker (`gc_concurrent.c`) — Hosted REPL

The concurrent marker runs in a pthread during REPL/bytecode execution.
It shares the Immix heap with `gc_stw.c` — only the mark phase changes.

### 4.1 — Snapshot-at-Beginning (SATB) on Immix

SATB over line bitmaps is simpler than SATB over per-object headers:

```c
// Write barrier: fires when a pointer field is overwritten
// Only active during the concurrent mark window
void immix_write_barrier(SageValue **slot, SageValue *new_val) {
    if (gc_marking_active) {
        SageValue *old_val = *slot;
        if (old_val && !immix_line_marked(old_val)) {
            // shade old value gray: push to mark stack
            mark_stack_push(old_val);
        }
    }
    *slot = new_val;
}
```

The write barrier only fires during the concurrent mark window, not
during normal allocation. This is less intrusive than the current SATB
which fires on every pointer store unconditionally.

### 4.2 — Four-Phase Structure (Matching Current Architecture)

```
1. Initial mark      (STW, ~50us)  — roots only, set gc_marking_active
2. Concurrent mark   (pthread)     — walk heap, fire write barriers
3. Final remark      (STW, ~20us)  — drain mark stack, clear gc_marking_active
4. Concurrent sweep  (pthread)     — walk line bitmaps, update free_lines
```

The structure is identical to the current SATB GC, but sweep is now a
bitmap walk instead of a free-list rebuild.

### 4.3 — Deliverables for Phase 4

- `src/gc/gc_concurrent.c`
- REPL benchmark shows allocation latency ≤ baseline (target: better
  due to bump-pointer replacing free-list walk)
- Write barrier fire rate lower than baseline (verify with `gc_stats()`)

---

## Phase 5 — RC Immix (`gc_arc.c`) — `--gc:arc` Mode

ARC on an Immix heap is well-studied — this is RC Immix from the 2013
Blackburn/McKinley paper. The key insight: per-line live-object counts
replace the free-list. When a line's live count drops to zero, it's
immediately available for reuse without a trace cycle.

### 5.1 — Per-Line Reference Count

```c
typedef struct ImmixBlock {
    // ... existing fields ...
    uint16_t line_live_count[IMMIX_LINES_PER_BLOCK]; // RC Immix addition
} ImmixBlock;
```

On increment: `line_live_count[line_of(v)]++`
On decrement to zero: `line_live_count[line_of(v)]--`; if count == 0,
the line is immediately recyclable. No trace needed for acyclic graphs.

### 5.2 — Cycle Collection

Keep Lins' trial deletion (existing ORC logic) as an optional overlay
on top of RC Immix. If `--gc:orc` is also specified, the trial deletion
cycle collector fires periodically on objects with non-zero RC that have
been in the "potential cycle" list. This reuses existing ORC code — you
only replace the heap layout under it.

### 5.3 — Deliverables for Phase 5

- `src/gc/gc_arc.c` (RC Immix over Immix heap)
- `--gc:arc` passes all existing ARC regression tests
- Line-level live counts validate against per-object reference counts
  (assert during debug builds)

---

## Phase 6 — Opportunistic Evacuation (Hosted Only)

Evacuation is the defragmentation mechanism that separates Immix from
plain mark-region. It is **only enabled for hosted builds** —
`VAL_POINTER` and `VAL_CLIB` preclude moving objects on bare-metal.

### 6.1 — Evacuation Candidate Selection

After sweep, any block where:

```
free_lines / IMMIX_LINES_PER_BLOCK < EVAC_THRESHOLD   // e.g. 0.5
```

...is marked as an evacuation candidate. Survivors are copied to fresh
blocks. The original block is reclaimed wholesale.

### 6.2 — Pointer Fixup

Requires a forwarding pointer in each object header (1 pointer-width):

```c
typedef struct SageObjectHeader {
    uint8_t    type;           // VAL_* tag
    uint8_t    flags;          // gc flags
    void      *forward;        // NULL normally; set during evacuation
} SageObjectHeader;
```

All pointers to evacuated objects are updated via root scan +
heap-walk. This pass runs at the end of the concurrent mark phase
before `gc_marking_active` is cleared.

### 6.3 — Guard: No Evacuation for Raw Pointer Types

```c
bool immix_can_evacuate(SageValue *v) {
    return v->type != VAL_POINTER && v->type != VAL_CLIB;
}
```

Any block containing a `VAL_POINTER` or `VAL_CLIB` is immediately
excluded from the evacuation candidate list.

### 6.4 — Deliverables for Phase 6

- Evacuation controlled by `SAGE_GC_EVAC=1` build flag (off by default)
- REPL long-session fragmentation benchmark shows improvement
- SageMetal build never compiles evacuation code (`#ifndef SAGE_GC_EVAC`)

---

## Phase 7 — Generational Nursery Overlay (Optional / Post-MVP)

Immix is semi-generational by default ("Sticky Immix") — young objects
stay in their blocks until the block is reclaimed, creating an implicit
generation. An explicit nursery adds a small bump-pointer region that
is collected at higher frequency.

### 7.1 — Nursery Design

```
Nursery: 2–4 Immix blocks (64–128 KB)
  └── Bump allocation into fresh lines
  └── Minor GC: scan nursery roots only
  └── Survivors: promote to mature Immix space (copy to regular block)
Major GC: full Immix collect on mature space (triggered by nursery fill rate)
```

For the REPL workload (10 000-element loops creating 10 000 integers
per expression), almost all nursery objects die in the minor GC —
the major GC almost never needs to run.

### 7.2 — Write Barrier for Intergenerational Pointers

Mature objects pointing into the nursery must be tracked (remembered
set). On every write to a mature object's pointer field:

```c
if (is_mature(container) && is_nursery(new_val)) {
    remembered_set_add(container);
}
```

This is the only additional write barrier cost introduced by the nursery.

---

## Phase 8 — Cleanup & Consolidation

### 8.1 — Remove Tri-Color SATB Infrastructure

Once Phase 4 is validated:
- Delete `src/gc/gc_tricolor.c` (or equivalent)
- Delete `pthread_mutex_t` from GC internals
- Remove SATB per-object mark bits from `SageValue` headers (reclaim space)
- Delete the three-way `#ifdef` maze in the current `gc_collect()`

### 8.2 — Remove `gc_disable()` Requirement

- Remove from all bare-metal boot scripts (already done in Phase 2)
- Remove from self-hosted interpreter (done in Phase 3)
- Deprecate the `gc_disable()` API or repurpose as "pause for
  critical section" (a 1-line `gc_marking_active = 0` toggle)

### 8.3 — Unified `gc_stats()` Output

```c
typedef struct GCStatsV2 {
    // Heap layout
    size_t   total_blocks;
    size_t   free_blocks;
    size_t   total_lines;
    size_t   free_lines;

    // Collection performance
    uint64_t collections;
    uint64_t minor_collections;   // nursery, if enabled
    uint64_t evac_candidates;     // blocks evacuated, if enabled
    double   avg_stw_us;          // mean STW pause time

    // Allocation throughput
    uint64_t alloc_calls;
    uint64_t alloc_bytes;
    uint64_t barrier_fires;       // write barrier, concurrent mode only
} GCStatsV2;
```

---

## File Layout After Migration

```
src/gc/
  immix_config.h        ← block/line sizes, compile-time flags
  immix_heap.c/.h       ← block pool, bump allocator, large object alloc
  gc_marks.c/.h         ← line bitmap ops: set, test, sweep, block_of, line_of
  gc_roots.c/.h         ← root set: push/pop/scan
  gc_stw.c/.h           ← stop-the-world marker (SageMetal + bare-metal)
  gc_concurrent.c/.h    ← SATB concurrent marker (hosted REPL)
  gc_arc.c/.h           ← RC Immix (--gc:arc)
  gc_evac.c/.h          ← opportunistic evacuation (hosted, opt-in)
  gc_nursery.c/.h       ← generational nursery (post-MVP)
  gc.c/.h               ← public API: gc_collect, gc_stats, gc_enable, etc.

include/
  sage_gc.h             ← public header (unchanged API)

bugs/
  satb-self-hosted.md   ← Phase 0.2 root-cause analysis
```

---

## Build Flags

| Target | `SAGE_GC` | `SAGE_GC_EVAC` | Notes |
|---|---|---|---|
| SageMetal (RP2040) | `stw` | `0` | No threads, no evacuation |
| Hosted bytecode | `conc` | `1` | Full Immix |
| `--gc:arc` | `arc` | `0` | RC Immix, no evacuation |
| Debug / testing | `stw` | `0` | Deterministic, easy to debug |

---

## Success Criteria

| Metric | Target |
|---|---|
| SageMetal boots without `gc_disable()` | ✅ Required |
| Self-hosted interpreter runs without `gc_disable()` | ✅ Required |
| REPL alloc latency vs. baseline | ≤ 1.0× (target ≤ 0.7×) |
| REPL fragmentation after 10 000-obj loop × 100 cycles | < 5% wasted lines |
| GC codepath count | 1 allocator + 3 marker backends |
| Bare-metal STW pause for 512KB heap | < 500µs |
| Write barrier fire rate (REPL, concurrent mode) | < 10% of alloc rate |
```

***

The plan above has eight sequential phases, each with discrete deliverables and roll-back points. [1] Immix's block/line model — 32KB blocks subdivided into 128-byte lines with a single mark byte per line — means sweep degenerates to a bitmap memset over dead blocks rather than a per-object free-list walk, which is the core allocation win for your REPL workload. [2] The bump-pointer path is also far faster than your current free-list because thread-local allocation simply increments a cursor without synchronization.

## Key Sequencing Rationale

The order matters: Phase 2 (STW) before Phase 4 (concurrent) is deliberate — the STW marker is simple enough to formally validate the heap structure in isolation. [3] The self-hosted `gc_disable()` fix sits in Phase 3 specifically because if it passes under STW (which has no write barrier at all), the bug is definitively in root scanning or value graph traversal, not in barrier correctness — that narrows your search space enormously before you add concurrent marking complexity. [4] RC Immix (Phase 5) reuses the same block/line heap under your existing `--gc:arc` flag, replacing only the free-list with per-line live counts — this is the approach from the 2013 Blackburn/McKinley RC Immix paper, which demonstrates it closes the performance gap with generational collectors.

## Bare-Metal Constraint Preservation

The evacuation guard in Phase 6 (`immix_can_evacuate` returning false for `VAL_POINTER` and `VAL_CLIB`) is non-negotiable. [1] Full Immix moves live objects out of fragmented blocks into fresh ones, which requires updating every pointer to the moved object — but a `VAL_CLIB` handle or `VAL_POINTER` may be held by C-side code outside the GC's visibility, making pointer fixup impossible. The simplest enforcement is block-level: any block containing a pinned type is permanently excluded from the evacuation candidate list, not just the specific object.

