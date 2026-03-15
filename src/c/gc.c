// src/gc.c - CORRECTED VERSION
// Garbage Collector Implementation for SageLang
// Mark-and-sweep collection with environment and function registry marking
// ADAPTED FOR SAGELANG ACTUAL STRUCTURES - WITH NATIVE FUNCTION SUPPORT

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sage_thread.h"
#include "gc.h"
#include "value.h"
#include "env.h"
#include "module.h"
#include "vm.h"

extern Environment* g_global_env;
extern Environment* g_gc_root_env;

// Thread safety: global GC mutex
static sage_mutex_t gc_mutex = SAGE_MUTEX_INITIALIZER;

void gc_lock(void) {
    sage_mutex_lock(&gc_mutex);
}

void gc_unlock(void) {
    sage_mutex_unlock(&gc_mutex);
}

// Environment marking now uses Env.marked flag directly (O(1) per env)

static Env* gc_root_env(void) {
    if (g_gc_root_env != NULL) {
        return g_gc_root_env;
    }
    return g_global_env;
}

// No longer needed — env marks are cleared during env_sweep_unmarked()

static unsigned long gc_live_bytes(void) {
    return gc.bytes_allocated - gc.bytes_freed;
}

static unsigned long gc_min_bytes_padding(void) {
    return GC_MIN_TRIGGER_BYTES / 2;
}

static int gc_min_object_padding(void) {
    return GC_MIN_TRIGGER_OBJECTS / 2;
}

static void gc_recompute_thresholds(unsigned long reclaimed_bytes,
                                    int reclaimed_objects) {
    unsigned long live_bytes = gc_live_bytes();
    int live_objects = gc.object_count;

    unsigned long byte_padding = live_bytes / 2;
    int object_padding = live_objects / 2;

    if (byte_padding < gc_min_bytes_padding()) {
        byte_padding = gc_min_bytes_padding();
    }
    if (object_padding < gc_min_object_padding()) {
        object_padding = gc_min_object_padding();
    }

    if (gc.collections == 0) {
        byte_padding = GC_MIN_TRIGGER_BYTES;
        object_padding = GC_MIN_TRIGGER_OBJECTS;
    } else if (reclaimed_bytes <= live_bytes / 8) {
        byte_padding /= 2;
        if (byte_padding < gc_min_bytes_padding()) {
            byte_padding = gc_min_bytes_padding();
        }
    } else if (reclaimed_bytes >= live_bytes) {
        byte_padding *= 2;
    }

    if (gc.collections == 0) {
        object_padding = GC_MIN_TRIGGER_OBJECTS;
    } else if (reclaimed_objects <= live_objects / 8) {
        object_padding /= 2;
        if (object_padding < gc_min_object_padding()) {
            object_padding = gc_min_object_padding();
        }
    } else if (reclaimed_objects >= live_objects) {
        object_padding *= 2;
    }

    gc.next_gc_bytes = live_bytes + byte_padding;
    if (gc.next_gc_bytes < GC_MIN_TRIGGER_BYTES) {
        gc.next_gc_bytes = GC_MIN_TRIGGER_BYTES;
    }

    gc.next_gc_objects = live_objects + object_padding;
    if (gc.next_gc_objects < GC_MIN_TRIGGER_OBJECTS) {
        gc.next_gc_objects = GC_MIN_TRIGGER_OBJECTS;
    }
}

static int gc_should_collect(size_t incoming_size) {
    if (!gc.enabled || gc.pin_count > 0) {
        return 0;
    }

    if ((gc.object_count + 1) >= gc.next_gc_objects) {
        return 1;
    }

    return gc_live_bytes() + (unsigned long)sizeof(GCHeader) + (unsigned long)incoming_size
        >= gc.next_gc_bytes;
}

static int gc_try_mark_object(void* object) {
    if (object == NULL) {
        return 0;
    }

    GCHeader* header = (GCHeader*)object - 1;
    if (header->marked) {
        return 0;
    }

    header->marked = 1;
    gc.marked_count++;
    return 1;
}

static int gc_try_mark_env(Env* env) {
    if (env->marked) {
        return 0;  // Already marked this cycle
    }
    env->marked = 1;
    return 1;
}

static size_t gc_release_object(GCHeader* header) {
    void* object = header + 1;
    size_t freed = sizeof(GCHeader) + header->size;

    switch (header->type) {
        case VAL_ARRAY: {
            ArrayValue* array = object;
            freed += sizeof(Value) * (size_t)array->capacity;
            free(array->elements);
            break;
        }
        case VAL_DICT: {
            DictValue* dict = object;
            freed += sizeof(DictEntry) * (size_t)dict->capacity;
            for (int i = 0; i < dict->capacity; i++) {
                if (dict->entries[i].key != NULL) {
                    freed += strlen(dict->entries[i].key) + 1;
                    freed += sizeof(Value);
                    free(dict->entries[i].key);
                    free(dict->entries[i].value);
                }
            }
            free(dict->entries);
            break;
        }
        case VAL_TUPLE: {
            TupleValue* tuple = object;
            freed += sizeof(Value) * (size_t)tuple->count;
            free(tuple->elements);
            break;
        }
        case VAL_CLASS: {
            ClassValue* class_val = object;
            freed += strlen(class_val->name) + 1;
            freed += sizeof(Method) * (size_t)class_val->method_count;
            for (int i = 0; i < class_val->method_count; i++) {
                freed += strlen(class_val->methods[i].name) + 1;
                free(class_val->methods[i].name);
            }
            free(class_val->methods);
            free(class_val->name);
            break;
        }
        case VAL_EXCEPTION: {
            ExceptionValue* exception = object;
            freed += strlen(exception->message) + 1;
            free(exception->message);
            break;
        }
        default:
            break;
    }

    return freed;
}

// Global GC state
GC gc = {0};

// Debug flag
static int gc_debug = 0;

// ============================================================================
// GC Initialization and Shutdown
// ============================================================================

void gc_init(void) {
    gc.objects = NULL;
    gc.object_count = 0;
    gc.objects_since_gc = 0;
    gc.collections = 0;
    gc.marked_count = 0;
    gc.freed_count = 0;
    gc.bytes_allocated = 0;
    gc.bytes_freed = 0;
    gc.next_gc_bytes = GC_MIN_TRIGGER_BYTES;
    gc.next_gc_objects = GC_MIN_TRIGGER_OBJECTS;
    gc.enabled = 1;  // GC starts enabled
    gc.pin_count = 0;

    if (gc_debug) {
        fprintf(stderr, "[GC] Garbage collector initialized\n");
    }
}

void gc_shutdown(void) {
    // Final collection
    if (gc.enabled) {
        gc_collect();
    }
    
    // Free any remaining objects
    void* obj = gc.objects;
    while (obj != NULL) {
        GCHeader* header = obj;
        void* next = header->next;
        gc.bytes_freed += gc_release_object(header);
        free(obj);
        obj = next;
    }
    
    if (gc_debug) {
        fprintf(stderr, "[GC] Garbage collector shutdown\n");
        gc_print_stats();
    }
}

// ============================================================================
// Memory Allocation with GC Support
// ============================================================================

void gc_pin(void) {
    gc.pin_count++;
}

void gc_unpin(void) {
    if (gc.pin_count > 0) gc.pin_count--;
}

void* gc_alloc(int type, size_t size) {
    // Check if GC should run (suppressed when pinned)
    if (gc_should_collect(size)) {
        Env* root = gc_root_env();
        if (root != NULL) {
            gc_collect_with_root(root);
        }
    }
    
    // Allocate memory with GC header
    size_t total_size = sizeof(GCHeader) + size;
    GCHeader* header = (GCHeader*)malloc(total_size);
    
    if (header == NULL) {
        fprintf(stderr, "Fatal: GC allocation failed (%zu bytes)\n", total_size);
        abort();
    }
    
    // Initialize header
    header->marked = 0;
    header->type = type;
    header->size = size;
    
    // Add to object list
    header->next = gc.objects;
    gc.objects = header;
    
    // Update stats
    gc.object_count++;
    gc.objects_since_gc++;
    gc.bytes_allocated += total_size;
    
    if (gc_debug) {
        fprintf(stderr, "[GC] Allocated %zu bytes (type=%d, total objects=%d)\n",
                total_size, type, gc.object_count);
    }
    
    // Return pointer after header
    return (void*)(header + 1);
}

void gc_free(void* obj) {
    if (obj == NULL) return;
    
    GCHeader* header = (GCHeader*)obj - 1;
    gc.bytes_freed += gc_release_object(header);
    gc.freed_count++;
    
    if (gc_debug) {
        fprintf(stderr, "[GC] Freed %zu bytes\n", sizeof(GCHeader) + header->size);
    }
    
    free(header);
}

void gc_track_external_allocation(size_t size) {
    gc.bytes_allocated += (unsigned long)size;
}

void gc_track_external_resize(size_t old_size, size_t new_size) {
    if (new_size >= old_size) {
        gc.bytes_allocated += (unsigned long)(new_size - old_size);
    } else {
        gc.bytes_freed += (unsigned long)(old_size - new_size);
    }
}

void gc_track_external_free(size_t size) {
    gc.bytes_freed += (unsigned long)size;
}

// ============================================================================
// GC Marking Phase - THE FIX FOR ALL THREE TODOS
// ============================================================================

static void gc_mark_bytecode_chunk(BytecodeChunk* chunk) {
    if (chunk == NULL) {
        return;
    }

    for (int i = 0; i < chunk->constant_count; i++) {
        gc_mark_value(chunk->constants[i]);
    }
}

void gc_mark_value(Value val) {
    // Primitive types - no marking needed
    if (val.type == VAL_NIL || val.type == VAL_NUMBER || 
        val.type == VAL_BOOL) {
        return;
    }
    
    if (val.type == VAL_STRING) {
        if (gc_try_mark_object(val.as.string)) {
        }
        return;
    }
    
    if (val.type == VAL_ARRAY) {
        if (gc_try_mark_object(val.as.array)) {
            // Mark all elements in array
            ArrayValue* arr = val.as.array;
            for (int i = 0; i < arr->count; i++) {
                gc_mark_value(arr->elements[i]);
            }
        }
        return;
    }
    
    if (val.type == VAL_DICT) {
        if (gc_try_mark_object(val.as.dict)) {
            // Mark all values in dict (hash table: iterate by capacity, skip empty slots)
            DictValue* dict = val.as.dict;
            for (int i = 0; i < dict->capacity; i++) {
                if (dict->entries[i].key != NULL && dict->entries[i].value != NULL) {
                    gc_mark_value(*dict->entries[i].value);
                }
            }
        }
        return;
    }
    
    if (val.type == VAL_TUPLE) {
        if (gc_try_mark_object(val.as.tuple)) {
            // Mark all elements in tuple
            TupleValue* tuple = val.as.tuple;
            for (int i = 0; i < tuple->count; i++) {
                gc_mark_value(tuple->elements[i]);
            }
        }
        return;
    }
    
    if (val.type == VAL_FUNCTION) {
        if (gc_try_mark_object(val.as.function)) {
            if (val.as.function->closure != NULL) {
                gc_mark_env(val.as.function->closure);
            }
            if (val.as.function->is_vm && val.as.function->vm_function != NULL) {
                gc_mark_bytecode_chunk(&val.as.function->vm_function->chunk);
            }
        }
        return;
    }
    
    if (val.type == VAL_NATIVE) {
        // Native functions are static, don't mark
        return;
    }
    
    if (val.type == VAL_GENERATOR) {
        if (gc_try_mark_object(val.as.generator)) {
            // Mark generator's environments
            GeneratorValue* gen = val.as.generator;
            if (gen->closure != NULL) {
                gc_mark_env(gen->closure);
            }
            if (gen->gen_env != NULL) {
                gc_mark_env(gen->gen_env);
            }
        }
        return;
    }
    
    if (val.type == VAL_CLASS) {
        if (gc_try_mark_object(val.as.class_val)) {
            if (val.as.class_val->parent != NULL) {
                gc_mark_value((Value){.type = VAL_CLASS, .as.class_val = val.as.class_val->parent});
            }
        }
        return;
    }
    
    if (val.type == VAL_INSTANCE) {
        if (gc_try_mark_object(val.as.instance)) {
            // Mark instance's fields
            InstanceValue* inst = val.as.instance;
            if (inst->class_def != NULL) {
                gc_mark_value((Value){.type = VAL_CLASS, .as.class_val = inst->class_def});
            }
            if (inst->fields != NULL) {
                // Mark the fields dict
                gc_mark_value((Value){.type = VAL_DICT, .as.dict = inst->fields});
            }
        }
        return;
    }
    
    if (val.type == VAL_EXCEPTION) {
        if (gc_try_mark_object(val.as.exception)) {
        }
        return;
    }

    if (val.type == VAL_MODULE) {
        if (gc_try_mark_object(val.as.module)) {
            if (val.as.module->module != NULL && val.as.module->module->env != NULL) {
                gc_mark_env(val.as.module->module->env);
            }
        }
        return;
    }
}

// FIX #1: Mark all environments in a scope chain
// This was TODO: Mark environment variables
void gc_mark_env(Env* env) {
    while (env != NULL) {
        if (!gc_try_mark_env(env)) {
            return;
        }

        if (gc_debug) {
            fprintf(stderr, "[GC] Marking environment %p\n", (void*)env);
        }
        
        // Mark all variables in this environment's linked list
        EnvNode* node = env->head;
        while (node != NULL) {
            gc_mark_value(node->value);
            node = node->next;
        }
        
        // Continue up the scope chain to parent environment
        env = env->parent;
    }
}

// FIX #2: Mark all functions in the function registry
// This was TODO: Mark function registry
void gc_mark_function_registry(void) {
    if (gc_debug) {
        fprintf(stderr, "[GC] Marking function registry\n");
    }
    
    // In SageLang, functions are stored in the global environment
    // They're marked via gc_mark_env, so this is mainly for documentation
    // If you add a separate function registry later, mark it here
}

// FIX #3: Mark all call stack frames and their local variables
// This was TODO: Mark call stack
void gc_mark_call_stack(void) {
    if (gc_debug) {
        fprintf(stderr, "[GC] Marking call stack\n");
    }
    
    // In SageLang, call stack is managed through environments
    // Each function call creates a new environment
    // The root/global environment is always reachable, so all scopes are marked
    // This is handled by gc_mark_env on the global environment
}

// Master marking function - marks all reachable objects
void gc_mark(void) {
    gc.marked_count = 0;

    if (gc_debug) {
        fprintf(stderr, "[GC] Starting mark phase\n");
    }

    gc_mark_from_root(gc_root_env());
}

// Wrapper to mark from root environment (call this from your interpreter)
void gc_mark_from_root(Env* root_env) {
    gc.marked_count = 0;

    if (gc_debug) {
        fprintf(stderr, "[GC] Starting mark phase from root\n");
    }

    // Mark all globals
    if (root_env != NULL) {
        gc_mark_env(root_env);
    }

    // Mark function registry
    gc_mark_function_registry();

    // Mark call stack (via environment traversal)
    gc_mark_call_stack();

    // Mark active bytecode VM state when bytecode runtime is executing.
    vm_mark_roots();

    if (gc_debug) {
        fprintf(stderr, "[GC] Mark phase complete: %d objects marked\n",
                gc.marked_count);
    }
}

// ============================================================================
// GC Sweeping Phase
// ============================================================================

void gc_sweep(void) {
    gc.freed_count = 0;

    if (gc_debug) {
        fprintf(stderr, "[GC] Starting sweep phase\n");
    }

    // Sweep GC-managed objects (values)
    void** current = (void**)&gc.objects;

    while (*current != NULL) {
        GCHeader* header = (GCHeader*)*current;

        if (!header->marked) {
            // Object is unreachable - free it
            void* unreached = *current;
            *current = header->next;

            gc.object_count--;
            gc.freed_count++;

            if (gc_debug) {
                fprintf(stderr, "[GC] Freeing unmarked object (type=%d)\n",
                        header->type);
            }

            gc.bytes_freed += gc_release_object(header);
            free(unreached);
        } else {
            // Object is reachable - unmark for next cycle
            header->marked = 0;
            current = (void**)&header->next;
        }
    }

    // Sweep unreachable environments (marks cleared inside)
    env_sweep_unmarked();

    if (gc_debug) {
        fprintf(stderr, "[GC] Sweep phase complete: %d objects freed\n",
                gc.freed_count);
    }
}

// ============================================================================
// Main GC Collection Routine
// ============================================================================

void gc_collect(void) {
    if (!gc.enabled) return;  // Skip if GC is disabled
    
    if (gc_debug) {
        fprintf(stderr, "\n[GC] ========== GC Collection #%d ==========\n", 
                gc.collections + 1);
    }
    
    unsigned long before_bytes = gc_live_bytes();
    int before_objects = gc.object_count;

    // Mark phase: find all reachable objects
    gc_mark();
    
    // Sweep phase: free unmarked objects
    gc_sweep();
    
    // Reset counter
    gc.objects_since_gc = 0;
    gc.collections++;
    gc_recompute_thresholds(before_bytes - gc_live_bytes(),
                            before_objects - gc.object_count);
    
    if (gc_debug) {
        fprintf(stderr, "[GC] Collection complete: %d objects remaining\n\n", 
                gc.object_count);
    }
}

// Wrapper to collect with root environment
void gc_collect_with_root(Env* root_env) {
    if (!gc.enabled) return;  // Skip if GC is disabled
    
    if (gc_debug) {
        fprintf(stderr, "\n[GC] ========== GC Collection #%d ==========\n", 
                gc.collections + 1);
    }
    
    unsigned long before_bytes = gc_live_bytes();
    int before_objects = gc.object_count;

    // Mark phase with root environment
    gc_mark_from_root(root_env);
    
    // Sweep phase: free unmarked objects
    gc_sweep();
    
    // Reset counter
    gc.objects_since_gc = 0;
    gc.collections++;
    gc_recompute_thresholds(before_bytes - gc_live_bytes(),
                            before_objects - gc.object_count);
    
    if (gc_debug) {
        fprintf(stderr, "[GC] Collection complete: %d objects remaining\n\n", 
                gc.object_count);
    }
}

// ============================================================================
// Debug and Stats Utilities
// ============================================================================

void gc_print_stats(void) {
    printf("=== Garbage Collector Statistics ===\n");
    printf("Collections run:        %d\n", gc.collections);
    printf("Objects allocated:      %d\n", gc.object_count);
    printf("Objects since GC:       %d\n", gc.objects_since_gc);
    printf("Total bytes allocated:  %lu\n", gc.bytes_allocated);
    printf("Total bytes freed:      %lu\n", gc.bytes_freed);
    printf("Current memory usage:   %lu bytes\n", 
           gc_live_bytes());
    printf("Marked in last cycle:   %d\n", gc.marked_count);
    printf("Freed in last cycle:    %d\n", gc.freed_count);
    printf("Next GC object target:  %d\n", gc.next_gc_objects);
    printf("Next GC byte target:    %lu\n", gc.next_gc_bytes);
    printf("GC enabled:             %s\n", gc.enabled ? "yes" : "no");
    printf("=====================================\n");
}

void gc_enable_debug(void) {
    gc_debug = 1;
    fprintf(stderr, "[GC] Debug mode enabled\n");
}

void gc_disable_debug(void) {
    gc_debug = 0;
    fprintf(stderr, "[GC] Debug mode disabled\n");
}

// Get statistics for native gc_stats() function
GCStats gc_get_stats(void) {
    GCStats stats;
    stats.bytes_allocated = gc.bytes_allocated;
    stats.current_bytes = gc_live_bytes();
    stats.num_objects = gc.object_count;
    stats.collections = gc.collections;
    stats.objects_freed = gc.freed_count;
    stats.next_gc = gc.next_gc_objects - gc.object_count;
    if (stats.next_gc < 0) stats.next_gc = 0;
    stats.next_gc_bytes = gc.next_gc_bytes;
    return stats;
}

// Enable GC from native function
void gc_enable(void) {
    gc.enabled = 1;
    if (gc_debug) {
        fprintf(stderr, "[GC] GC enabled\n");
    }
}

// Disable GC from native function
void gc_disable(void) {
    gc.enabled = 0;
    if (gc_debug) {
        fprintf(stderr, "[GC] GC disabled\n");
    }
}
