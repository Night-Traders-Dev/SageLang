// include/gc.h
// Garbage Collector for SageLang
// Mark-and-sweep garbage collection for memory management
// ADAPTED FOR SAGELANG STRUCTURES

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

// Safe allocation macro - aborts with diagnostic on OOM
#define SAGE_ALLOC(size) sage_safe_malloc(size, __FILE__, __LINE__)
#define SAGE_REALLOC(ptr, size) sage_safe_realloc(ptr, size, __FILE__, __LINE__)

static inline void* sage_safe_malloc(size_t size, const char* file, int line) {
    if (size == 0) size = 1;  // Guarantee non-NULL return for zero-size allocs
    void* ptr = malloc(size);
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

// GC object header (prepended to all allocated objects)
typedef struct {
    int marked;           // Has this object been marked in this cycle?
    int type;             // Object type (VAL_STRING, VAL_ARRAY, etc.)
    size_t size;          // Bytes owned directly by this object payload
    void* next;           // Next object in linked list
} GCHeader;

// GC Statistics struct (for gc_stats native function)
typedef struct {
    unsigned long bytes_allocated;  // Total bytes allocated
    unsigned long current_bytes;    // Managed bytes currently live
    int num_objects;                // Current number of objects
    int collections;                // Number of GC collections run
    int objects_freed;              // Objects freed in last collection
    int next_gc;                    // Objects until next GC
    unsigned long next_gc_bytes;    // Managed-byte threshold for next GC
} GCStats;

// Garbage collector state
typedef struct {
    void* objects;              // Linked list of all objects
    int object_count;           // Number of objects allocated
    int objects_since_gc;       // Objects allocated since last GC
    int collections;            // Number of GC collections run
    int marked_count;           // Objects marked this cycle
    int freed_count;            // Objects freed this cycle
    unsigned long bytes_allocated;  // Total bytes allocated
    unsigned long bytes_freed;      // Total bytes freed
    unsigned long next_gc_bytes;    // Managed-byte threshold for next GC
    int next_gc_objects;            // Live-object threshold for next GC
    int enabled;                // Is GC enabled?
    int pin_count;              // When > 0, auto-collection is suppressed
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
void gc_collect_with_root(Env* root_env);  // Use this one!
void gc_mark(void);
void gc_mark_from_root(Env* root_env);     // Use this one!
void gc_sweep(void);

// GC pinning - suppress collection during multi-step allocations
void gc_pin(void);    // Increment pin count (suppresses auto-collection)
void gc_unpin(void);  // Decrement pin count (re-enables auto-collection)

// Memory allocation
void* gc_alloc(int type, size_t size);
void gc_free(void* obj);

// Track auxiliary heap buffers owned by GC-managed objects.
void gc_track_external_allocation(size_t size);
void gc_track_external_resize(size_t old_size, size_t new_size);
void gc_track_external_free(size_t size);

// Mark functions for different object types
void gc_mark_value(Value val);
void gc_mark_env(Env* env);
void gc_mark_function_registry(void);
void gc_mark_call_stack(void);

// Debug and stats utilities
void gc_print_stats(void);
void gc_enable_debug(void);
void gc_disable_debug(void);
GCStats gc_get_stats(void);
void gc_enable(void);
void gc_disable(void);

#endif // SAGELANG_GC_H
