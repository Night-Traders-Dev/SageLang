#ifndef SAGE_GC_H
#define SAGE_GC_H

#include "value.h"

typedef struct Obj Obj;

// Object types for GC tracking
typedef enum {
    OBJ_STRING,
    OBJ_ARRAY,
    OBJ_DICT,
    OBJ_TUPLE,
    OBJ_FUNCTION
} ObjType;

// Base object structure (header for all heap-allocated objects)
struct Obj {
    ObjType type;
    int is_marked;      // For mark-and-sweep
    struct Obj* next;   // Linked list of all objects
};

// GC statistics
typedef struct {
    size_t bytes_allocated;
    size_t next_gc;
    size_t num_objects;
    size_t collections;
    size_t objects_freed;
} GCStats;

// GC Configuration
#define GC_HEAP_GROW_FACTOR 2
#define GC_INITIAL_THRESHOLD (1024 * 1024)  // 1 MB

// GC API
void gc_init();
void gc_shutdown();
void* gc_allocate(size_t size, ObjType type);
void gc_register_obj(Obj* obj);
void gc_collect();
void gc_mark_value(Value* value);
void gc_mark_all_roots();
GCStats gc_get_stats();

// Manual collection control
void gc_enable();
void gc_disable();
int gc_is_enabled();

#endif