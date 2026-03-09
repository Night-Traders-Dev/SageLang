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
#define GC_HEAP_SIZE (1024 * 1024)  // 1MB heap
#define GC_THRESHOLD 1000            // Run GC after allocating 1000 objects

// Safe allocation macro - aborts with diagnostic on OOM
#define SAGE_ALLOC(size) sage_safe_malloc(size, __FILE__, __LINE__)
#define SAGE_REALLOC(ptr, size) sage_safe_realloc(ptr, size, __FILE__, __LINE__)

static inline void* sage_safe_malloc(size_t size, const char* file, int line) {
    void* ptr = malloc(size);
    if (ptr == NULL && size > 0) {
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
    void* next;           // Next object in linked list
} GCHeader;

// GC Statistics struct (for gc_stats native function)
typedef struct {
    unsigned long bytes_allocated;  // Total bytes allocated
    int num_objects;                // Current number of objects
    int collections;                // Number of GC collections run
    int objects_freed;              // Objects freed in last collection
    int next_gc;                    // Objects until next GC
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
    int enabled;                // Is GC enabled?
    int pin_count;              // When > 0, auto-collection is suppressed
} GC;

// Global GC instance
extern GC gc;

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
