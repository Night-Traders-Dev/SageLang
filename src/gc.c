#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gc.h"
#include "value.h"

// Global GC state
static struct {
    Obj* objects;           // Linked list of all allocated objects
    GCStats stats;
    int enabled;
} gc_state;

// Root set (temporary - will be replaced with proper root tracking)
static Value* gc_roots[1024];
static int gc_root_count = 0;

void gc_init() {
    gc_state.objects = NULL;
    gc_state.stats.bytes_allocated = 0;
    gc_state.stats.next_gc = GC_INITIAL_THRESHOLD;
    gc_state.stats.num_objects = 0;
    gc_state.stats.collections = 0;
    gc_state.stats.objects_freed = 0;
    gc_state.enabled = 1;
    gc_root_count = 0;
}

void gc_shutdown() {
    // Free all remaining objects
    Obj* obj = gc_state.objects;
    while (obj != NULL) {
        Obj* next = obj->next;
        free(obj);
        obj = next;
    }
    gc_state.objects = NULL;
}

void* gc_allocate(size_t size, ObjType type) {
    // Track allocation
    gc_state.stats.bytes_allocated += size;
    
    // Trigger GC if threshold exceeded and GC is enabled
    if (gc_state.enabled && gc_state.stats.bytes_allocated > gc_state.stats.next_gc) {
        gc_collect();
    }
    
    // Allocate memory
    Obj* obj = (Obj*)malloc(size);
    if (obj == NULL) {
        fprintf(stderr, "Out of memory!\n");
        exit(1);
    }
    
    // Initialize object header
    obj->type = type;
    obj->is_marked = 0;
    obj->next = gc_state.objects;
    gc_state.objects = obj;
    gc_state.stats.num_objects++;
    
    return obj;
}

void gc_register_obj(Obj* obj) {
    obj->next = gc_state.objects;
    gc_state.objects = obj;
    gc_state.stats.num_objects++;
}

// Mark phase - recursively mark all reachable objects
void gc_mark_value(Value* value) {
    if (value == NULL) return;
    
    switch (value->type) {
        case VAL_STRING: {
            // Strings are currently not tracked as Obj*
            // Will be updated when we refactor string allocation
            break;
        }
        
        case VAL_ARRAY: {
            if (value->as.array == NULL) break;
            
            // Mark array object
            Obj* obj = (Obj*)value->as.array;
            if (obj->is_marked) return;  // Already marked
            obj->is_marked = 1;
            
            // Mark array elements
            ArrayValue* arr = value->as.array;
            for (int i = 0; i < arr->count; i++) {
                gc_mark_value(&arr->elements[i]);
            }
            break;
        }
        
        case VAL_DICT: {
            if (value->as.dict == NULL) break;
            
            // Mark dict object
            Obj* obj = (Obj*)value->as.dict;
            if (obj->is_marked) return;
            obj->is_marked = 1;
            
            // Mark dict values
            DictValue* dict = value->as.dict;
            for (int i = 0; i < dict->count; i++) {
                gc_mark_value(dict->entries[i].value);
            }
            break;
        }
        
        case VAL_TUPLE: {
            if (value->as.tuple == NULL) break;
            
            // Mark tuple object
            Obj* obj = (Obj*)value->as.tuple;
            if (obj->is_marked) return;
            obj->is_marked = 1;
            
            // Mark tuple elements
            TupleValue* tuple = value->as.tuple;
            for (int i = 0; i < tuple->count; i++) {
                gc_mark_value(&tuple->elements[i]);
            }
            break;
        }
        
        default:
            // Primitives (numbers, bools, nil) don't need marking
            break;
    }
}

void gc_mark_all_roots() {
    // Mark all roots
    for (int i = 0; i < gc_root_count; i++) {
        gc_mark_value(gc_roots[i]);
    }
    
    // TODO: Mark environment variables
    // TODO: Mark function registry
    // TODO: Mark call stack
}

// Sweep phase - free unmarked objects
static void gc_sweep() {
    Obj** obj_ptr = &gc_state.objects;
    
    while (*obj_ptr != NULL) {
        Obj* obj = *obj_ptr;
        
        if (!obj->is_marked) {
            // Unlink and free
            *obj_ptr = obj->next;
            
            // Free object-specific data
            switch (obj->type) {
                case OBJ_ARRAY: {
                    ArrayValue* arr = (ArrayValue*)obj;
                    if (arr->elements != NULL) {
                        free(arr->elements);
                    }
                    break;
                }
                
                case OBJ_DICT: {
                    DictValue* dict = (DictValue*)obj;
                    for (int i = 0; i < dict->count; i++) {
                        free(dict->entries[i].key);
                        free(dict->entries[i].value);
                    }
                    if (dict->entries != NULL) {
                        free(dict->entries);
                    }
                    break;
                }
                
                case OBJ_TUPLE: {
                    TupleValue* tuple = (TupleValue*)obj;
                    if (tuple->elements != NULL) {
                        free(tuple->elements);
                    }
                    break;
                }
                
                default:
                    break;
            }
            
            size_t obj_size = sizeof(Obj);  // Approximate
            gc_state.stats.bytes_allocated -= obj_size;
            gc_state.stats.num_objects--;
            gc_state.stats.objects_freed++;
            
            free(obj);
        } else {
            // Unmark for next collection
            obj->is_marked = 0;
            obj_ptr = &obj->next;
        }
    }
}

void gc_collect() {
    if (!gc_state.enabled) return;
    
#ifdef GC_DEBUG
    size_t before = gc_state.stats.num_objects;
#endif
    
    // Mark phase
    gc_mark_all_roots();
    
    // Sweep phase
    gc_sweep();
    
    // Update threshold
    gc_state.stats.next_gc = gc_state.stats.bytes_allocated * GC_HEAP_GROW_FACTOR;
    if (gc_state.stats.next_gc < GC_INITIAL_THRESHOLD) {
        gc_state.stats.next_gc = GC_INITIAL_THRESHOLD;
    }
    
    gc_state.stats.collections++;
    
#ifdef GC_DEBUG
    size_t after = gc_state.stats.num_objects;
    size_t freed = before - after;
    printf("[GC] Collected %zu objects (%zu -> %zu)\n", freed, before, after);
    printf("[GC] Next collection at %zu bytes\n", gc_state.stats.next_gc);
#endif
}

GCStats gc_get_stats() {
    return gc_state.stats;
}

void gc_enable() {
    gc_state.enabled = 1;
}

void gc_disable() {
    gc_state.enabled = 0;
}

int gc_is_enabled() {
    return gc_state.enabled;
}

// Root management (simplified for now)
void gc_add_root(Value* value) {
    if (gc_root_count < 1024) {
        gc_roots[gc_root_count++] = value;
    }
}

void gc_remove_root(Value* value) {
    for (int i = 0; i < gc_root_count; i++) {
        if (gc_roots[i] == value) {
            gc_roots[i] = gc_roots[--gc_root_count];
            return;
        }
    }
}