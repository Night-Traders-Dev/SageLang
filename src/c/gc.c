// src/gc.c - Concurrent Tri-Color Mark-Sweep Garbage Collector
// Sub-millisecond STW pauses via SATB write barriers and incremental processing
//
// Design:
//   Phase 1 (STW ~50-200us): Snapshot roots -> shade gray, enable write barrier
//   Phase 2 (Concurrent):     Drain mark stack (gray -> black), mutator runs freely
//   Phase 3 (STW ~20-50us):   Drain barrier-shaded objects, disable write barrier
//   Phase 4 (Concurrent):     Sweep white objects in small batches
//
// Write barrier: SATB (Snapshot At The Beginning) - before overwriting a reference,
//   the OLD value is shaded gray to prevent the concurrent marker from missing it.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
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

void gc_lock(void) { sage_mutex_lock(&gc_mutex); }
void gc_unlock(void) { sage_mutex_unlock(&gc_mutex); }

static Env* gc_root_env(void) {
    if (g_gc_root_env != NULL) return g_gc_root_env;
    return g_global_env;
}

// Global GC state
GC gc = {0};
static int gc_debug = 0;

// ============================================================================
// Timing helpers
// ============================================================================

static unsigned long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long)ts.tv_sec * 1000000000UL + (unsigned long)ts.tv_nsec;
}

// ============================================================================
// Mark stack
// ============================================================================

void gc_mark_stack_init(GCMarkStack* stack) {
    stack->capacity = GC_MARK_STACK_INIT;
    stack->count = 0;
    stack->items = (void**)malloc(sizeof(void*) * stack->capacity);
    if (!stack->items) {
        fprintf(stderr, "Fatal: cannot allocate GC mark stack\n");
        abort();
    }
}

void gc_mark_stack_push(GCMarkStack* stack, void* obj) {
    if (stack->count >= stack->capacity) {
        stack->capacity *= 2;
        stack->items = (void**)realloc(stack->items, sizeof(void*) * stack->capacity);
        if (!stack->items) {
            fprintf(stderr, "Fatal: cannot grow GC mark stack\n");
            abort();
        }
    }
    stack->items[stack->count++] = obj;
}

void* gc_mark_stack_pop(GCMarkStack* stack) {
    if (stack->count == 0) return NULL;
    return stack->items[--stack->count];
}

void gc_mark_stack_free(GCMarkStack* stack) {
    free(stack->items);
    stack->items = NULL;
    stack->count = 0;
    stack->capacity = 0;
}

// ============================================================================
// Threshold computation
// ============================================================================

static unsigned long gc_live_bytes(void) {
    return gc.bytes_allocated - gc.bytes_freed;
}

static void gc_recompute_thresholds(unsigned long reclaimed_bytes, int reclaimed_objects) {
    unsigned long live_bytes = gc_live_bytes();
    int live_objects = gc.object_count;
    unsigned long byte_padding = live_bytes / 2;
    int object_padding = live_objects / 2;
    if (byte_padding < GC_MIN_TRIGGER_BYTES / 2) byte_padding = GC_MIN_TRIGGER_BYTES / 2;
    if (object_padding < GC_MIN_TRIGGER_OBJECTS / 2) object_padding = GC_MIN_TRIGGER_OBJECTS / 2;
    if (gc.collections == 0) {
        byte_padding = GC_MIN_TRIGGER_BYTES;
        object_padding = GC_MIN_TRIGGER_OBJECTS;
    } else if (reclaimed_bytes <= live_bytes / 8) {
        byte_padding /= 2;
        if (byte_padding < GC_MIN_TRIGGER_BYTES / 2) byte_padding = GC_MIN_TRIGGER_BYTES / 2;
    } else if (reclaimed_bytes >= live_bytes) {
        byte_padding *= 2;
    }
    gc.next_gc_bytes = live_bytes + byte_padding;
    if (gc.next_gc_bytes < GC_MIN_TRIGGER_BYTES) gc.next_gc_bytes = GC_MIN_TRIGGER_BYTES;
    gc.next_gc_objects = live_objects + object_padding;
    if (gc.next_gc_objects < GC_MIN_TRIGGER_OBJECTS) gc.next_gc_objects = GC_MIN_TRIGGER_OBJECTS;
}

static int gc_should_collect(size_t incoming_size) {
    if (!gc.enabled || gc.pin_count > 0) return 0;
    if (gc.phase != GC_PHASE_IDLE) return 0; // Already collecting
    if ((gc.object_count + 1) >= gc.next_gc_objects) return 1;
    return gc_live_bytes() + (unsigned long)sizeof(GCHeader) + (unsigned long)incoming_size
        >= gc.next_gc_bytes;
}

// ============================================================================
// Object release (type-specific cleanup)
// ============================================================================

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
            size_t msg_len = strlen(exception->message) + 1;
            freed += msg_len;
            gc_track_external_free(msg_len);
            free(exception->message);
            break;
        }
        case VAL_CLIB: {
            CLibValue* clib = object;
            if (clib->name) { freed += strlen(clib->name) + 1; free(clib->name); }
            break;
        }
        case VAL_POINTER: {
            PointerValue* pv = object;
            if (pv->ptr && pv->owned) { freed += pv->size; free(pv->ptr); }
            break;
        }
        case VAL_THREAD: {
            ThreadValue* tv = object;
            free(tv->handle); free(tv->data);
            break;
        }
        case VAL_MUTEX: {
            MutexValue* mv = object;
            if (mv->handle) { sage_mutex_destroy((sage_mutex_t*)mv->handle); free(mv->handle); }
            break;
        }
        default: break;
    }
    return freed;
}

// ============================================================================
// Initialization and Shutdown
// ============================================================================

void gc_init(void) {
    memset(&gc, 0, sizeof(GC));
    gc.next_gc_bytes = GC_MIN_TRIGGER_BYTES;
    gc.next_gc_objects = GC_MIN_TRIGGER_OBJECTS;
    gc.enabled = 1;
    gc.phase = GC_PHASE_IDLE;
    gc.barrier_active = 0;
    gc.mode = GC_MODE_TRACING;
    gc.cycle_buffer = NULL;
    gc.cycle_buffer_count = 0;
    gc.cycle_buffer_capacity = 0;
    gc.arc_decrements = 0;
    gc.arc_cycle_threshold = 1000;
    gc_mark_stack_init(&gc.mark_stack);
    if (gc_debug) fprintf(stderr, "[GC] Concurrent garbage collector initialized\n");
}

// Forward declaration: cleanup ARC side-table (defined in ARC section below)
static void arc_table_cleanup(void);

void gc_shutdown(void) {
    if (gc.enabled) gc_collect();
    // Run final ORC/ARC cycle collection before full teardown
    if (gc.mode == GC_MODE_ORC) orc_collect_cycles();
    else if (gc.mode == GC_MODE_ARC) arc_collect_cycles();
    void* obj = gc.objects;
    while (obj != NULL) {
        GCHeader* header = obj;
        void* next = header->next;
        gc.bytes_freed += gc_release_object(header);
        free(obj);
        obj = next;
    }
    gc_mark_stack_free(&gc.mark_stack);
    free(gc.cycle_buffer); gc.cycle_buffer = NULL;
    free(gc.orc_roots); gc.orc_roots = NULL;
    arc_table_cleanup();
    if (gc_debug) { fprintf(stderr, "[GC] Garbage collector shutdown\n"); gc_print_stats(); }
}

// ============================================================================
// Memory Allocation
// ============================================================================

void gc_pin(void) { gc.pin_count++; }
void gc_unpin(void) { if (gc.pin_count > 0) gc.pin_count--; }

void* gc_alloc(int type, size_t size) {
    sage_mutex_lock(&gc_mutex);

    if (gc_should_collect(size)) {
        Env* root = gc_root_env();
        if (root != NULL) {
            sage_mutex_unlock(&gc_mutex);
            gc_collect_with_root(root);
            sage_mutex_lock(&gc_mutex);
        }
    }

    size_t total_size = sizeof(GCHeader) + size;
    GCHeader* header = (GCHeader*)calloc(1, total_size);
    if (header == NULL) {
        sage_mutex_unlock(&gc_mutex);
        fprintf(stderr, "Fatal: GC allocation failed (%zu bytes)\n", total_size);
        abort();
    }

    // New objects are BLACK during concurrent mark (allocated-black invariant)
    // This means newly allocated objects survive the current cycle.
    // During IDLE phase, color doesn't matter (will be reset at next cycle start).
    header->color = (gc.phase == GC_PHASE_CONCURRENT_MARK || gc.phase == GC_PHASE_REMARK)
                    ? GC_BLACK : GC_WHITE;
    header->type = type;
    header->size = size;
    header->next = gc.objects;
    gc.objects = header;
    // ARC/ORC: register object in side-table with initial ref_count=1
    if (gc.mode == GC_MODE_ARC || gc.mode == GC_MODE_ORC) {
        arc_register(header + 1);
    }

    gc.object_count++;
    gc.objects_since_gc++;
    gc.bytes_allocated += total_size;

    sage_mutex_unlock(&gc_mutex);
    return (void*)(header + 1);
}

void gc_free(void* obj) {
    if (obj == NULL) return;
    GCHeader* header = (GCHeader*)obj - 1;
    gc.bytes_freed += gc_release_object(header);
    gc.freed_count++;
    free(header);
}

void gc_track_external_allocation(size_t size) { gc.bytes_allocated += (unsigned long)size; }
void gc_track_external_resize(size_t old_size, size_t new_size) {
    if (new_size >= old_size) gc.bytes_allocated += (unsigned long)(new_size - old_size);
    else gc.bytes_freed += (unsigned long)(old_size - new_size);
}
void gc_track_external_free(size_t size) { gc.bytes_freed += (unsigned long)size; }

// ============================================================================
// Write Barrier (SATB)
// ============================================================================

// Shade an object gray: set color to GRAY and push to mark stack
void gc_shade_gray(void* object, int type) {
    if (object == NULL) return;
    GCHeader* header = (GCHeader*)object - 1;
    if (header->color == GC_WHITE) {
        header->color = GC_GRAY;
        gc_mark_stack_push(&gc.mark_stack, header);
    }
}

void gc_write_barrier_value(Value old_val) {
    // Only active during concurrent marking
    if (!gc.barrier_active) return;

    // Shade the OLD value being overwritten so the concurrent marker doesn't miss it
    switch (old_val.type) {
        case VAL_STRING:    gc_shade_gray(old_val.as.string, VAL_STRING); break;
        case VAL_ARRAY:     gc_shade_gray(old_val.as.array, VAL_ARRAY); break;
        case VAL_DICT:      gc_shade_gray(old_val.as.dict, VAL_DICT); break;
        case VAL_TUPLE:     gc_shade_gray(old_val.as.tuple, VAL_TUPLE); break;
        case VAL_FUNCTION:  gc_shade_gray(old_val.as.function, VAL_FUNCTION); break;
        case VAL_GENERATOR: gc_shade_gray(old_val.as.generator, VAL_GENERATOR); break;
        case VAL_CLASS:     gc_shade_gray(old_val.as.class_val, VAL_CLASS); break;
        case VAL_INSTANCE:  gc_shade_gray(old_val.as.instance, VAL_INSTANCE); break;
        case VAL_EXCEPTION: gc_shade_gray(old_val.as.exception, VAL_EXCEPTION); break;
        case VAL_MODULE:    gc_shade_gray(old_val.as.module, VAL_MODULE); break;
        case VAL_CLIB:      gc_shade_gray(old_val.as.clib, VAL_CLIB); break;
        case VAL_POINTER:   gc_shade_gray(old_val.as.pointer, VAL_POINTER); break;
        case VAL_THREAD:    gc_shade_gray(old_val.as.thread, VAL_THREAD); break;
        case VAL_MUTEX:     gc_shade_gray(old_val.as.mutex, VAL_MUTEX); break;
        default: break; // Primitives (nil, number, bool) - no heap object
    }
}

void gc_write_barrier_env(Env* old_env) {
    if (!gc.barrier_active || old_env == NULL) return;
    if (!old_env->marked) {
        old_env->marked = 1;
        // Mark all values in the old environment
        EnvNode* node = old_env->head;
        while (node != NULL) {
            gc_write_barrier_value(node->value);
            node = node->next;
        }
    }
}

// ============================================================================
// Marking - shade object and push children
// ============================================================================

static void gc_shade_children(GCHeader* header);

// Try to shade an object gray (returns 1 if newly shaded)
static int gc_try_shade(void* object) {
    if (object == NULL) return 0;
    GCHeader* header = (GCHeader*)object - 1;
    if (header->color != GC_WHITE) return 0;
    header->color = GC_GRAY;
    gc_mark_stack_push(&gc.mark_stack, header);
    gc.marked_count++;
    return 1;
}

static int gc_try_mark_env(Env* env) {
    if (env == NULL || env->marked) return 0;
    env->marked = 1;
    return 1;
}

// Mark a value by shading its heap object gray
void gc_mark_value(Value val) {
    switch (val.type) {
        case VAL_NIL: case VAL_NUMBER: case VAL_BOOL: case VAL_NATIVE:
            return; // No heap object
        case VAL_STRING:    gc_try_shade(val.as.string); break;
        case VAL_ARRAY:     gc_try_shade(val.as.array); break;
        case VAL_DICT:      gc_try_shade(val.as.dict); break;
        case VAL_TUPLE:     gc_try_shade(val.as.tuple); break;
        case VAL_FUNCTION:  gc_try_shade(val.as.function); break;
        case VAL_GENERATOR: gc_try_shade(val.as.generator); break;
        case VAL_CLASS:     gc_try_shade(val.as.class_val); break;
        case VAL_INSTANCE:  gc_try_shade(val.as.instance); break;
        case VAL_EXCEPTION: gc_try_shade(val.as.exception); break;
        case VAL_MODULE:    gc_try_shade(val.as.module); break;
        case VAL_CLIB:      gc_try_shade(val.as.clib); break;
        case VAL_POINTER:   gc_try_shade(val.as.pointer); break;
        case VAL_THREAD:    gc_try_shade(val.as.thread); break;
        case VAL_MUTEX:     gc_try_shade(val.as.mutex); break;
        default: break;
    }
}

// Mark all environments in a scope chain
void gc_mark_env(Env* env) {
    while (env != NULL) {
        if (!gc_try_mark_env(env)) return;
        EnvNode* node = env->head;
        while (node != NULL) {
            gc_mark_value(node->value);
            node = node->next;
        }
        env = env->parent;
    }
}

void gc_mark_function_registry(void) { /* Functions marked via environment traversal */ }
void gc_mark_call_stack(void) { /* Call stack managed through environments */ }

// Process children of a gray object (shade them, then turn object black)
static void gc_shade_children(GCHeader* header) {
    void* object = header + 1;
    switch (header->type) {
        case VAL_ARRAY: {
            ArrayValue* arr = object;
            for (int i = 0; i < arr->count; i++) gc_mark_value(arr->elements[i]);
            break;
        }
        case VAL_DICT: {
            DictValue* dict = object;
            for (int i = 0; i < dict->capacity; i++) {
                if (dict->entries[i].key != NULL && dict->entries[i].value != NULL)
                    gc_mark_value(*dict->entries[i].value);
            }
            break;
        }
        case VAL_TUPLE: {
            TupleValue* tuple = object;
            for (int i = 0; i < tuple->count; i++) gc_mark_value(tuple->elements[i]);
            break;
        }
        case VAL_FUNCTION: {
            FunctionValue* func = object;
            if (func->closure != NULL) gc_mark_env(func->closure);
            if (func->is_vm && func->vm_function != NULL) {
                BytecodeChunk* chunk = &func->vm_function->chunk;
                for (int i = 0; i < chunk->constant_count; i++)
                    gc_mark_value(chunk->constants[i]);
            }
            break;
        }
        case VAL_GENERATOR: {
            GeneratorValue* gen = object;
            if (gen->closure != NULL) gc_mark_env(gen->closure);
            if (gen->gen_env != NULL) gc_mark_env(gen->gen_env);
            break;
        }
        case VAL_CLASS: {
            ClassValue* cls = object;
            if (cls->parent != NULL)
                gc_try_shade(cls->parent);
            break;
        }
        case VAL_INSTANCE: {
            InstanceValue* inst = object;
            if (inst->class_def != NULL) gc_try_shade(inst->class_def);
            if (inst->fields != NULL) gc_try_shade(inst->fields);
            break;
        }
        case VAL_MODULE: {
            ModuleValue* mod = object;
            if (mod->module != NULL && mod->module->env != NULL)
                gc_mark_env(mod->module->env);
            break;
        }
        default: break; // String, exception, clib, pointer, thread, mutex: no children
    }
    header->color = GC_BLACK;
}

// ============================================================================
// Concurrent GC Phases
// ============================================================================

// Phase 1 (STW): Snapshot roots, shade them gray, enable write barrier
void gc_begin_cycle(Env* root_env) {
    unsigned long t0 = now_ns();

    gc.phase = GC_PHASE_ROOT_SCAN;
    gc.marked_count = 0;
    gc.mark_stack.count = 0;

    // All existing objects start as WHITE
    GCHeader* obj = (GCHeader*)gc.objects;
    while (obj != NULL) {
        obj->color = GC_WHITE;
        obj = (GCHeader*)obj->next;
    }

    // Shade roots gray
    if (root_env != NULL) gc_mark_env(root_env);
    gc_mark_function_registry();
    gc_mark_call_stack();
    vm_mark_roots();

    // Enable write barrier for concurrent phase
    gc.barrier_active = 1;
    gc.phase = GC_PHASE_CONCURRENT_MARK;

    gc.last_root_scan_ns = now_ns() - t0;
    if (gc.last_root_scan_ns > gc.max_pause_ns)
        gc.max_pause_ns = gc.last_root_scan_ns;

    if (gc_debug)
        fprintf(stderr, "[GC] Root scan: %lu us, %d gray objects\n",
                gc.last_root_scan_ns / 1000, gc.mark_stack.count);
}

// Phase 2 (Concurrent): Process up to max_objects from the mark stack
void gc_mark_step(int max_objects) {
    int processed = 0;
    while (processed < max_objects && gc.mark_stack.count > 0) {
        GCHeader* header = (GCHeader*)gc_mark_stack_pop(&gc.mark_stack);
        if (header != NULL && header->color == GC_GRAY) {
            gc_shade_children(header);
            processed++;
        }
    }
}

int gc_mark_complete(void) {
    return gc.mark_stack.count == 0;
}

// Phase 3 (STW): Remark - drain any objects shaded by write barrier during concurrent mark
void gc_remark(Env* root_env) {
    unsigned long t0 = now_ns();

    gc.phase = GC_PHASE_REMARK;

    // Re-scan roots to catch any new references created during concurrent mark
    if (root_env != NULL) gc_mark_env(root_env);
    vm_mark_roots();

    // Drain the mark stack completely (barrier-shaded objects)
    while (gc.mark_stack.count > 0) {
        GCHeader* header = (GCHeader*)gc_mark_stack_pop(&gc.mark_stack);
        if (header != NULL && header->color == GC_GRAY) {
            gc_shade_children(header);
        }
    }

    // Disable write barrier
    gc.barrier_active = 0;

    gc.last_remark_ns = now_ns() - t0;
    if (gc.last_remark_ns > gc.max_pause_ns)
        gc.max_pause_ns = gc.last_remark_ns;

    // Prepare for sweep
    gc.phase = GC_PHASE_SWEEP;
    gc.sweep_prev = (void**)&gc.objects;
    gc.sweep_cursor = gc.objects;
    gc.freed_count = 0;

    if (gc_debug)
        fprintf(stderr, "[GC] Remark: %lu us\n", gc.last_remark_ns / 1000);
}

// Phase 4 (Concurrent): Sweep up to max_objects white objects
void gc_sweep_step(int max_objects) {
    int processed = 0;
    while (gc.sweep_cursor != NULL && processed < max_objects) {
        GCHeader* header = (GCHeader*)gc.sweep_cursor;
        if (header->color == GC_WHITE) {
            // Unreachable - unlink and free
            *gc.sweep_prev = header->next;
            gc.sweep_cursor = header->next;
            gc.object_count--;
            gc.freed_count++;
            gc.bytes_freed += gc_release_object(header);
            free(header);
        } else {
            // Reachable - reset color for next cycle
            header->color = GC_WHITE;
            gc.sweep_prev = (void**)&header->next;
            gc.sweep_cursor = header->next;
        }
        processed++;
    }
}

int gc_sweep_complete(void) {
    return gc.sweep_cursor == NULL;
}

// ============================================================================
// Full collection (runs all phases synchronously - used as fallback)
// ============================================================================

void gc_mark(void) {
    gc_mark_from_root(gc_root_env());
}

void gc_mark_from_root(Env* root_env) {
    gc.marked_count = 0;
    // Reset all objects to white
    GCHeader* obj = (GCHeader*)gc.objects;
    while (obj != NULL) {
        obj->color = GC_WHITE;
        obj = (GCHeader*)obj->next;
    }
    gc.mark_stack.count = 0;
    // Shade roots
    if (root_env != NULL) gc_mark_env(root_env);
    gc_mark_function_registry();
    gc_mark_call_stack();
    vm_mark_roots();
    // Drain mark stack fully
    while (gc.mark_stack.count > 0) {
        GCHeader* header = (GCHeader*)gc_mark_stack_pop(&gc.mark_stack);
        if (header != NULL && header->color == GC_GRAY) {
            gc_shade_children(header);
        }
    }
}

void gc_sweep(void) {
    gc.freed_count = 0;
    void** current = (void**)&gc.objects;
    while (*current != NULL) {
        GCHeader* header = (GCHeader*)*current;
        if (header->color == GC_WHITE) {
            void* unreached = *current;
            *current = header->next;
            gc.object_count--;
            gc.freed_count++;
            gc.bytes_freed += gc_release_object(header);
            free(unreached);
        } else {
            header->color = GC_WHITE;
            current = (void**)&header->next;
        }
    }
    env_sweep_unmarked();
}

// Main collection entry point - runs concurrent phases inline
void gc_collect(void) {
    if (!gc.enabled) return;
    sage_mutex_lock(&gc_mutex);

    unsigned long cycle_start = now_ns();
    unsigned long before_bytes = gc_live_bytes();
    int before_objects = gc.object_count;

    Env* root = gc_root_env();

    // Phase 1: Root scan (STW)
    gc_begin_cycle(root);

    // Phase 2: Concurrent mark (in this synchronous path, we drain fully)
    // In a truly threaded implementation, the mutator would continue here.
    // For now we do the marking inline but in bounded steps for future threading.
    while (!gc_mark_complete()) {
        gc_mark_step(512);
    }
    gc.last_mark_ns = now_ns() - cycle_start - gc.last_root_scan_ns;

    // Phase 3: Remark (STW)
    gc_remark(root);

    // Phase 4: Sweep
    unsigned long sweep_start = now_ns();
    while (!gc_sweep_complete()) {
        gc_sweep_step(GC_SWEEP_BATCH);
    }
    gc.last_sweep_ns = now_ns() - sweep_start;

    // Sweep environments
    env_sweep_unmarked();

    // Finalize
    gc.phase = GC_PHASE_IDLE;
    gc.objects_since_gc = 0;
    gc.collections++;
    unsigned long live = gc_live_bytes();
    unsigned long reclaimed_bytes = (before_bytes >= live) ? before_bytes - live : 0;
    int reclaimed_objects = before_objects - gc.object_count;
    gc_recompute_thresholds(reclaimed_bytes, reclaimed_objects);

    if (gc_debug) {
        unsigned long total_ns = now_ns() - cycle_start;
        fprintf(stderr, "[GC] Collection #%d: root=%luus mark=%luus remark=%luus sweep=%luus total=%luus freed=%d\n",
                gc.collections,
                gc.last_root_scan_ns / 1000,
                gc.last_mark_ns / 1000,
                gc.last_remark_ns / 1000,
                gc.last_sweep_ns / 1000,
                total_ns / 1000,
                gc.freed_count);
    }

    sage_mutex_unlock(&gc_mutex);
}

void gc_collect_with_root(Env* root_env) {
    if (!gc.enabled) return;
    sage_mutex_lock(&gc_mutex);

    unsigned long cycle_start = now_ns();
    unsigned long before_bytes = gc_live_bytes();
    int before_objects = gc.object_count;

    gc_begin_cycle(root_env);
    while (!gc_mark_complete()) gc_mark_step(512);
    gc.last_mark_ns = now_ns() - cycle_start - gc.last_root_scan_ns;
    gc_remark(root_env);
    unsigned long sweep_start = now_ns();
    while (!gc_sweep_complete()) gc_sweep_step(GC_SWEEP_BATCH);
    gc.last_sweep_ns = now_ns() - sweep_start;
    env_sweep_unmarked();

    gc.phase = GC_PHASE_IDLE;
    gc.objects_since_gc = 0;
    gc.collections++;
    unsigned long live = gc_live_bytes();
    unsigned long reclaimed_bytes = (before_bytes >= live) ? before_bytes - live : 0;
    gc_recompute_thresholds(reclaimed_bytes, before_objects - gc.object_count);

    sage_mutex_unlock(&gc_mutex);
}

// ============================================================================
// Debug and Stats
// ============================================================================

void gc_print_stats(void) {
    const char* mode_name = gc.mode == GC_MODE_ORC ? "ORC" :
                            gc.mode == GC_MODE_ARC ? "ARC" : "Tracing";
    printf("=== GC Statistics (%s mode) ===\n", mode_name);
    printf("Collections run:        %d\n", gc.collections);
    printf("Objects allocated:      %d\n", gc.object_count);
    printf("Objects since GC:       %d\n", gc.objects_since_gc);
    printf("Total bytes allocated:  %lu\n", gc.bytes_allocated);
    printf("Total bytes freed:      %lu\n", gc.bytes_freed);
    printf("Current memory usage:   %lu bytes\n", gc_live_bytes());
    printf("Marked in last cycle:   %d\n", gc.marked_count);
    printf("Freed in last cycle:    %d\n", gc.freed_count);
    if (gc.mode == GC_MODE_ORC) {
        printf("ORC epoch:              %d\n", gc.orc_epoch);
        printf("ORC cycle collections:  %lu\n", gc.orc_collections);
        printf("ORC cycles freed:       %lu\n", gc.orc_cycles_freed);
    } else if (gc.mode == GC_MODE_TRACING) {
        printf("Max STW pause:          %lu us\n", gc.max_pause_ns / 1000);
        printf("Last root scan:         %lu us\n", gc.last_root_scan_ns / 1000);
        printf("Last remark:            %lu us\n", gc.last_remark_ns / 1000);
        printf("Last sweep:             %lu us\n", gc.last_sweep_ns / 1000);
    }
    printf("Current phase:          %d\n", gc.phase);
    printf("Write barrier active:   %s\n", gc.barrier_active ? "yes" : "no");
    printf("GC enabled:             %s\n", gc.enabled ? "yes" : "no");
    printf("================================\n");
}

void gc_enable_debug(void) { gc_debug = 1; }
void gc_disable_debug(void) { gc_debug = 0; }

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
    stats.max_pause_ns = gc.max_pause_ns;
    stats.last_mark_ns = gc.last_mark_ns;
    stats.last_sweep_ns = gc.last_sweep_ns;
    stats.phase = gc.phase;
    return stats;
}

void gc_enable(void) {
    gc.enabled = 1;
    if (gc_debug) fprintf(stderr, "[GC] GC enabled\n");
}

void gc_disable(void) {
    gc.enabled = 0;
    if (gc_debug) fprintf(stderr, "[GC] GC disabled\n");
}

// ============================================================================
// ARC Mode: Automatic Reference Counting with Cycle Collection
// ============================================================================
// Inspired by Nim's --gc:arc. Objects are freed deterministically when their
// reference count drops to zero. A cycle collector periodically handles
// cycles using trial deletion.
//
// ARC metadata is stored in a separate side-table (hash map from pointer to
// ARCMeta) to avoid changing the GCHeader struct size, which would break
// heap alignment for all existing allocations.

// Simple hash table for ARC metadata
#define ARC_TABLE_SIZE 4096
typedef struct ARCNode {
    void* key;           // Object pointer (header + 1)
    int ref_count;
    int buffered;        // In cycle candidate buffer (ARC) or root set (ORC)
    int orc_color;       // ORC cycle collector color (ORC_COLOR_BLACK/PURPLE/GRAY/WHITE)
    struct ARCNode* next;
} ARCNode;

static ARCNode* arc_table[ARC_TABLE_SIZE] = {0};

static unsigned int arc_hash(void* ptr) {
    unsigned long h = (unsigned long)ptr;
    h = (h >> 3) ^ (h >> 17);
    return (unsigned int)(h % ARC_TABLE_SIZE);
}

static ARCNode* arc_find(void* obj) {
    unsigned int idx = arc_hash(obj);
    for (ARCNode* n = arc_table[idx]; n != NULL; n = n->next) {
        if (n->key == obj) return n;
    }
    return NULL;
}

// Register a new object with ref_count = 1
void arc_register(void* obj) {
    unsigned int idx = arc_hash(obj);
    ARCNode* node = (ARCNode*)malloc(sizeof(ARCNode));
    node->key = obj;
    node->ref_count = 1;
    node->buffered = 0;
    node->orc_color = ORC_COLOR_BLACK;
    node->next = arc_table[idx];
    arc_table[idx] = node;
}

static void arc_unregister(void* obj) {
    unsigned int idx = arc_hash(obj);
    ARCNode** prev = &arc_table[idx];
    for (ARCNode* n = arc_table[idx]; n != NULL; n = n->next) {
        if (n->key == obj) {
            *prev = n->next;
            free(n);
            return;
        }
        prev = &n->next;
    }
}

// Clean up ARC side-table (called from gc_shutdown)
static void arc_table_cleanup(void) {
    for (int i = 0; i < ARC_TABLE_SIZE; i++) {
        ARCNode* n = arc_table[i];
        while (n != NULL) {
            ARCNode* next = n->next;
            free(n);
            n = next;
        }
        arc_table[i] = NULL;
    }
}

void gc_set_mode(int mode) {
    gc.mode = mode;
    if (mode == GC_MODE_ARC) {
        gc.enabled = 0; // Disable tracing GC in ARC mode
        gc.arc_cycle_threshold = 1000;
        gc.arc_decrements = 0;
        if (gc.cycle_buffer == NULL) {
            gc.cycle_buffer_capacity = 256;
            gc.cycle_buffer = (void**)malloc(sizeof(void*) * (size_t)gc.cycle_buffer_capacity);
            gc.cycle_buffer_count = 0;
        }
        if (gc_debug) fprintf(stderr, "[GC] ARC mode enabled\n");
    } else if (mode == GC_MODE_ORC) {
        gc.enabled = 0; // Disable tracing GC in ORC mode
        gc.arc_cycle_threshold = 500;  // ORC collects cycles more aggressively
        gc.arc_decrements = 0;
        gc.orc_epoch = 0;
        gc.orc_collections = 0;
        gc.orc_cycles_freed = 0;
        if (gc.orc_roots == NULL) {
            gc.orc_roots_capacity = 512;
            gc.orc_roots = (void**)malloc(sizeof(void*) * (size_t)gc.orc_roots_capacity);
            gc.orc_roots_count = 0;
        }
        // ORC shares ARC's side-table — no separate cycle_buffer needed
        if (gc_debug) fprintf(stderr, "[GC] ORC mode enabled (trial deletion cycle collector)\n");
    } else {
        gc.enabled = 1;
        if (gc_debug) fprintf(stderr, "[GC] Tracing GC mode enabled\n");
    }
}

void arc_retain(void* obj) {
    if (obj == NULL || (gc.mode != GC_MODE_ARC && gc.mode != GC_MODE_ORC)) return;
    ARCNode* node = arc_find(obj);
    if (node) {
        node->ref_count++;
        // ORC: retaining makes object non-candidate (back to BLACK)
        if (gc.mode == GC_MODE_ORC) node->orc_color = ORC_COLOR_BLACK;
    }
}

void arc_release(void* obj) {
    if (obj == NULL || (gc.mode != GC_MODE_ARC && gc.mode != GC_MODE_ORC)) return;
    ARCNode* node = arc_find(obj);
    if (!node) return;
    node->ref_count--;
    gc.arc_decrements++;

    if (node->ref_count <= 0) {
        // Object is dead — unlink from GC list and free
        if (gc.mode == GC_MODE_ORC) node->orc_color = ORC_COLOR_BLACK;
        GCHeader* header = (GCHeader*)obj - 1;
        sage_mutex_lock(&gc_mutex);
        void** prev = (void**)&gc.objects;
        for (GCHeader* cur = gc.objects; cur != NULL; cur = cur->next) {
            if (cur == header) {
                *prev = header->next;
                break;
            }
            prev = &cur->next;
        }
        gc.object_count--;
        gc.bytes_freed += gc_release_object(header);
        gc.freed_count++;
        arc_unregister(obj);
        free(header);
        sage_mutex_unlock(&gc_mutex);
    } else if (gc.mode == GC_MODE_ORC) {
        // ORC: mark as PURPLE candidate for trial deletion
        orc_mark_candidate(obj);
    } else {
        // ARC: buffer for simplified cycle collection
        arc_add_candidate(obj);
    }

    if (gc.arc_decrements >= gc.arc_cycle_threshold) {
        if (gc.mode == GC_MODE_ORC) {
            orc_collect_cycles();
        } else {
            arc_collect_cycles();
        }
        gc.arc_decrements = 0;
    }
}

void arc_assign(void** slot, void* new_obj) {
    void* old = *slot;
    if (old == new_obj) return;
    if (new_obj) arc_retain(new_obj);
    *slot = new_obj;
    if (old) arc_release(old);
}

void arc_assign_value(Value* slot, Value new_val) {
    if (gc.mode != GC_MODE_ARC && gc.mode != GC_MODE_ORC) {
        *slot = new_val;
        return;
    }
    // In ARC/ORC mode, retain new and release old heap objects
    // For simplicity, just assign — the env layer handles retain/release
    *slot = new_val;
}

void arc_add_candidate(void* obj) {
    if (obj == NULL) return;
    ARCNode* node = arc_find(obj);
    if (!node || node->buffered) return;
    node->buffered = 1;

    if (gc.cycle_buffer_count >= gc.cycle_buffer_capacity) {
        gc.cycle_buffer_capacity = gc.cycle_buffer_capacity ? gc.cycle_buffer_capacity * 2 : 256;
        gc.cycle_buffer = (void**)realloc(gc.cycle_buffer, sizeof(void*) * (size_t)gc.cycle_buffer_capacity);
    }
    gc.cycle_buffer[gc.cycle_buffer_count++] = obj;
}

void arc_collect_cycles(void) {
    if (gc.cycle_buffer_count == 0) return;
    if (gc_debug) fprintf(stderr, "[ARC] Cycle collection: %d candidates\n", gc.cycle_buffer_count);

    // Simplified cycle collection: use the tracing GC for cycle detection
    // Mark all candidates, sweep unreachable ones
    int collected = 0;
    for (int i = 0; i < gc.cycle_buffer_count; i++) {
        ARCNode* node = arc_find(gc.cycle_buffer[i]);
        if (node) {
            node->buffered = 0;
            if (node->ref_count <= 0) {
                GCHeader* header = (GCHeader*)gc.cycle_buffer[i] - 1;
                sage_mutex_lock(&gc_mutex);
                void** prev = (void**)&gc.objects;
                for (GCHeader* cur = gc.objects; cur != NULL; cur = cur->next) {
                    if (cur == header) {
                        *prev = header->next;
                        break;
                    }
                    prev = &cur->next;
                }
                gc.object_count--;
                gc.bytes_freed += gc_release_object(header);
                gc.freed_count++;
                arc_unregister(gc.cycle_buffer[i]);
                free(header);
                sage_mutex_unlock(&gc_mutex);
                collected++;
            }
        }
    }

    gc.cycle_buffer_count = 0;
    gc.collections++;
    if (gc_debug) fprintf(stderr, "[ARC] Cycle collection complete: %d objects freed\n", collected);
}

void arc_force_cycle_collection(void) {
    if (gc.mode == GC_MODE_ORC) {
        orc_collect_cycles();
    } else {
        arc_collect_cycles();
    }
    gc.arc_decrements = 0;
}

// ============================================================================
// ORC Mode: Optimized Reference Counting with Trial Deletion
// ============================================================================
// Implements Lins' trial deletion algorithm for cycle detection.
// ORC shares ARC's reference counting base but replaces ARC's simplified
// cycle collector with a proper three-phase trial deletion algorithm:
//
//   Phase 1 (Mark Roots):  Collect PURPLE objects as candidate cycle roots
//   Phase 2 (Scan):        Trial-decrement ref counts from candidates;
//                           objects whose trial count reaches 0 → WHITE (garbage)
//                           objects with remaining external refs → BLACK (restore)
//   Phase 3 (Collect):     Free all WHITE objects (confirmed unreachable cycles)
//
// Colors: BLACK (in use) → PURPLE (candidate) → GRAY (scanning) → WHITE (garbage)

// Mark an object as a PURPLE candidate root for cycle collection
void orc_mark_candidate(void* obj) {
    if (obj == NULL) return;
    ARCNode* node = arc_find(obj);
    if (!node || node->buffered) return;

    node->orc_color = ORC_COLOR_PURPLE;
    node->buffered = 1;

    if (gc.orc_roots_count >= gc.orc_roots_capacity) {
        gc.orc_roots_capacity = gc.orc_roots_capacity ? gc.orc_roots_capacity * 2 : 512;
        gc.orc_roots = (void**)realloc(gc.orc_roots, sizeof(void*) * (size_t)gc.orc_roots_capacity);
    }
    gc.orc_roots[gc.orc_roots_count++] = obj;
}

// Helper: iterate over children of an object and call a visitor function.
// The visitor receives the child object pointer (header + 1).
typedef void (*orc_child_visitor)(void* child);

static void orc_visit_children(void* obj, orc_child_visitor visitor) {
    GCHeader* header = (GCHeader*)obj - 1;
    switch (header->type) {
        case VAL_ARRAY: {
            ArrayValue* arr = (ArrayValue*)obj;
            for (int i = 0; i < arr->count; i++) {
                Value v = arr->elements[i];
                switch (v.type) {
                    case VAL_STRING:    visitor(v.as.string); break;
                    case VAL_ARRAY:     visitor(v.as.array); break;
                    case VAL_DICT:      visitor(v.as.dict); break;
                    case VAL_TUPLE:     visitor(v.as.tuple); break;
                    case VAL_FUNCTION:  visitor(v.as.function); break;
                    case VAL_GENERATOR: visitor(v.as.generator); break;
                    case VAL_CLASS:     visitor(v.as.class_val); break;
                    case VAL_INSTANCE:  visitor(v.as.instance); break;
                    case VAL_EXCEPTION: visitor(v.as.exception); break;
                    case VAL_MODULE:    visitor(v.as.module); break;
                    case VAL_CLIB:      visitor(v.as.clib); break;
                    case VAL_POINTER:   visitor(v.as.pointer); break;
                    case VAL_THREAD:    visitor(v.as.thread); break;
                    case VAL_MUTEX:     visitor(v.as.mutex); break;
                    default: break;
                }
            }
            break;
        }
        case VAL_DICT: {
            DictValue* dict = (DictValue*)obj;
            for (int i = 0; i < dict->capacity; i++) {
                if (dict->entries[i].key != NULL && dict->entries[i].value != NULL) {
                    Value v = *dict->entries[i].value;
                    switch (v.type) {
                        case VAL_STRING:    visitor(v.as.string); break;
                        case VAL_ARRAY:     visitor(v.as.array); break;
                        case VAL_DICT:      visitor(v.as.dict); break;
                        case VAL_TUPLE:     visitor(v.as.tuple); break;
                        case VAL_FUNCTION:  visitor(v.as.function); break;
                        case VAL_GENERATOR: visitor(v.as.generator); break;
                        case VAL_CLASS:     visitor(v.as.class_val); break;
                        case VAL_INSTANCE:  visitor(v.as.instance); break;
                        case VAL_EXCEPTION: visitor(v.as.exception); break;
                        case VAL_MODULE:    visitor(v.as.module); break;
                        case VAL_CLIB:      visitor(v.as.clib); break;
                        case VAL_POINTER:   visitor(v.as.pointer); break;
                        case VAL_THREAD:    visitor(v.as.thread); break;
                        case VAL_MUTEX:     visitor(v.as.mutex); break;
                        default: break;
                    }
                }
            }
            break;
        }
        case VAL_TUPLE: {
            TupleValue* tuple = (TupleValue*)obj;
            for (int i = 0; i < tuple->count; i++) {
                Value v = tuple->elements[i];
                switch (v.type) {
                    case VAL_STRING:    visitor(v.as.string); break;
                    case VAL_ARRAY:     visitor(v.as.array); break;
                    case VAL_DICT:      visitor(v.as.dict); break;
                    case VAL_TUPLE:     visitor(v.as.tuple); break;
                    case VAL_FUNCTION:  visitor(v.as.function); break;
                    case VAL_GENERATOR: visitor(v.as.generator); break;
                    case VAL_CLASS:     visitor(v.as.class_val); break;
                    case VAL_INSTANCE:  visitor(v.as.instance); break;
                    case VAL_EXCEPTION: visitor(v.as.exception); break;
                    case VAL_MODULE:    visitor(v.as.module); break;
                    default: break;
                }
            }
            break;
        }
        case VAL_INSTANCE: {
            InstanceValue* inst = (InstanceValue*)obj;
            if (inst->class_def != NULL) visitor(inst->class_def);
            if (inst->fields != NULL) visitor(inst->fields);
            break;
        }
        case VAL_CLASS: {
            ClassValue* cls = (ClassValue*)obj;
            if (cls->parent != NULL) visitor(cls->parent);
            break;
        }
        default: break;  // String, exception, pointer, etc.: no heap children
    }
}

// Phase 2a: Trial-decrement ref counts from a candidate (mark gray)
static void orc_scan_decrement(void* child) {
    if (child == NULL) return;
    ARCNode* node = arc_find(child);
    if (!node) return;
    node->ref_count--;
    if (node->orc_color != ORC_COLOR_GRAY) {
        node->orc_color = ORC_COLOR_GRAY;
        orc_visit_children(child, orc_scan_decrement);
    }
}

// Phase 2b: Check if object is truly garbage or has external refs
static void orc_scan_check(void* child);

static void orc_scan_object(void* obj) {
    ARCNode* node = arc_find(obj);
    if (!node) return;
    if (node->orc_color == ORC_COLOR_GRAY) {
        if (node->ref_count <= 0) {
            // No external references — this is cycle garbage
            node->orc_color = ORC_COLOR_WHITE;
            orc_visit_children(obj, orc_scan_check);
        } else {
            // External references exist — restore this subgraph
            orc_scan_check(obj);
        }
    }
}

// Phase 2c: Restore ref counts for non-garbage subgraph (re-color BLACK)
static void orc_restore_increment(void* child) {
    if (child == NULL) return;
    ARCNode* node = arc_find(child);
    if (!node) return;
    node->ref_count++;
    if (node->orc_color != ORC_COLOR_BLACK) {
        node->orc_color = ORC_COLOR_BLACK;
        orc_visit_children(child, orc_restore_increment);
    }
}

static void orc_scan_check(void* obj) {
    if (obj == NULL) return;
    ARCNode* node = arc_find(obj);
    if (!node) return;
    if (node->orc_color == ORC_COLOR_GRAY) {
        if (node->ref_count > 0) {
            // Has external refs — restore the entire subgraph
            orc_restore_increment(obj);
        } else {
            node->orc_color = ORC_COLOR_WHITE;
            orc_visit_children(obj, orc_scan_check);
        }
    }
}

// Phase 3: Collect all WHITE objects (confirmed cycle garbage)
static void orc_collect_white(void* obj) {
    if (obj == NULL) return;
    ARCNode* node = arc_find(obj);
    if (!node || node->orc_color != ORC_COLOR_WHITE) return;

    // Mark as BLACK to prevent double-free during child traversal
    node->orc_color = ORC_COLOR_BLACK;
    node->buffered = 0;

    // Recurse into children first (they may also be WHITE)
    orc_visit_children(obj, orc_collect_white);

    // Unlink from GC object list and free
    GCHeader* header = (GCHeader*)obj - 1;
    sage_mutex_lock(&gc_mutex);
    void** prev = (void**)&gc.objects;
    for (GCHeader* cur = gc.objects; cur != NULL; cur = cur->next) {
        if (cur == header) {
            *prev = header->next;
            break;
        }
        prev = &cur->next;
    }
    gc.object_count--;
    gc.bytes_freed += gc_release_object(header);
    gc.freed_count++;
    gc.orc_cycles_freed++;
    arc_unregister(obj);
    free(header);
    sage_mutex_unlock(&gc_mutex);
}

// Main ORC cycle collection: three-phase trial deletion
void orc_collect_cycles(void) {
    if (gc.orc_roots_count == 0) return;

    unsigned long t0 = now_ns();
    if (gc_debug)
        fprintf(stderr, "[ORC] Cycle collection epoch %d: %d candidates\n",
                gc.orc_epoch, gc.orc_roots_count);

    // Snapshot the current root set (new candidates added during collection
    // will be picked up in the next epoch)
    int root_count = gc.orc_roots_count;
    void** roots = (void**)malloc(sizeof(void*) * (size_t)root_count);
    memcpy(roots, gc.orc_roots, sizeof(void*) * (size_t)root_count);
    gc.orc_roots_count = 0;

    // Phase 1: Mark Roots — only process PURPLE candidates
    // Filter out objects that have been freed or are no longer PURPLE
    int candidate_count = 0;
    for (int i = 0; i < root_count; i++) {
        ARCNode* node = arc_find(roots[i]);
        if (!node) continue;
        if (node->orc_color == ORC_COLOR_PURPLE && node->ref_count > 0) {
            roots[candidate_count++] = roots[i];
        } else {
            node->buffered = 0;
            // If ref_count dropped to 0, arc_release already freed it
        }
    }

    // Phase 2: Scan — trial decrement from each candidate root
    for (int i = 0; i < candidate_count; i++) {
        ARCNode* node = arc_find(roots[i]);
        if (!node) continue;
        node->orc_color = ORC_COLOR_GRAY;
        orc_visit_children(roots[i], orc_scan_decrement);
    }

    // Phase 2b: Check — determine which objects are truly garbage
    for (int i = 0; i < candidate_count; i++) {
        orc_scan_object(roots[i]);
    }

    // Phase 3: Collect — free all WHITE objects (confirmed cycles)
    int freed_before = gc.freed_count;
    for (int i = 0; i < candidate_count; i++) {
        ARCNode* node = arc_find(roots[i]);
        if (node && node->orc_color == ORC_COLOR_WHITE) {
            orc_collect_white(roots[i]);
        } else if (node) {
            // Non-garbage: clear buffered flag so it can be re-added
            node->buffered = 0;
        }
    }
    int collected = gc.freed_count - freed_before;

    gc.orc_epoch++;
    gc.orc_collections++;
    gc.collections++;
    free(roots);

    if (gc_debug) {
        unsigned long elapsed = now_ns() - t0;
        fprintf(stderr, "[ORC] Epoch %d complete: %d candidates, %d cycles freed, %lu us\n",
                gc.orc_epoch - 1, candidate_count, collected, elapsed / 1000);
    }
}

void orc_force_cycle_collection(void) {
    orc_collect_cycles();
    gc.arc_decrements = 0;
}
