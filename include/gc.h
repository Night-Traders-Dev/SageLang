// include/gc.h
// Concurrent Tri-Color Mark-Sweep Garbage Collector for SageLang
// Sub-millisecond STW pauses via SATB write barriers and concurrent marking

#ifndef SAGELANG_GC_H
#define SAGELANG_GC_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "value.h"
#include "env.h"

// GC configuration
#define GC_HEAP_SIZE (1024 * 1024)        // 1MB heap
#define GC_MIN_TRIGGER_OBJECTS 128        // Minimum live objects before auto-GC
#define GC_MIN_TRIGGER_BYTES (64 * 1024)  // Minimum managed bytes before auto-GC
#define GC_MARK_STACK_INIT 4096           // Initial mark stack capacity
#define GC_SWEEP_BATCH 256                // Objects per incremental sweep step

// Safe allocation macro - aborts with diagnostic on OOM
#define SAGE_ALLOC(size) sage_safe_malloc(size, __FILE__, __LINE__)
#define SAGE_REALLOC(ptr, size) sage_safe_realloc(ptr, size, __FILE__, __LINE__)

static inline void* sage_safe_malloc(size_t size, const char* file, int line) {
    if (size == 0) size = 1;
    void* ptr = calloc(1, size);
    if (ptr == NULL) {
        fprintf(stderr, "Fatal: Out of memory allocating %zu bytes at %s:%d\n", size, file, line);
        abort();
    }
    return ptr;
}

static inline void* sage_safe_realloc(void* old, size_t size, const char* file, int line) {
    void* ptr = realloc(old, size);
    if (ptr == NULL && size > 0) {
        fprintf(stderr, "Fatal: Out of memory reallocating %zu bytes at %s:%d\n", size, file, line);
        abort();
    }
    return ptr;
}

static inline char* sage_safe_strdup(const char* str, const char* file, int line) {
    if (str == NULL) return NULL;
    char* ptr = strdup(str);
    if (ptr == NULL) {
        fprintf(stderr, "Fatal: Out of memory in strdup at %s:%d\n", file, line);
        abort();
    }
    return ptr;
}
#define SAGE_STRDUP(str) sage_safe_strdup(str, __FILE__, __LINE__)

// ============================================================================
// Tri-color marking
// ============================================================================

// Object colors for concurrent tri-color marking
#define GC_WHITE 0   // Not yet reached (candidate for collection)
#define GC_GRAY  1   // Reachable, children not yet scanned
#define GC_BLACK 2   // Reachable, all children scanned

// GC phases
#define GC_PHASE_IDLE           0  // No collection in progress
#define GC_PHASE_ROOT_SCAN      1  // STW: snapshot roots (brief)
#define GC_PHASE_CONCURRENT_MARK 2 // Concurrent: process gray objects
#define GC_PHASE_REMARK         3  // STW: process barrier-shaded objects (brief)
#define GC_PHASE_SWEEP          4  // Concurrent: free white objects

// GC modes
#define GC_MODE_TRACING  0   // Default: concurrent tri-color mark-sweep
#define GC_MODE_ARC      1   // Nim-style ARC: reference counting + cycle collector

// GC object header (prepended to all allocated objects)
// IMPORTANT: Do not change this struct layout — it affects heap alignment for all allocations.
typedef struct {
    int color;            // Tri-color: GC_WHITE, GC_GRAY, GC_BLACK
    int type;             // Object type (VAL_STRING, VAL_ARRAY, etc.)
    size_t size;          // Bytes owned directly by this object payload
    void* next;           // Next object in linked list
} GCHeader;

// ARC metadata stored in a separate side-table (avoids changing GCHeader size)
typedef struct ARCMeta {
    int ref_count;        // Reference count
    int buffered;         // In cycle candidate buffer
} ARCMeta;

// Backward compat: "marked" maps to color != WHITE
#define gc_header_marked(h) ((h)->color != GC_WHITE)

// GC Statistics struct (for gc_stats native function)
typedef struct {
    unsigned long bytes_allocated;
    unsigned long current_bytes;
    int num_objects;
    int collections;
    int objects_freed;
    int next_gc;
    unsigned long next_gc_bytes;
    unsigned long max_pause_ns;       // Worst-case STW pause in nanoseconds
    unsigned long last_mark_ns;       // Last mark phase duration
    unsigned long last_sweep_ns;      // Last sweep phase duration
    int phase;                        // Current GC phase
} GCStats;

// Mark stack for concurrent gray-object processing
typedef struct {
    void** items;       // Array of GCHeader pointers
    int count;
    int capacity;
} GCMarkStack;

// Garbage collector state
typedef struct {
    void* objects;              // Linked list of all objects
    int object_count;
    int objects_since_gc;
    int collections;
    int marked_count;
    int freed_count;
    unsigned long bytes_allocated;
    unsigned long bytes_freed;
    unsigned long next_gc_bytes;
    int next_gc_objects;
    int enabled;
    int pin_count;

    // Concurrent GC state
    int phase;                  // Current GC phase
    GCMarkStack mark_stack;     // Gray objects pending scan
    int barrier_active;         // Write barrier enabled during marking

    // Timing (nanoseconds)
    unsigned long last_root_scan_ns;
    unsigned long last_mark_ns;
    unsigned long last_remark_ns;
    unsigned long last_sweep_ns;
    unsigned long max_pause_ns;

    // Sweep cursor for incremental sweep
    void* sweep_cursor;         // Current position in object list during sweep
    void** sweep_prev;          // Pointer to previous node's next field

    // ARC mode state
    int mode;                   // GC_MODE_TRACING or GC_MODE_ARC
    void** cycle_buffer;        // Trial deletion candidates for cycle collection
    int cycle_buffer_count;
    int cycle_buffer_capacity;
    int arc_decrements;         // Decrements since last cycle collection
    int arc_cycle_threshold;    // Trigger cycle collection after N decrements
    // ARC side-table: maps GCHeader* → ARCMeta (simple linked list for now)
    void* arc_table;            // Hash table of ARCMeta entries
} GC;

// Global GC instance
extern GC gc;

// Thread safety for GC
void gc_lock(void);
void gc_unlock(void);

// Core GC functions
void gc_init(void);
void gc_shutdown(void);
void gc_collect(void);
void gc_collect_with_root(Env* root_env);

// Concurrent GC phases (called internally or for fine-grained control)
void gc_begin_cycle(Env* root_env);   // STW: snapshot roots -> gray
void gc_mark_step(int max_objects);    // Concurrent: process N gray objects
int  gc_mark_complete(void);           // True when mark stack is empty
void gc_remark(Env* root_env);        // STW: drain barrier-shaded objects
void gc_sweep_step(int max_objects);   // Concurrent: sweep N objects
int  gc_sweep_complete(void);          // True when sweep cursor is exhausted

// Legacy mark/sweep (used when concurrent mode is not active)
void gc_mark(void);
void gc_mark_from_root(Env* root_env);
void gc_sweep(void);

// GC pinning
void gc_pin(void);
void gc_unpin(void);

// Memory allocation
void* gc_alloc(int type, size_t size);
void gc_free(void* obj);

// Track auxiliary heap buffers
void gc_track_external_allocation(size_t size);
void gc_track_external_resize(size_t old_size, size_t new_size);
void gc_track_external_free(size_t size);

// ============================================================================
// Write Barrier (SATB - Snapshot At The Beginning)
// ============================================================================

// Call BEFORE overwriting a reference field.
// If a concurrent mark is in progress, shades the OLD value gray
// so it won't be missed by the concurrent marker.
void gc_write_barrier_value(Value old_val);
void gc_write_barrier_env(Env* old_env);

// Convenience macro for the common case
#define GC_WRITE_BARRIER(old_val) \
    do { if (gc.barrier_active) gc_write_barrier_value(old_val); } while(0)

#define GC_WRITE_BARRIER_ENV(old_env) \
    do { if (gc.barrier_active) gc_write_barrier_env(old_env); } while(0)

// ============================================================================
// Mark stack operations
// ============================================================================

void gc_mark_stack_init(GCMarkStack* stack);
void gc_mark_stack_push(GCMarkStack* stack, void* obj);
void* gc_mark_stack_pop(GCMarkStack* stack);
void gc_mark_stack_free(GCMarkStack* stack);

// Mark functions for different object types
void gc_mark_value(Value val);
void gc_mark_env(Env* env);
void gc_mark_function_registry(void);
void gc_mark_call_stack(void);

// Shade a value gray (push children to mark stack for concurrent processing)
void gc_shade_gray(void* object, int type);

// Debug and stats
void gc_print_stats(void);
void gc_enable_debug(void);
void gc_disable_debug(void);
GCStats gc_get_stats(void);
void gc_enable(void);
void gc_disable(void);

// ============================================================================
// ARC Mode (Nim-style Automatic Reference Counting)
// ============================================================================
// When gc.mode == GC_MODE_ARC, objects are freed deterministically when
// their reference count drops to zero. A cycle collector runs periodically
// to handle reference cycles (like Nim's --gc:arc with --cycleCollector:markAndSweep).

// Set GC mode (call before any allocations, typically from --gc:arc flag)
void gc_set_mode(int mode);

// ARC reference counting operations
void arc_register(void* obj);         // Register object in ARC side-table (ref_count=1)
void arc_retain(void* obj);           // Increment ref count
void arc_release(void* obj);          // Decrement ref count, free if zero
void arc_assign(void** slot, void* new_obj);  // Atomic assign: retain new, release old

// ARC-aware value assignment: handles retain/release for heap-allocated values
void arc_assign_value(Value* slot, Value new_val);

// ARC cycle collector (trial deletion / mark-and-sweep hybrid)
void arc_collect_cycles(void);        // Run cycle detection on buffered suspects
void arc_add_candidate(void* obj);    // Add potential cycle root to buffer
void arc_force_cycle_collection(void); // Force immediate cycle collection

// ARC convenience macros
#define ARC_RETAIN(obj) do { if (gc.mode == GC_MODE_ARC && (obj) != NULL) arc_retain(obj); } while(0)
#define ARC_RELEASE(obj) do { if (gc.mode == GC_MODE_ARC && (obj) != NULL) arc_release(obj); } while(0)
#define ARC_ASSIGN(slot, new_obj) \
    do { if (gc.mode == GC_MODE_ARC) arc_assign((void**)(slot), (void*)(new_obj)); \
         else *(slot) = (new_obj); } while(0)

#endif // SAGELANG_GC_H
