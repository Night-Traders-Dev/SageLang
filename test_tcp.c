#define _POSIX_C_SOURCE 200809L
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <semaphore.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <stdint.h>

// Security: Cap entire-file reads to 100MB to prevent memory exhaustion DoS attacks.
#define SAGE_MAX_READ_SIZE (100 * 1024 * 1024)

typedef struct SageValue SageValue;
typedef struct SageGcHeader SageGcHeader;
typedef struct SageGcFrame SageGcFrame;

typedef struct {
    int count;
    int capacity;
    SageValue* elements;
} SageArray;

typedef struct {
    char** keys;
    SageValue* values;
    int count;
    int capacity;
} SageDict;

typedef struct {
    SageValue* elements;
    int count;
} SageTuple;

typedef enum {
    SAGE_TAG_NIL,
    SAGE_TAG_NUMBER,
    SAGE_TAG_BOOL,
    SAGE_TAG_STRING,
    SAGE_TAG_ARRAY,
    SAGE_TAG_DICT,
    SAGE_TAG_TUPLE,
    SAGE_TAG_FUNCTION,
    SAGE_TAG_CLIB,
    SAGE_TAG_POINTER,
    SAGE_TAG_THREAD,
    SAGE_TAG_MUTEX,
    SAGE_TAG_BYTES
} SageTag;

typedef struct {
    unsigned char* data;
    int count;
} SageBytes;

struct SageValue {
    SageTag type;
    union {
        double number;
        int boolean;
        const char* string;
        SageArray* array;
        SageDict* dict;
        SageTuple* tuple;
        void* function;
        void* clib;
        void* pointer;
        void* thread;
        void* mutex;
        SageBytes* bytes;
    } as;
};

typedef struct {
    int defined;
    SageValue value;
} SageSlot;

typedef enum {
    SAGE_GC_STRING,
    SAGE_GC_ARRAY,
    SAGE_GC_DICT,
    SAGE_GC_TUPLE
} SageGcKind;

struct SageGcHeader {
    unsigned char marked;
    unsigned char kind;
    size_t size;
    SageGcHeader* next;
};

struct SageGcFrame {
    SageGcFrame* prev;
    SageSlot** slots;
    int slot_count;
};

typedef struct {
    SageGcHeader* objects;
    SageGcFrame* frames;
    int object_count;
    int collections;
    int pin_count;
    unsigned long bytes_allocated;
    unsigned long bytes_freed;
    unsigned long next_gc_bytes;
    int next_gc_objects;
    int enabled;
} SageGcState;

#define SAGE_GC_MIN_TRIGGER_BYTES 65536UL
#define SAGE_GC_MIN_TRIGGER_OBJECTS 128
static SageGcState sage_gc = {NULL, NULL, 0, 0, 0, 0, 0, SAGE_GC_MIN_TRIGGER_BYTES, SAGE_GC_MIN_TRIGGER_OBJECTS, 1};

#define SAGE_STRING_LEN(v) ((int)(((SageGcHeader*)(v).as.string - 1)->size - 1))

/* Exception handling via setjmp/longjmp */
#define SAGE_MAX_TRY_DEPTH 1024
static jmp_buf sage_try_stack[SAGE_MAX_TRY_DEPTH];
static SageValue sage_exception_value;
static int sage_try_depth = 0;

static void sage_fail(const char* message) {
    fputs(message, stderr);
    fputc('\n', stderr);
    exit(1);
}

static unsigned long sage_gc_live_bytes(void) {
    return sage_gc.bytes_allocated - sage_gc.bytes_freed;
}

static void sage_gc_recompute_thresholds(unsigned long reclaimed_bytes, int reclaimed_objects) {
    unsigned long live_bytes = sage_gc_live_bytes();
    int live_objects = sage_gc.object_count;
    unsigned long byte_padding = live_bytes / 2;
    int object_padding = live_objects / 2;
    if (byte_padding < (SAGE_GC_MIN_TRIGGER_BYTES / 2)) byte_padding = SAGE_GC_MIN_TRIGGER_BYTES / 2;
    if (object_padding < (SAGE_GC_MIN_TRIGGER_OBJECTS / 2)) object_padding = SAGE_GC_MIN_TRIGGER_OBJECTS / 2;
    if (reclaimed_bytes <= live_bytes / 8) {
        byte_padding /= 2;
        if (byte_padding < (SAGE_GC_MIN_TRIGGER_BYTES / 2)) byte_padding = SAGE_GC_MIN_TRIGGER_BYTES / 2;
    } else if (reclaimed_bytes >= live_bytes) {
        byte_padding *= 2;
    }
    if (reclaimed_objects <= live_objects / 8) {
        object_padding /= 2;
        if (object_padding < (SAGE_GC_MIN_TRIGGER_OBJECTS / 2)) object_padding = SAGE_GC_MIN_TRIGGER_OBJECTS / 2;
    } else if (reclaimed_objects >= live_objects) {
        object_padding *= 2;
    }
    sage_gc.next_gc_bytes = live_bytes + byte_padding;
    if (sage_gc.next_gc_bytes < SAGE_GC_MIN_TRIGGER_BYTES) sage_gc.next_gc_bytes = SAGE_GC_MIN_TRIGGER_BYTES;
    sage_gc.next_gc_objects = live_objects + object_padding;
    if (sage_gc.next_gc_objects < SAGE_GC_MIN_TRIGGER_OBJECTS) sage_gc.next_gc_objects = SAGE_GC_MIN_TRIGGER_OBJECTS;
}

static int sage_gc_try_mark(void* object) {
    if (object == NULL) return 0;
    SageGcHeader* header = ((SageGcHeader*)object) - 1;
    if (header->marked) return 0;
    header->marked = 1;
    return 1;
}

static void sage_gc_mark_value(SageValue value);
extern void sage_gc_mark_program_globals(void);

static void sage_gc_mark_roots(void) {
    sage_gc_mark_program_globals();
    for (SageGcFrame* frame = sage_gc.frames; frame != NULL; frame = frame->prev) {
        if (frame->slots == NULL) continue;
        for (int i = 0; i < frame->slot_count; i++) {
            if (frame->slots[i] != NULL && frame->slots[i]->defined) {
                sage_gc_mark_value(frame->slots[i]->value);
            }
        }
    }
    if (sage_try_depth > 0) sage_gc_mark_value(sage_exception_value);
}

static size_t sage_gc_release_object(SageGcHeader* header) {
    void* object = (void*)(header + 1);
    size_t freed = sizeof(SageGcHeader) + header->size;
    switch ((SageGcKind)header->kind) {
        case SAGE_GC_STRING:
            break;
        case SAGE_GC_ARRAY: {
            SageArray* array = (SageArray*)object;
            free(array->elements);
            break;
        }
        case SAGE_GC_DICT: {
            SageDict* dict = (SageDict*)object;
            for (int i = 0; i < dict->count; i++) {
                if (dict->keys[i] != NULL) {
                    free(dict->keys[i]);
                }
            }
            free(dict->keys);
            free(dict->values);
            break;
        }
        case SAGE_GC_TUPLE: {
            SageTuple* tuple = (SageTuple*)object;
            free(tuple->elements);
            break;
        }
    }
    return freed;
}

static void sage_gc_collect(void) {
    if (!sage_gc.enabled) return;
    unsigned long before_bytes = sage_gc_live_bytes();
    int before_objects = sage_gc.object_count;
    sage_gc_mark_roots();
    SageGcHeader** current = &sage_gc.objects;
    while (*current != NULL) {
        SageGcHeader* header = *current;
        if (!header->marked) {
            *current = header->next;
            sage_gc.object_count--;
            sage_gc.bytes_freed += sage_gc_release_object(header);
            free(header);
        } else {
            header->marked = 0;
            current = &header->next;
        }
    }
    sage_gc.collections++;
    sage_gc_recompute_thresholds(before_bytes - sage_gc_live_bytes(), before_objects - sage_gc.object_count);
}

static int sage_gc_should_collect(size_t incoming_size) {
    if (!sage_gc.enabled || sage_gc.pin_count > 0) return 0;
    if ((sage_gc.object_count + 1) >= sage_gc.next_gc_objects) return 1;
    return sage_gc_live_bytes() + (unsigned long)sizeof(SageGcHeader) + (unsigned long)incoming_size >= sage_gc.next_gc_bytes;
}

static void* sage_gc_alloc(SageGcKind kind, size_t size) {
    if (sage_gc.frames != NULL && sage_gc_should_collect(size)) sage_gc_collect();
    size_t total = sizeof(SageGcHeader) + size;
    SageGcHeader* header = (SageGcHeader*)malloc(total);
    if (header == NULL) sage_fail("Runtime Error: out of memory");
    header->marked = 0;
    header->kind = (unsigned char)kind;
    header->size = size;
    header->next = sage_gc.objects;
    sage_gc.objects = header;
    sage_gc.object_count++;
    sage_gc.bytes_allocated += (unsigned long)total;
    return (void*)(header + 1);
}

static void sage_gc_push_frame(SageGcFrame* frame, SageSlot** slots, int slot_count) {
    frame->prev = sage_gc.frames;
    frame->slots = slots;
    frame->slot_count = slot_count;
    sage_gc.frames = frame;
}

static void sage_gc_pop_frame(SageGcFrame* frame) {
    if (sage_gc.frames == frame) sage_gc.frames = frame->prev;
}

static void sage_gc_pin(void) { sage_gc.pin_count++; }
static void sage_gc_unpin(void) { if (sage_gc.pin_count > 0) sage_gc.pin_count--; }

static SageValue sage_gc_return(SageGcFrame* frame, SageValue value) {
    sage_gc_pop_frame(frame);
    return value;
}

static void sage_gc_shutdown(void) {
    SageGcHeader* object = sage_gc.objects;
    while (object != NULL) {
        SageGcHeader* next = object->next;
        sage_gc.bytes_freed += sage_gc_release_object(object);
        free(object);
        object = next;
    }
    sage_gc.objects = NULL;
    sage_gc.object_count = 0;
}

static void sage_gc_mark_value(SageValue value) {
    switch (value.type) {
        case SAGE_TAG_STRING:
            (void)sage_gc_try_mark((void*)value.as.string);
            return;
        case SAGE_TAG_ARRAY:
            if (sage_gc_try_mark(value.as.array)) {
                for (int i = 0; i < value.as.array->count; i++) sage_gc_mark_value(value.as.array->elements[i]);
            }
            return;
        case SAGE_TAG_DICT:
            if (sage_gc_try_mark(value.as.dict)) {
                for (int i = 0; i < value.as.dict->count; i++) sage_gc_mark_value(value.as.dict->values[i]);
            }
            return;
        case SAGE_TAG_TUPLE:
            if (sage_gc_try_mark(value.as.tuple)) {
                for (int i = 0; i < value.as.tuple->count; i++) sage_gc_mark_value(value.as.tuple->elements[i]);
            }
            return;
        default:
            return;
    }
}

static char* sage_dup_string(const char* text) {
    size_t len = strlen(text);
    char* copy = (char*)malloc(len + 1);
    if (copy == NULL) sage_fail("Runtime Error: out of memory");
    memcpy(copy, text, len + 1);
    return copy;
}

static char* sage_gc_copy_string(const char* text) {
    size_t len = strlen(text);
    char* copy = (char*)sage_gc_alloc(SAGE_GC_STRING, len + 1);
    memcpy(copy, text, len + 1);
    return copy;
}

static SageArray* sage_new_array(void) {
    SageArray* array = (SageArray*)sage_gc_alloc(SAGE_GC_ARRAY, sizeof(SageArray));
    array->count = 0;
    array->capacity = 0;
    array->elements = NULL;
    return array;
}

static SageValue sage_nil(void) { SageValue v; v.type = SAGE_TAG_NIL; v.as.number = 0; return v; }
static SageValue sage_number(double value) { SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = value; return v; }
static SageValue sage_bool(int value) { SageValue v; v.type = SAGE_TAG_BOOL; v.as.boolean = value ? 1 : 0; return v; }
static SageValue sage_string(const char* value) { SageValue v; v.type = SAGE_TAG_STRING; v.as.string = sage_gc_copy_string(value == NULL ? "" : value); return v; }
static SageValue sage_string_take(char* value) { SageValue v = sage_string(value == NULL ? "" : value); free(value); return v; }
static SageValue sage_array(void) { SageValue v; v.type = SAGE_TAG_ARRAY; v.as.array = sage_new_array(); return v; }
static SageValue sage_function(void* fn) { SageValue v; v.type = SAGE_TAG_FUNCTION; v.as.function = fn; return v; }

static SageValue sage_ffi_open(SageValue libname) {
    if (libname.type != SAGE_TAG_STRING) return sage_nil();
    void* handle = dlopen(libname.as.string, RTLD_NOW);
    if (!handle) return sage_nil();
    SageValue v; v.type = SAGE_TAG_CLIB; v.as.clib = handle; return v;
}
static SageValue sage_ffi_close(SageValue handle) {
    if (handle.type != SAGE_TAG_CLIB) return sage_nil();
    dlclose(handle.as.clib);
    return sage_nil();
}
static SageValue sage_ffi_call(SageValue handle, SageValue name, SageValue ret_type, SageValue args) {
    if (handle.type != SAGE_TAG_CLIB || name.type != SAGE_TAG_STRING || ret_type.type != SAGE_TAG_STRING)
        return sage_nil();
    void* lib_handle = handle.as.clib;
    if (!lib_handle) return sage_nil();
    void* sym = dlsym(lib_handle, name.as.string);
    if (!sym) return sage_nil();
    const char* rt = ret_type.as.string;
    int call_argc = 0;
    SageValue call_argv[4];
    if (args.type == SAGE_TAG_ARRAY) {
        call_argc = args.as.array->count;
        if (call_argc > 3) call_argc = 3;
        for (int i = 0; i < call_argc; i++) call_argv[i] = args.as.array->elements[i];
    }
    #define IS_NUM(v) ((v).type == SAGE_TAG_NUMBER)
    #define IS_STR(v) ((v).type == SAGE_TAG_STRING)
    #pragma GCC diagnostic push
    #pragma GCC diagnostic ignored "-Wpedantic"
    if (strcmp(rt, "int") == 0) {
        if (call_argc == 0) { int (*fn)(void) = (int(*)(void))sym; return sage_number((double)fn()); }
        if (call_argc == 1 && IS_NUM(call_argv[0])) { int (*fn)(int) = (int(*)(int))sym; return sage_number((double)fn((int)call_argv[0].as.number)); }
        if (call_argc == 1 && IS_STR(call_argv[0])) { int (*fn)(const char*) = (int(*)(const char*))sym; return sage_number((double)fn(call_argv[0].as.string)); }
        if (call_argc == 2 && IS_NUM(call_argv[0]) && IS_NUM(call_argv[1])) { int (*fn)(int,int) = (int(*)(int,int))sym; return sage_number((double)fn((int)call_argv[0].as.number,(int)call_argv[1].as.number)); }
        if (call_argc == 2 && IS_STR(call_argv[0]) && IS_NUM(call_argv[1])) { int (*fn)(const char*,int) = (int(*)(const char*,int))sym; return sage_number((double)fn(call_argv[0].as.string,(int)call_argv[1].as.number)); }
        if (call_argc == 2 && IS_NUM(call_argv[0]) && IS_STR(call_argv[1])) { int (*fn)(int,const char*) = (int(*)(int,const char*))sym; return sage_number((double)fn((int)call_argv[0].as.number,call_argv[1].as.string)); }
        if (call_argc == 3 && IS_NUM(call_argv[0]) && IS_NUM(call_argv[1]) && IS_NUM(call_argv[2])) { int (*fn)(int,int,int) = (int(*)(int,int,int))sym; return sage_number((double)fn((int)call_argv[0].as.number,(int)call_argv[1].as.number,(int)call_argv[2].as.number)); }
        if (call_argc == 3 && IS_NUM(call_argv[0]) && IS_STR(call_argv[1]) && IS_NUM(call_argv[2])) { int (*fn)(int,const char*,int) = (int(*)(int,const char*,int))sym; return sage_number((double)fn((int)call_argv[0].as.number,call_argv[1].as.string,(int)call_argv[2].as.number)); }
    }
    if (strcmp(rt, "void") == 0) {
        if (call_argc == 0) { void (*fn)(void) = (void(*)(void))sym; fn(); return sage_nil(); }
        if (call_argc == 1 && IS_NUM(call_argv[0])) { void (*fn)(int) = (void(*)(int))sym; fn((int)call_argv[0].as.number); return sage_nil(); }
        if (call_argc == 1 && IS_STR(call_argv[0])) { void (*fn)(const char*) = (void(*)(const char*))sym; fn(call_argv[0].as.string); return sage_nil(); }
        if (call_argc == 2 && IS_NUM(call_argv[0]) && IS_NUM(call_argv[1])) { void (*fn)(int,int) = (void(*)(int,int))sym; fn((int)call_argv[0].as.number,(int)call_argv[1].as.number); return sage_nil(); }
    }
    if (strcmp(rt, "double") == 0) {
        if (call_argc == 0) { double (*fn)(void) = (double(*)(void))sym; return sage_number(fn()); }
        if (call_argc == 1 && IS_NUM(call_argv[0])) { double (*fn)(double) = (double(*)(double))sym; return sage_number(fn(call_argv[0].as.number)); }
        if (call_argc == 2 && IS_NUM(call_argv[0]) && IS_NUM(call_argv[1])) { double (*fn)(double,double) = (double(*)(double,double))sym; return sage_number(fn(call_argv[0].as.number,call_argv[1].as.number)); }
        if (call_argc == 3 && IS_NUM(call_argv[0]) && IS_NUM(call_argv[1]) && IS_NUM(call_argv[2])) { double (*fn)(double,double,double) = (double(*)(double,double,double))sym; return sage_number(fn(call_argv[0].as.number,call_argv[1].as.number,call_argv[2].as.number)); }
    }
    if (strcmp(rt, "long") == 0) {
        if (call_argc == 0) { long (*fn)(void) = (long(*)(void))sym; return sage_number((double)fn()); }
        if (call_argc == 1 && IS_NUM(call_argv[0])) { long (*fn)(long) = (long(*)(long))sym; return sage_number((double)fn((long)call_argv[0].as.number)); }
        if (call_argc == 2 && IS_NUM(call_argv[0]) && IS_NUM(call_argv[1])) { long (*fn)(long,long) = (long(*)(long,long))sym; return sage_number((double)fn((long)call_argv[0].as.number,(long)call_argv[1].as.number)); }
    }
    if (strcmp(rt, "string") == 0) {
        if (call_argc == 0) { const char* (*fn)(void) = (const char*(*)(void))sym; const char* r = fn(); return r ? sage_string(r) : sage_nil(); }
        if (call_argc == 1 && IS_STR(call_argv[0])) { const char* (*fn)(const char*) = (const char*(*)(const char*))sym; const char* r = fn(call_argv[0].as.string); return r ? sage_string(r) : sage_nil(); }
        if (call_argc == 1 && IS_NUM(call_argv[0])) { const char* (*fn)(int) = (const char*(*)(int))sym; const char* r = fn((int)call_argv[0].as.number); return r ? sage_string(r) : sage_nil(); }
    }
    #pragma GCC diagnostic pop
    #undef IS_NUM
    #undef IS_STR
    return sage_nil();
}
static SageValue sage_ffi_call_full(SageValue h, SageValue n, SageValue r, SageValue a) { return sage_ffi_call(h,n,r,a); }

static SageValue sage_atomic_new(SageValue val) {
    SageValue* atom = malloc(sizeof(SageValue));
    *atom = val;
    SageValue v; v.type = SAGE_TAG_POINTER; v.as.pointer = atom; return v;
}
static SageValue sage_atomic_load(SageValue atom) {
    if (atom.type != SAGE_TAG_POINTER) return sage_nil();
    return *(SageValue*)atom.as.pointer;
}
static SageValue sage_atomic_store(SageValue atom, SageValue val) {
    if (atom.type != SAGE_TAG_POINTER) return sage_nil();
    *(SageValue*)atom.as.pointer = val;
    return val;
}
static SageValue sage_atomic_add(SageValue atom, SageValue val) { return sage_nil(); }
static SageValue sage_atomic_cas(SageValue atom, SageValue old, SageValue new_val) { return sage_nil(); }
static SageValue sage_atomic_exchange(SageValue atom, SageValue val) { return sage_nil(); }

static SageValue sage_sem_new(SageValue val) {
    sem_t* sem = malloc(sizeof(sem_t));
    sem_init(sem, 0, (unsigned int)val.as.number);
    SageValue v; v.type = SAGE_TAG_POINTER; v.as.pointer = sem; return v;
}
static SageValue sage_sem_wait(SageValue sem) {
    if (sem.type != SAGE_TAG_POINTER) return sage_nil();
    sem_wait((sem_t*)sem.as.pointer);
    return sage_nil();
}
static SageValue sage_sem_post(SageValue sem) {
    if (sem.type != SAGE_TAG_POINTER) return sage_nil();
    sem_post((sem_t*)sem.as.pointer);
    return sage_nil();
}
static SageValue sage_sem_trywait(SageValue sem) {
    if (sem.type != SAGE_TAG_POINTER) return sage_bool(0);
    return sage_bool(sem_trywait((sem_t*)sem.as.pointer) == 0);
}
static SageSlot sage_slot_undefined(void) { SageSlot slot; slot.defined = 0; slot.value = sage_nil(); return slot; }

static SageValue sage_make_dict(void) {
    SageDict* dict = (SageDict*)sage_gc_alloc(SAGE_GC_DICT, sizeof(SageDict));
    dict->keys = NULL;
    dict->values = NULL;
    dict->count = 0;
    dict->capacity = 0;
    SageValue v; v.type = SAGE_TAG_DICT; v.as.dict = dict;
    return v;
}

static void sage_dict_set(SageDict* dict, const char* key, SageValue value) {
    for (int i = 0; i < dict->count; i++) {
        if (strcmp(dict->keys[i], key) == 0) {
            dict->values[i] = value;
            return;
        }
    }
    if (dict->count >= dict->capacity) {
        int cap = dict->capacity == 0 ? 4 : dict->capacity * 2;
        dict->keys = (char**)realloc(dict->keys, sizeof(char*) * (size_t)cap);
        dict->values = (SageValue*)realloc(dict->values, sizeof(SageValue) * (size_t)cap);
        if (dict->keys == NULL || dict->values == NULL) sage_fail("Runtime Error: out of memory");
        dict->capacity = cap;
    }
    dict->keys[dict->count] = sage_dup_string(key);
    dict->values[dict->count] = value;
    dict->count++;
}

static SageValue sage_make_dict_from_entries(int count, const char** keys, const SageValue* values) {
    sage_gc_pin();
    SageValue dict = sage_make_dict();
    for (int i = 0; i < count; i++) {
        sage_dict_set(dict.as.dict, keys[i], values[i]);
    }
    sage_gc_unpin();
    return dict;
}

static SageValue sage_dict_get(SageDict* dict, const char* key) {
    for (int i = 0; i < dict->count; i++) {
        if (strcmp(dict->keys[i], key) == 0) return dict->values[i];
    }
    return sage_nil();
}

static SageValue sage_make_tuple(int count, const SageValue* values) {
    sage_gc_pin();
    SageTuple* tuple = (SageTuple*)sage_gc_alloc(SAGE_GC_TUPLE, sizeof(SageTuple));
    tuple->count = count;
    tuple->elements = (SageValue*)malloc(sizeof(SageValue) * (size_t)count);
    if (tuple->elements == NULL && count > 0) sage_fail("Runtime Error: out of memory");
    for (int i = 0; i < count; i++) tuple->elements[i] = values[i];
    SageValue v; v.type = SAGE_TAG_TUPLE; v.as.tuple = tuple;
    sage_gc_unpin();
    return v;
}

static void sage_raise(SageValue value) {
    if (sage_try_depth > 0) {
        sage_exception_value = value;
        longjmp(sage_try_stack[sage_try_depth - 1], 1);
    }
    fputs("Unhandled exception: ", stderr);
    if (value.type == SAGE_TAG_STRING) fputs(value.as.string, stderr);
    else fputs("(unknown)", stderr);
    fputc('\n', stderr);
    exit(1);
}

static void sage_array_reserve(SageArray* array, int needed) {
    if (array->capacity >= needed) return;
    int capacity = array->capacity == 0 ? 4 : array->capacity;
    while (capacity < needed) capacity *= 2;
    SageValue* elements = (SageValue*)realloc(array->elements, sizeof(SageValue) * (size_t)capacity);
    if (elements == NULL) sage_fail("Runtime Error: out of memory");
    array->elements = elements;
    array->capacity = capacity;
}

static void sage_array_push_raw(SageArray* array, SageValue value) {
    sage_array_reserve(array, array->count + 1);
    array->elements[array->count++] = value;
}

static SageValue sage_make_array(int count, const SageValue* values) {
    sage_gc_pin();
    SageValue array = sage_array();
    for (int i = 0; i < count; i++) {
        sage_array_push_raw(array.as.array, values[i]);
    }
    sage_gc_unpin();
    return array;
}

static int sage_truthy(SageValue value) {
    if (value.type == SAGE_TAG_NIL) return 0;
    if (value.type == SAGE_TAG_BOOL) return value.as.boolean;
    if (value.type == SAGE_TAG_NUMBER) return value.as.number != 0.0;
    if (value.type == SAGE_TAG_STRING) return value.as.string[0] != '\0';
    return 1;
}

static SageValue sage_load_slot(const SageSlot* slot, const char* name) {
    if (!slot->defined) {
        fprintf(stderr, "Runtime Error: Undefined variable '%s'.\n", name);
        exit(1);
    }
    return slot->value;
}

static void sage_define_slot(SageSlot* slot, SageValue value) {
    slot->defined = 1;
    slot->value = value;
}

static SageValue sage_assign_slot(SageSlot* slot, const char* name, SageValue value) {
    if (!slot->defined) {
        fprintf(stderr, "Runtime Error: Undefined variable '%s'.\n", name);
        exit(1);
    }
    slot->value = value;
    return value;
}

static int sage_values_equal(SageValue left, SageValue right) {
    if (left.type != right.type) return 0;
    switch (left.type) {
        case SAGE_TAG_NIL: return 1;
        case SAGE_TAG_NUMBER: return left.as.number == right.as.number;
        case SAGE_TAG_BOOL: return left.as.boolean == right.as.boolean;
        case SAGE_TAG_STRING: return strcmp(left.as.string, right.as.string) == 0;
        case SAGE_TAG_ARRAY: {
            if (left.as.array == right.as.array) return 1;
            if (left.as.array->count != right.as.array->count) return 0;
            for (int i = 0; i < left.as.array->count; i++) {
                if (!sage_values_equal(left.as.array->elements[i], right.as.array->elements[i])) return 0;
            }
            return 1;
        }
        case SAGE_TAG_DICT: return left.as.dict == right.as.dict;
        case SAGE_TAG_TUPLE: {
            if (left.as.tuple == right.as.tuple) return 1;
            if (left.as.tuple->count != right.as.tuple->count) return 0;
            for (int i = 0; i < left.as.tuple->count; i++) {
                if (!sage_values_equal(left.as.tuple->elements[i], right.as.tuple->elements[i])) return 0;
            }
            return 1;
        }
    }
    return 0;
}

static void sage_print_value(SageValue value) {
    switch (value.type) {
        case SAGE_TAG_NUMBER: {
            double d = value.as.number;
            if (d == (double)(long long)d && d >= -1e15 && d <= 1e15)
                printf("%lld", (long long)d);
            else
                printf("%g", d);
            break;
        }
        case SAGE_TAG_BOOL: fputs(value.as.boolean ? "true" : "false", stdout); break;
        case SAGE_TAG_STRING: fputs(value.as.string, stdout); break;
        case SAGE_TAG_ARRAY:
            fputc('[', stdout);
            for (int i = 0; i < value.as.array->count; i++) {
                if (i > 0) fputs(", ", stdout);
                sage_print_value(value.as.array->elements[i]);
            }
            fputc(']', stdout);
            break;
        case SAGE_TAG_DICT:
            fputc('{', stdout);
            for (int i = 0; i < value.as.dict->count; i++) {
                if (i > 0) fputs(", ", stdout);
                printf("\"%s\": ", value.as.dict->keys[i]);
                sage_print_value(value.as.dict->values[i]);
            }
            fputc('}', stdout);
            break;
        case SAGE_TAG_TUPLE:
            fputc('(', stdout);
            for (int i = 0; i < value.as.tuple->count; i++) {
                if (i > 0) fputs(", ", stdout);
                sage_print_value(value.as.tuple->elements[i]);
            }
            fputc(')', stdout);
            break;
        case SAGE_TAG_NIL: fputs("nil", stdout); break;
    }
}

static void sage_print_ln(SageValue value) {
    sage_print_value(value);
    fputc('\n', stdout);
}

static SageValue sage_str(SageValue value) {
    char buffer[64];
    switch (value.type) {
        case SAGE_TAG_STRING: return value;
        case SAGE_TAG_NUMBER: {
            double d = value.as.number;
            if (d == (double)(long long)d && d >= -1e15 && d <= 1e15)
                snprintf(buffer, sizeof(buffer), "%lld", (long long)d);
            else
                snprintf(buffer, sizeof(buffer), "%g", d);
            return sage_string(buffer);
        }
        case SAGE_TAG_BOOL:
            return sage_string(value.as.boolean ? "true" : "false");
        case SAGE_TAG_NIL:
            return sage_string("nil");
        case SAGE_TAG_ARRAY:
            return sage_string("<array>");
        case SAGE_TAG_DICT:
            return sage_string("<dict>");
        case SAGE_TAG_TUPLE:
            return sage_string("<tuple>");
    }
    return sage_string("nil");
}

static SageValue sage_int(SageValue value) {
    if (value.type == SAGE_TAG_NUMBER) return sage_number((double)(long long)value.as.number);
    if (value.type == SAGE_TAG_STRING) return sage_number((double)atof(value.as.string));
    if (value.type == SAGE_TAG_BOOL) return sage_number((double)value.as.boolean);
    return sage_number(0);
}

static SageValue sage_abs(SageValue value) {
    if (value.type == SAGE_TAG_NUMBER) return sage_number(fabs(value.as.number));
    return sage_nil();
}
static SageValue sage_sqrt(SageValue value) {
    if (value.type == SAGE_TAG_NUMBER) return sage_number(sqrt(value.as.number));
    return sage_nil();
}

static SageValue sage_native_random(void) { return sage_number((double)rand() / (double)RAND_MAX); }
static SageValue sage_native_srandom(SageValue seed) { srand((unsigned int)seed.as.number); return sage_nil(); }
static SageValue sage_native_sin(SageValue v) { return sage_number(sin(v.as.number)); }
static SageValue sage_native_cos(SageValue v) { return sage_number(cos(v.as.number)); }
static SageValue sage_native_tan(SageValue v) { return sage_number(tan(v.as.number)); }
static SageValue sage_native_floor(SageValue v) { return sage_number(floor(v.as.number)); }
static SageValue sage_native_ceil(SageValue v) { return sage_number(ceil(v.as.number)); }
static SageValue sage_native_pow(SageValue a, SageValue b) { return sage_number(pow(a.as.number, b.as.number)); }
static SageValue sage_native_exp(SageValue v) { return sage_number(exp(v.as.number)); }
static SageValue sage_native_log(SageValue v) { return sage_number(log(v.as.number)); }
static SageValue sage_native_sqrt(SageValue v) { return sage_number(sqrt(v.as.number)); }

static SageValue sage_native_thread_mutex(void) {
    pthread_mutex_t* m = malloc(sizeof(pthread_mutex_t));
    pthread_mutex_init(m, NULL);
    SageValue v; v.type = SAGE_TAG_MUTEX; v.as.mutex = m; return v;
}
static SageValue sage_native_thread_lock(SageValue m) {
    if (m.type == SAGE_TAG_MUTEX) pthread_mutex_lock((pthread_mutex_t*)m.as.mutex);
    return sage_nil();
}
static SageValue sage_native_thread_unlock(SageValue m) {
    if (m.type == SAGE_TAG_MUTEX) pthread_mutex_unlock((pthread_mutex_t*)m.as.mutex);
    return sage_nil();
}
static void* sage_thread_wrapper(void* arg) {
    (void)arg;
    return NULL;
}
static SageValue sage_native_thread_spawn(SageValue fn, SageValue arg) {
    pthread_t* t = malloc(sizeof(pthread_t));
    (void)fn; (void)arg;
    pthread_create(t, NULL, sage_thread_wrapper, NULL);
    SageValue v; v.type = SAGE_TAG_THREAD; v.as.thread = t; return v;
}
static SageValue sage_native_thread_sleep(SageValue ms) {
    struct timespec ts;
    ts.tv_sec = (time_t)(ms.as.number / 1000);
    ts.tv_nsec = (long)((ms.as.number - (double)(ts.tv_sec * 1000)) * 1000000);
    nanosleep(&ts, NULL);
    return sage_nil();
}
static SageValue sage_native_thread_id(void) { return sage_number((double)(uintptr_t)pthread_self()); }

static SageValue sage_native_io_readbytes(SageValue path) {
    if (path.type != SAGE_TAG_STRING) return sage_nil();
    FILE* f = fopen(path.as.string, "rb");
    if (!f) return sage_nil();
    if (fseek(f, 0, SEEK_END) == 0) {
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (size < 0 || size > SAGE_MAX_READ_SIZE) { fclose(f); return sage_nil(); }
        unsigned char* data = (unsigned char*)malloc((size_t)size);
        if (!data) { fclose(f); return sage_nil(); }
        if (size > 0 && fread(data, 1, (size_t)size, f) != (size_t)size) { free(data); fclose(f); return sage_nil(); }
        fclose(f);
        SageBytes* bytes = (SageBytes*)malloc(sizeof(SageBytes));
        if (!bytes) { free(data); return sage_nil(); }
        bytes->data = data; bytes->count = (int)size;
        SageValue v; v.type = SAGE_TAG_BYTES; v.as.bytes = bytes; return v;
    }
    // Non-seekable file (e.g., /dev/urandom) — read in chunks until EOF
    sage_gc_pin();
    SageValue arr = sage_array();
    unsigned char chunk[4096];
    size_t nread;
    size_t total_read = 0;
    while ((nread = fread(chunk, 1, sizeof(chunk), f)) > 0) {
        if (total_read + nread > SAGE_MAX_READ_SIZE) nread = SAGE_MAX_READ_SIZE - total_read;
        for (size_t i = 0; i < nread; i++) {
            sage_array_push_raw(arr.as.array, sage_number((double)chunk[i]));
        }
        total_read += nread;
        if (total_read >= SAGE_MAX_READ_SIZE) break;
    }
    fclose(f);
    sage_gc_unpin();
    return arr;
}
static SageValue sage_native_io_writebytes(SageValue path, SageValue v) {
    if (path.type != SAGE_TAG_STRING) return sage_nil();
    FILE* f = fopen(path.as.string, "wb");
    if (!f) return sage_nil();
    if (v.type == SAGE_TAG_BYTES) {
        if (v.as.bytes->count > 0) fwrite(v.as.bytes->data, 1, v.as.bytes->count, f);
        fclose(f);
        return sage_bool(1);
    }
    if (v.type != SAGE_TAG_ARRAY) { fclose(f); return sage_nil(); }
    SageArray* a = v.as.array;
    unsigned char chunk[4096];
    int pos = 0;
    for (int i = 0; i < a->count; i++) {
        chunk[pos++] = (unsigned char)a->elements[i].as.number;
        if (pos == sizeof(chunk)) {
            fwrite(chunk, 1, sizeof(chunk), f);
            pos = 0;
        }
    }
    if (pos > 0) fwrite(chunk, 1, pos, f);
    fclose(f);
    return sage_bool(1);
}
static SageValue sage_native_io_appendbytes(SageValue path, SageValue v) {
    if (path.type != SAGE_TAG_STRING) return sage_nil();
    FILE* f = fopen(path.as.string, "ab");
    if (!f) return sage_nil();
    if (v.type == SAGE_TAG_BYTES) {
        if (v.as.bytes->count > 0) fwrite(v.as.bytes->data, 1, v.as.bytes->count, f);
        fclose(f);
        return sage_bool(1);
    }
    if (v.type != SAGE_TAG_ARRAY) { fclose(f); return sage_nil(); }
    SageArray* a = v.as.array;
    unsigned char chunk[4096];
    int pos = 0;
    for (int i = 0; i < a->count; i++) {
        chunk[pos++] = (unsigned char)a->elements[i].as.number;
        if (pos == sizeof(chunk)) {
            fwrite(chunk, 1, sizeof(chunk), f);
            pos = 0;
        }
    }
    if (pos > 0) fwrite(chunk, 1, pos, f);
    fclose(f);
    return sage_bool(1);
}
static SageValue sage_native_io_readfile(SageValue path) { return sage_native_io_readbytes(path); }
static SageValue sage_native_io_writefile(SageValue path, SageValue data) {
    if (path.type != SAGE_TAG_STRING || data.type != SAGE_TAG_STRING) return sage_nil();
    FILE* f = fopen(path.as.string, "wb");
    if (!f) return sage_nil();
    fwrite(data.as.string, 1, strlen(data.as.string), f);
    fclose(f);
    return sage_bool(1);
}

extern int sage_argc;
extern char** sage_argv;
static SageValue sage_native_sys_args(void) {
    SageValue arr = sage_array();
    for (int i = 0; i < sage_argc; i++) {
        sage_array_push_raw(arr.as.array, sage_string(sage_argv[i]));
    }
    return arr;
}
static SageValue sage_native_sys_getenv(SageValue name) {
    if (name.type != SAGE_TAG_STRING) return sage_nil();
    char* val = getenv(name.as.string);
    return val ? sage_string(val) : sage_nil();
}
static SageValue sage_native_sys_clock(void) { return sage_number((double)clock() / CLOCKS_PER_SEC); }

static SageValue sage_init_native_module(const char* name) {
    /* For now, just return an empty dict; real native modules should be linked */
    return sage_make_dict();
}

static SageValue sage_len(SageValue value) {
    if (value.type == SAGE_TAG_STRING) return sage_number((double)SAGE_STRING_LEN(value));
    if (value.type == SAGE_TAG_ARRAY) return sage_number((double)value.as.array->count);
    if (value.type == SAGE_TAG_DICT) return sage_number((double)value.as.dict->count);
    if (value.type == SAGE_TAG_TUPLE) return sage_number((double)value.as.tuple->count);
    if (value.type == SAGE_TAG_BYTES) return sage_number((double)value.as.bytes->count);
    return sage_nil();
}

static SageValue sage_index(SageValue collection, SageValue index) {
    if (collection.type == SAGE_TAG_ARRAY && index.type == SAGE_TAG_NUMBER) {
        int idx = (int)index.as.number;
        if (idx < 0 || idx >= collection.as.array->count) return sage_nil();
        return collection.as.array->elements[idx];
    }
    if (collection.type == SAGE_TAG_BYTES && index.type == SAGE_TAG_NUMBER) {
        int idx = (int)index.as.number;
        if (idx < 0 || idx >= collection.as.bytes->count) return sage_nil();
        return sage_number((double)collection.as.bytes->data[idx]);
    }
    if (collection.type == SAGE_TAG_DICT && index.type == SAGE_TAG_STRING) {
        return sage_dict_get(collection.as.dict, index.as.string);
    }
    if (collection.type == SAGE_TAG_TUPLE && index.type == SAGE_TAG_NUMBER) {
        int idx = (int)index.as.number;
        if (idx < 0 || idx >= collection.as.tuple->count) return sage_nil();
        return collection.as.tuple->elements[idx];
    }
    if (collection.type == SAGE_TAG_STRING && index.type == SAGE_TAG_NUMBER) {
        int idx = (int)index.as.number;
        int len = SAGE_STRING_LEN(collection);
        if (idx < 0 || idx >= len) return sage_nil();
        char buf[2] = {collection.as.string[idx], '\0'};
        return sage_string(buf);
    }
    return sage_nil();
}

static SageValue sage_slice(SageValue array, SageValue start, SageValue end) {
    if (array.type != SAGE_TAG_ARRAY && array.type != SAGE_TAG_STRING) return sage_nil();
    sage_gc_pin();
    int len = array.type == SAGE_TAG_ARRAY ? array.as.array->count : SAGE_STRING_LEN(array);
    int start_index = 0;
    int end_index = len;
    if (start.type == SAGE_TAG_NUMBER) start_index = (int)start.as.number;
    else if (start.type != SAGE_TAG_NIL) { sage_gc_unpin(); return sage_nil(); }
    if (end.type == SAGE_TAG_NUMBER) end_index = (int)end.as.number;
    else if (end.type != SAGE_TAG_NIL) { sage_gc_unpin(); return sage_nil(); }
    if (start_index < 0) start_index = len + start_index;
    if (end_index < 0) end_index = len + end_index;
    if (start_index < 0) start_index = 0;
    if (end_index > len) end_index = len;
    if (start_index >= end_index) {
        SageValue empty = array.type == SAGE_TAG_ARRAY ? sage_array() : sage_string("");
        sage_gc_unpin(); return empty;
    }
    if (array.type == SAGE_TAG_ARRAY) {
        SageValue result = sage_array();
        for (int i = start_index; i < end_index; i++) {
            sage_array_push_raw(result.as.array, array.as.array->elements[i]);
        }
        sage_gc_unpin();
        return result;
    } else {
        int new_len = end_index - start_index;
        char* buf = malloc(new_len + 1);
        if (buf == NULL) sage_fail("Runtime Error: out of memory");
        memcpy(buf, array.as.string + start_index, new_len);
        buf[new_len] = '\0';
        SageValue result = sage_string_take(buf);
        sage_gc_unpin();
        return result;
    }
}

static SageValue sage_push(SageValue array, SageValue value) {
    if (array.type != SAGE_TAG_ARRAY) return sage_nil();
    sage_array_push_raw(array.as.array, value);
    return sage_nil();
}

static SageValue sage_pop(SageValue array) {
    if (array.type != SAGE_TAG_ARRAY || array.as.array->count == 0) return sage_nil();
    return array.as.array->elements[--array.as.array->count];
}

static SageValue sage_array_extend(SageValue target, SageValue source) {
    if (target.type != SAGE_TAG_ARRAY || source.type != SAGE_TAG_ARRAY) return sage_nil();
    SageArray* dst = target.as.array;
    SageArray* src = source.as.array;
    if (src->count > 0) {
        sage_array_reserve(dst, dst->count + src->count);
        memcpy(dst->elements + dst->count, src->elements, sizeof(SageValue) * (size_t)src->count);
        dst->count += src->count;
    }
    return sage_nil();
}

static SageValue sage_array_reverse(SageValue array) {
    if (array.type != SAGE_TAG_ARRAY) return sage_nil();
    SageArray* src = array.as.array;
    sage_gc_pin();
    SageValue result = sage_array();
    if (src->count > 0) {
        SageArray* dst = result.as.array;
        sage_array_reserve(dst, src->count);
        dst->count = src->count;
        for (int i = 0; i < src->count; i++) {
            dst->elements[i] = src->elements[src->count - 1 - i];
        }
    }
    sage_gc_unpin();
    return result;
}

static SageValue sage_range2(SageValue start, SageValue end) {
    if (start.type != SAGE_TAG_NUMBER || end.type != SAGE_TAG_NUMBER) return sage_nil();
    sage_gc_pin();
    SageValue result = sage_array();
    for (int i = (int)start.as.number; i < (int)end.as.number; i++) {
        sage_array_push_raw(result.as.array, sage_number((double)i));
    }
    sage_gc_unpin();
    return result;
}
static SageValue sage_range3(SageValue start, SageValue end, SageValue step) {
    if (start.type != SAGE_TAG_NUMBER || end.type != SAGE_TAG_NUMBER || step.type != SAGE_TAG_NUMBER) return sage_nil();
    int s = (int)start.as.number, e = (int)end.as.number, st = (int)step.as.number;
    if (st == 0) return sage_nil();
    sage_gc_pin();
    SageValue result = sage_array();
    if (st > 0) {
        for (int i = s; i < e; i += st) {
            sage_array_push_raw(result.as.array, sage_number((double)i));
        }
    } else {
        for (int i = s; i > e; i += st) {
            sage_array_push_raw(result.as.array, sage_number((double)i));
        }
    }
    sage_gc_unpin();
    return result;
}

static SageValue sage_range1(SageValue end) {
    return sage_range2(sage_number(0), end);
}

static SageValue sage_add(SageValue left, SageValue right);
static SageValue sage_sub(SageValue left, SageValue right);
static SageValue sage_mul(SageValue left, SageValue right);
static SageValue sage_div(SageValue left, SageValue right);
static SageValue sage_eq(SageValue left, SageValue right);
static SageValue sage_neq(SageValue left, SageValue right);
static SageValue sage_gt(SageValue left, SageValue right);
static SageValue sage_lt(SageValue left, SageValue right);
static SageValue sage_gte(SageValue left, SageValue right);
static SageValue sage_lte(SageValue left, SageValue right);

static inline SageValue SAGE_ADD(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_number(a.as.number + b.as.number);
    return sage_add(a, b);
}
static inline SageValue SAGE_SUB(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_number(a.as.number - b.as.number);
    return sage_sub(a, b);
}
static inline SageValue SAGE_MUL(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_number(a.as.number * b.as.number);
    return sage_mul(a, b);
}
static inline SageValue SAGE_DIV(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER && b.as.number != 0.0) return sage_number(a.as.number / b.as.number);
    return sage_div(a, b);
}
static inline SageValue SAGE_EQ(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_bool(a.as.number == b.as.number);
    return sage_eq(a, b);
}
static inline SageValue SAGE_NEQ(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_bool(a.as.number != b.as.number);
    return sage_neq(a, b);
}
static inline SageValue SAGE_GT(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_bool(a.as.number > b.as.number);
    return sage_gt(a, b);
}
static inline SageValue SAGE_LT(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_bool(a.as.number < b.as.number);
    return sage_lt(a, b);
}
static inline SageValue SAGE_GTE(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_bool(a.as.number >= b.as.number);
    return sage_gte(a, b);
}
static inline SageValue SAGE_LTE(SageValue a, SageValue b) {
    if (a.type == SAGE_TAG_NUMBER && b.type == SAGE_TAG_NUMBER) return sage_bool(a.as.number <= b.as.number);
    return sage_lte(a, b);
}

static SageValue sage_add(SageValue left, SageValue right) {
    if (left.type == SAGE_TAG_NUMBER && right.type == SAGE_TAG_NUMBER) {
        return sage_number(left.as.number + right.as.number);
    }
    if (left.type == SAGE_TAG_STRING && right.type == SAGE_TAG_STRING) {
        size_t len1 = SAGE_STRING_LEN(left);
        size_t len2 = SAGE_STRING_LEN(right);
        char* result = (char*)malloc(len1 + len2 + 1);
        if (result == NULL) sage_fail("Runtime Error: out of memory");
        memcpy(result, left.as.string, len1);
        memcpy(result + len1, right.as.string, len2 + 1);
        return sage_string_take(result);
    }
    if (left.type == SAGE_TAG_ARRAY && right.type == SAGE_TAG_ARRAY) {
        int total = left.as.array->count + right.as.array->count;
        SageValue result = sage_array();
        result.as.array->count = total;
        result.as.array->capacity = total;
        result.as.array->elements = (SageValue*)malloc(sizeof(SageValue) * total);
        if (result.as.array->elements == NULL) sage_fail("Runtime Error: out of memory");
        memcpy(result.as.array->elements, left.as.array->elements, sizeof(SageValue) * left.as.array->count);
        memcpy(result.as.array->elements + left.as.array->count, right.as.array->elements, sizeof(SageValue) * right.as.array->count);
        return result;
    }
    sage_fail("Runtime Error: Operands must be numbers, strings, or arrays.");
    return sage_nil();
}

static SageValue sage_sub(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number(left.as.number - right.as.number);
}
static SageValue sage_mul(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number(left.as.number * right.as.number);
}
static SageValue sage_div(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    if (right.as.number == 0) return sage_nil();
    return sage_number(left.as.number / right.as.number);
}
static SageValue sage_mod(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    if (right.as.number == 0) return sage_nil();
    return sage_number(fmod(left.as.number, right.as.number));
}
static SageValue sage_eq(SageValue left, SageValue right) { return sage_bool(sage_values_equal(left, right)); }
static SageValue sage_neq(SageValue left, SageValue right) { return sage_bool(!sage_values_equal(left, right)); }
static SageValue sage_gt(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_bool(left.as.number > right.as.number);
}
static SageValue sage_lt(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_bool(left.as.number < right.as.number);
}
static SageValue sage_gte(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_bool(left.as.number >= right.as.number);
}
static SageValue sage_lte(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_bool(left.as.number <= right.as.number);
}
static SageValue sage_not(SageValue value) { return sage_bool(!sage_truthy(value)); }
static SageValue sage_and(SageValue left, SageValue right) { return sage_bool(sage_truthy(left) && sage_truthy(right)); }
static SageValue sage_or(SageValue left, SageValue right) { return sage_bool(sage_truthy(left) || sage_truthy(right)); }
static SageValue sage_bit_not(SageValue value) {
    if (value.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Bitwise NOT operand must be a number.");
    return sage_number((double)(~(long long)value.as.number));
}
static SageValue sage_bit_and(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number((double)(((long long)left.as.number) & ((long long)right.as.number)));
}
static SageValue sage_bit_or(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number((double)(((long long)left.as.number) | ((long long)right.as.number)));
}
static SageValue sage_bit_xor(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number((double)(((long long)left.as.number) ^ ((long long)right.as.number)));
}
static SageValue sage_lshift(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number((double)(((unsigned long long)left.as.number) << ((long long)right.as.number)));
}
static SageValue sage_rshift(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number((double)(((unsigned long long)left.as.number) >> ((long long)right.as.number)));
}

static SageValue sage_tonumber(SageValue value) {
    if (value.type == SAGE_TAG_NUMBER) return value;
    if (value.type == SAGE_TAG_STRING) {
        char* end;
        double result = strtod(value.as.string, &end);
        if (end != value.as.string && *end == '\0') return sage_number(result);
    }
    return sage_nil();
}

static SageValue sage_dict_keys_fn(SageValue dict_val) {
    if (dict_val.type != SAGE_TAG_DICT) return sage_array();
    sage_gc_pin();
    SageValue result = sage_array();
    for (int i = 0; i < dict_val.as.dict->count; i++) {
        sage_array_push_raw(result.as.array, sage_string(dict_val.as.dict->keys[i]));
    }
    sage_gc_unpin();
    return result;
}

static SageValue sage_dict_values_fn(SageValue dict_val) {
    if (dict_val.type != SAGE_TAG_DICT) return sage_array();
    sage_gc_pin();
    SageValue result = sage_array();
    for (int i = 0; i < dict_val.as.dict->count; i++) {
        sage_array_push_raw(result.as.array, dict_val.as.dict->values[i]);
    }
    sage_gc_unpin();
    return result;
}

static SageValue sage_dict_has_fn(SageValue dict_val, SageValue key) {
    if (dict_val.type != SAGE_TAG_DICT || key.type != SAGE_TAG_STRING) return sage_bool(0);
    for (int i = 0; i < dict_val.as.dict->count; i++) {
        if (strcmp(dict_val.as.dict->keys[i], key.as.string) == 0) return sage_bool(1);
    }
    return sage_bool(0);
}

static SageValue sage_dict_delete_fn(SageValue dict_val, SageValue key) {
    if (dict_val.type != SAGE_TAG_DICT || key.type != SAGE_TAG_STRING) return sage_nil();
    SageDict* dict = dict_val.as.dict;
    for (int i = 0; i < dict->count; i++) {
        if (strcmp(dict->keys[i], key.as.string) == 0) {
            free(dict->keys[i]);
            for (int j = i; j < dict->count - 1; j++) {
                dict->keys[j] = dict->keys[j + 1];
                dict->values[j] = dict->values[j + 1];
            }
            dict->count--;
            return sage_bool(1);
        }
    }
    return sage_bool(0);
}

static SageValue sage_chr(SageValue v) {
    if (v.type != SAGE_TAG_NUMBER) return sage_nil();
    char buf[2] = { (char)(int)v.as.number, 0 };
    return sage_string(buf);
}

static SageValue sage_ord(SageValue v) {
    if (v.type != SAGE_TAG_STRING || v.as.string == NULL || v.as.string[0] == 0) return sage_nil();
    return sage_number((double)(unsigned char)v.as.string[0]);
}

static SageValue sage_type(SageValue v) {
    switch (v.type) {
        case SAGE_TAG_NIL: return sage_string("nil");
        case SAGE_TAG_NUMBER: return sage_string("number");
        case SAGE_TAG_BOOL: return sage_string("bool");
        case SAGE_TAG_STRING: return sage_string("string");
        case SAGE_TAG_ARRAY: return sage_string("array");
        case SAGE_TAG_DICT: return sage_string("dict");
        default: return sage_string("unknown");
    }
}

static SageValue sage_startswith(SageValue s, SageValue prefix) {
    if (s.type != SAGE_TAG_STRING || prefix.type != SAGE_TAG_STRING) return sage_bool(0);
    return sage_bool(strncmp(s.as.string, prefix.as.string, SAGE_STRING_LEN(prefix)) == 0);
}

static SageValue sage_endswith(SageValue s, SageValue suffix) {
    if (s.type != SAGE_TAG_STRING || suffix.type != SAGE_TAG_STRING) return sage_bool(0);
    size_t slen = SAGE_STRING_LEN(s), suflen = SAGE_STRING_LEN(suffix);
    if (suflen > slen) return sage_bool(0);
    return sage_bool(strcmp(s.as.string + slen - suflen, suffix.as.string) == 0);
}

static SageValue sage_contains(SageValue haystack, SageValue needle) {
    if (haystack.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_bool(0);
    return sage_bool(strstr(haystack.as.string, needle.as.string) != NULL);
}

static SageValue sage_indexof(SageValue haystack, SageValue needle) {
    if (haystack.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_nil();
    char* found = strstr(haystack.as.string, needle.as.string);
    if (found == NULL) return sage_number(-1);
    return sage_number((double)(found - haystack.as.string));
}

static SageValue sage_string_count(SageValue haystack, SageValue needle) {
    if (haystack.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_nil();
    if (SAGE_STRING_LEN(needle) == 0) return sage_number(0);
    size_t count = 0;
    const char* pos = haystack.as.string;
    while ((pos = strstr(pos, needle.as.string)) != NULL) {
        count++;
        pos += SAGE_STRING_LEN(needle);
    }
    return sage_number((double)count);
}

static SageValue sage_string_repeat(SageValue s, SageValue count) {
    if (s.type != SAGE_TAG_STRING || count.type != SAGE_TAG_NUMBER) return sage_nil();
    int n = (int)count.as.number;
    if (n <= 0) return sage_string("");
    size_t slen = SAGE_STRING_LEN(s);
    char* buf = malloc(slen * n + 1);
    if (!buf) return sage_nil();
    for (int i = 0; i < n; i++) memcpy(buf + i * slen, s.as.string, slen);
    buf[slen * n] = '\0';
    SageValue result = sage_string_take(buf);
    return result;
}

static void sage_index_set(SageValue c, SageValue k, SageValue v) {
    if (c.type == SAGE_TAG_ARRAY && k.type == SAGE_TAG_NUMBER) {
        int i = (int)k.as.number;
        if (i >= 0 && i < c.as.array->count) c.as.array->elements[i] = v;
        return;
    }
    if (c.type == SAGE_TAG_DICT && k.type == SAGE_TAG_STRING) {
        SageDict* d = c.as.dict;
        for (int i = 0; i < d->count; i++) {
            if (strcmp(d->keys[i], k.as.string) == 0) { d->values[i] = v; return; }
        }
        if (d->count >= d->capacity) {
            int nc = d->capacity == 0 ? 4 : d->capacity * 2;
            d->keys = realloc(d->keys, sizeof(char*) * nc);
            d->values = realloc(d->values, sizeof(SageValue) * nc);
            d->capacity = nc;
        }
        { size_t l = SAGE_STRING_LEN(k); d->keys[d->count] = malloc(l+1); memcpy(d->keys[d->count], k.as.string, l+1); }
        d->values[d->count] = v;
        d->count++;
    }
}

static SageValue sage_gc_collect_fn(void) {
    sage_gc_collect();
    return sage_nil();
}

static SageValue sage_gc_enable_fn(void) {
    sage_gc.enabled = 1;
    return sage_nil();
}

static SageValue sage_gc_disable_fn(void) {
    sage_gc.enabled = 0;
    return sage_nil();
}

static SageValue sage_gc_stats_fn(void) {
    int next_gc = sage_gc.next_gc_objects - sage_gc.object_count;
    if (next_gc < 0) next_gc = 0;
    return sage_make_dict_from_entries(7,
        (const char*[]){"bytes_allocated", "current_bytes", "num_objects", "collections", "objects_freed", "next_gc", "next_gc_bytes"},
        (SageValue[]){
            sage_number((double)sage_gc.bytes_allocated),
            sage_number((double)sage_gc_live_bytes()),
            sage_number((double)sage_gc.object_count),
            sage_number((double)sage_gc.collections),
            sage_number(0),
            sage_number((double)next_gc),
            sage_number((double)sage_gc.next_gc_bytes)
        });
}

static SageValue sage_gc_collections_fn(void) {
    return sage_number((double)sage_gc.collections);
}

#include <ctype.h>
static SageValue sage_upper(SageValue value) {
    if (value.type != SAGE_TAG_STRING) return sage_nil();
    size_t len = strlen(value.as.string);
    char* result = (char*)malloc(len + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    for (size_t i = 0; i < len; i++) result[i] = (char)toupper((unsigned char)value.as.string[i]);
    result[len] = '\0';
    return sage_string_take(result);
}
static SageValue sage_lower(SageValue value) {
    if (value.type != SAGE_TAG_STRING) return sage_nil();
    size_t len = strlen(value.as.string);
    char* result = (char*)malloc(len + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    for (size_t i = 0; i < len; i++) result[i] = (char)tolower((unsigned char)value.as.string[i]);
    result[len] = '\0';
    return sage_string_take(result);
}
static SageValue sage_strip_fn(SageValue value) {
    if (value.type != SAGE_TAG_STRING) return sage_nil();
    const char* s = value.as.string;
    while (*s && isspace((unsigned char)*s)) s++;
    const char* end = s + strlen(s);
    while (end > s && isspace((unsigned char)*(end - 1))) end--;
    size_t len = (size_t)(end - s);
    char* result = (char*)malloc(len + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    memcpy(result, s, len);
    result[len] = '\0';
    return sage_string_take(result);
}

static SageValue sage_split_fn(SageValue str_val, SageValue delim_val) {
    if (str_val.type != SAGE_TAG_STRING || delim_val.type != SAGE_TAG_STRING) return sage_array();
    sage_gc_pin();
    const char* s = str_val.as.string;
    const char* delim = delim_val.as.string;
    size_t dlen = strlen(delim);
    SageValue result = sage_array();
    if (dlen == 0) {
        for (size_t i = 0; s[i]; i++) {
            char buf[2] = {s[i], '\0'};
            sage_array_push_raw(result.as.array, sage_string(buf));
        }
        sage_gc_unpin();
        return result;
    }
    const char* start = s;
    const char* found;
    while ((found = strstr(start, delim)) != NULL) {
        size_t len = (size_t)(found - start);
        char* part = (char*)malloc(len + 1);
        if (part == NULL) sage_fail("Runtime Error: out of memory");
        memcpy(part, start, len);
        part[len] = '\0';
        sage_array_push_raw(result.as.array, sage_string_take(part));
        start = found + dlen;
    }
    sage_array_push_raw(result.as.array, sage_string(start));
    sage_gc_unpin();
    return result;
}

static SageValue sage_join_fn(SageValue arr_val, SageValue delim_val) {
    if (arr_val.type != SAGE_TAG_ARRAY || delim_val.type != SAGE_TAG_STRING) return sage_nil();
    SageArray* arr = arr_val.as.array;
    const char* delim = delim_val.as.string;
    size_t dlen = strlen(delim);
    if (arr->count == 0) return sage_string("");
    size_t total = 0;
    for (int i = 0; i < arr->count; i++) {
        if (arr->elements[i].type == SAGE_TAG_STRING) total += strlen(arr->elements[i].as.string);
        if (i > 0) total += dlen;
    }
    char* result = (char*)malloc(total + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    char* p = result;
    for (int i = 0; i < arr->count; i++) {
        if (i > 0) { memcpy(p, delim, dlen); p += dlen; }
        if (arr->elements[i].type == SAGE_TAG_STRING) {
            size_t len = strlen(arr->elements[i].as.string);
            memcpy(p, arr->elements[i].as.string, len);
            p += len;
        }
    }
    *p = '\0';
    return sage_string_take(result);
}

static SageValue sage_replace_fn(SageValue str_val, SageValue old_val, SageValue new_val) {
    if (str_val.type != SAGE_TAG_STRING || old_val.type != SAGE_TAG_STRING || new_val.type != SAGE_TAG_STRING)
        return sage_nil();
    const char* s = str_val.as.string;
    const char* old_s = old_val.as.string;
    const char* new_s = new_val.as.string;
    size_t old_len = strlen(old_s);
    size_t new_len = strlen(new_s);
    if (old_len == 0) return sage_string(s);
    size_t count = 0;
    const char* tmp = s;
    while ((tmp = strstr(tmp, old_s)) != NULL) { count++; tmp += old_len; }
    size_t result_len = strlen(s) + count * (new_len - old_len);
    char* result = (char*)malloc(result_len + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    char* p = result;
    while (*s) {
        if (strncmp(s, old_s, old_len) == 0) {
            memcpy(p, new_s, new_len);
            p += new_len;
            s += old_len;
        } else {
            *p++ = *s++;
        }
    }
    *p = '\0';
    return sage_string_take(result);
}

#include <stdint.h>

typedef struct {
    void* ptr;
    size_t size;
    int owned;
} SagePointer;

static SageValue sage_mem_alloc(SageValue size_val) {
    if (size_val.type != SAGE_TAG_NUMBER) { fputs("mem_alloc(): expects number\n", stderr); return sage_nil(); }
    size_t size = (size_t)size_val.as.number;
    if (size == 0 || size > 1024*1024*64) { fputs("mem_alloc(): invalid size\n", stderr); return sage_nil(); }
    SagePointer* sp = (SagePointer*)malloc(sizeof(SagePointer));
    if (sp == NULL) sage_fail("Runtime Error: out of memory");
    sp->ptr = calloc(1, size);
    if (sp->ptr == NULL) { free(sp); sage_fail("Runtime Error: out of memory"); }
    sp->size = size;
    sp->owned = 1;
    SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = (double)(uintptr_t)sp;
    return v;
}

static SagePointer* sage_as_pointer(SageValue v) {
    if (v.type != SAGE_TAG_NUMBER) return NULL;
    return (SagePointer*)(uintptr_t)v.as.number;
}

static SageValue sage_mem_free(SageValue ptr_val) {
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL) { fputs("mem_free(): expects pointer\n", stderr); return sage_nil(); }
    if (sp->ptr && sp->owned) { free(sp->ptr); sp->ptr = NULL; sp->size = 0; }
    free(sp);
    return sage_nil();
}

static SageValue sage_mem_read(SageValue ptr_val, SageValue off_val, SageValue type_val) {
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL || sp->ptr == NULL || off_val.type != SAGE_TAG_NUMBER || type_val.type != SAGE_TAG_STRING)
        return sage_nil();
    size_t offset = (size_t)off_val.as.number;
    const char* type = type_val.as.string;
    unsigned char* base = (unsigned char*)sp->ptr + offset;
    if (strcmp(type, "byte") == 0) { return sage_number((double)*base); }
    if (strcmp(type, "int") == 0) { int v; memcpy(&v, base, sizeof(int)); return sage_number((double)v); }
    if (strcmp(type, "double") == 0) { double v; memcpy(&v, base, sizeof(double)); return sage_number(v); }
    if (strcmp(type, "string") == 0) { return sage_string((const char*)base); }
    return sage_nil();
}

static SageValue sage_mem_write(SageValue ptr_val, SageValue off_val, SageValue type_val, SageValue val) {
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL || sp->ptr == NULL || off_val.type != SAGE_TAG_NUMBER || type_val.type != SAGE_TAG_STRING)
        return sage_nil();
    size_t offset = (size_t)off_val.as.number;
    const char* type = type_val.as.string;
    unsigned char* base = (unsigned char*)sp->ptr + offset;
    if (strcmp(type, "byte") == 0 && val.type == SAGE_TAG_NUMBER) { *base = (unsigned char)val.as.number; }
    else if (strcmp(type, "int") == 0 && val.type == SAGE_TAG_NUMBER) { int v = (int)val.as.number; memcpy(base, &v, sizeof(int)); }
    else if (strcmp(type, "double") == 0 && val.type == SAGE_TAG_NUMBER) { double v = val.as.number; memcpy(base, &v, sizeof(double)); }
    return sage_nil();
}

static SageValue sage_mem_size(SageValue ptr_val) {
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL) return sage_nil();
    return sage_number((double)sp->size);
}

static SageValue sage_ptr_to_int(SageValue ptr_val) {
    if (ptr_val.type != SAGE_TAG_POINTER) return sage_nil();
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL) return sage_nil();
    return sage_number((double)(uintptr_t)sp->ptr);
}
static SageValue sage_ffi_sym(SageValue handle, SageValue name) {
    if (handle.type != SAGE_TAG_CLIB || name.type != SAGE_TAG_STRING)
        return sage_bool(0);
    void* lib = handle.as.clib;
    if (!lib) return sage_bool(0);
    void* sym = dlsym(lib, name.as.string);
    return sage_bool(sym != NULL);
}
static SageValue sage_ffi_sym_addr(SageValue handle, SageValue name) {
    if (handle.type != SAGE_TAG_CLIB || name.type != SAGE_TAG_STRING)
        return sage_nil();
    void* lib = handle.as.clib;
    if (!lib) return sage_nil();
    void* sym = dlsym(lib, name.as.string);
    if (!sym) return sage_nil();
    return sage_number((double)(uintptr_t)sym);
}
static SageValue sage_addressof(SageValue val) {
    return sage_number((double)(uintptr_t)&val);
}
static SageValue sage_ptr_add(SageValue ptr_val, SageValue offset) {
    if (ptr_val.type != SAGE_TAG_POINTER || offset.type != SAGE_TAG_NUMBER)
        return sage_nil();
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL) return sage_nil();
    SageValue v; v.type = SAGE_TAG_POINTER;
    v.as.pointer = sp;
    sp->ptr = (void*)((uintptr_t)sp->ptr + (intptr_t)offset.as.number);
    return v;
}
static SageValue sage_sizeof(SageValue type_name) {
    if (type_name.type != SAGE_TAG_STRING) return sage_nil();
    const char* tn = type_name.as.string;
    if (strcmp(tn,"char")==0||strcmp(tn,"byte")==0) return sage_number(1);
    if (strcmp(tn,"short")==0) return sage_number(2);
    if (strcmp(tn,"int")==0) return sage_number(4);
    if (strcmp(tn,"long")==0) return sage_number(8);
    if (strcmp(tn,"float")==0) return sage_number(4);
    if (strcmp(tn,"double")==0) return sage_number(8);
    if (strcmp(tn,"ptr")==0) return sage_number(8);
    return sage_nil();
}

static int sage_struct_type_info(const char* type, size_t* out_size, size_t* out_align) {
    if (strcmp(type,"char")==0||strcmp(type,"byte")==0) { *out_size=1; *out_align=1; return 0; }
    if (strcmp(type,"short")==0) { *out_size=sizeof(short); *out_align=sizeof(short); return 0; }
    if (strcmp(type,"int")==0) { *out_size=sizeof(int); *out_align=sizeof(int); return 0; }
    if (strcmp(type,"long")==0) { *out_size=sizeof(long); *out_align=sizeof(long); return 0; }
    if (strcmp(type,"float")==0) { *out_size=sizeof(float); *out_align=sizeof(float); return 0; }
    if (strcmp(type,"double")==0) { *out_size=sizeof(double); *out_align=sizeof(double); return 0; }
    if (strcmp(type,"ptr")==0) { *out_size=sizeof(void*); *out_align=sizeof(void*); return 0; }
    return -1;
}

static SageValue sage_struct_def(SageValue fields) {
    if (fields.type != SAGE_TAG_ARRAY) return sage_nil();
    sage_gc_pin();
    SageValue def = sage_make_dict();
    size_t offset = 0, max_align = 1;
    for (int i = 0; i < fields.as.array->count; i++) {
        SageValue pair = fields.as.array->elements[i];
        if (pair.type != SAGE_TAG_ARRAY || pair.as.array->count < 2) continue;
        if (pair.as.array->elements[0].type != SAGE_TAG_STRING ||
            pair.as.array->elements[1].type != SAGE_TAG_STRING) continue;
        const char* name = pair.as.array->elements[0].as.string;
        const char* type = pair.as.array->elements[1].as.string;
        size_t fsize, falign;
        if (sage_struct_type_info(type, &fsize, &falign) != 0) continue;
        if (falign > max_align) max_align = falign;
        size_t rem = offset % falign;
        if (rem != 0) offset += falign - rem;
        /* store field: "name" -> [offset, type] */
        SageValue field_info = sage_make_array(2, (SageValue[]){
            sage_number((double)offset), sage_string(type)
        });
        sage_dict_set(def.as.dict, name, field_info);
        offset += fsize;
    }
    size_t rem = offset % max_align;
    if (rem != 0) offset += max_align - rem;
    sage_dict_set(def.as.dict, "__size__", sage_number((double)offset));
    sage_dict_set(def.as.dict, "__align__", sage_number((double)max_align));
    sage_gc_unpin();
    return def;
}

static SageValue sage_struct_new(SageValue def) {
    if (def.type != SAGE_TAG_DICT) return sage_nil();
    SageValue size_val = sage_dict_get(def.as.dict, "__size__");
    if (size_val.type != SAGE_TAG_NUMBER) return sage_nil();
    size_t size = (size_t)size_val.as.number;
    SagePointer* sp = (SagePointer*)malloc(sizeof(SagePointer));
    if (sp == NULL) sage_fail("Runtime Error: out of memory");
    sp->ptr = calloc(1, size);
    if (sp->ptr == NULL) { free(sp); sage_fail("Runtime Error: out of memory"); }
    sp->size = size;
    sp->owned = 1;
    SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = (double)(uintptr_t)sp;
    return v;
}

static SageValue sage_struct_get(SageValue ptr_val, SageValue def, SageValue field_name) {
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL || sp->ptr == NULL || def.type != SAGE_TAG_DICT || field_name.type != SAGE_TAG_STRING)
        return sage_nil();
    SageValue info = sage_dict_get(def.as.dict, field_name.as.string);
    if (info.type != SAGE_TAG_ARRAY || info.as.array->count < 2) return sage_nil();
    size_t offset = (size_t)info.as.array->elements[0].as.number;
    const char* type = info.as.array->elements[1].as.string;
    unsigned char* base = (unsigned char*)sp->ptr + offset;
    if (strcmp(type,"char")==0||strcmp(type,"byte")==0) return sage_number((double)*base);
    if (strcmp(type,"short")==0) { short v; memcpy(&v,base,sizeof(short)); return sage_number((double)v); }
    if (strcmp(type,"int")==0) { int v; memcpy(&v,base,sizeof(int)); return sage_number((double)v); }
    if (strcmp(type,"long")==0) { long v; memcpy(&v,base,sizeof(long)); return sage_number((double)v); }
    if (strcmp(type,"float")==0) { float v; memcpy(&v,base,sizeof(float)); return sage_number((double)v); }
    if (strcmp(type,"double")==0) { double v; memcpy(&v,base,sizeof(double)); return sage_number(v); }
    return sage_nil();
}

static SageValue sage_struct_set(SageValue ptr_val, SageValue def, SageValue field_name, SageValue val) {
    SagePointer* sp = sage_as_pointer(ptr_val);
    if (sp == NULL || sp->ptr == NULL || def.type != SAGE_TAG_DICT || field_name.type != SAGE_TAG_STRING)
        return sage_nil();
    SageValue info = sage_dict_get(def.as.dict, field_name.as.string);
    if (info.type != SAGE_TAG_ARRAY || info.as.array->count < 2) return sage_nil();
    size_t offset = (size_t)info.as.array->elements[0].as.number;
    const char* type = info.as.array->elements[1].as.string;
    unsigned char* base = (unsigned char*)sp->ptr + offset;
    if (val.type != SAGE_TAG_NUMBER) return sage_nil();
    if (strcmp(type,"char")==0||strcmp(type,"byte")==0) { *base = (unsigned char)val.as.number; }
    else if (strcmp(type,"short")==0) { short v=(short)val.as.number; memcpy(base,&v,sizeof(short)); }
    else if (strcmp(type,"int")==0) { int v=(int)val.as.number; memcpy(base,&v,sizeof(int)); }
    else if (strcmp(type,"long")==0) { long v=(long)val.as.number; memcpy(base,&v,sizeof(long)); }
    else if (strcmp(type,"float")==0) { float v=(float)val.as.number; memcpy(base,&v,sizeof(float)); }
    else if (strcmp(type,"double")==0) { double v=val.as.number; memcpy(base,&v,sizeof(double)); }
    return sage_nil();
}

static SageValue sage_struct_size(SageValue def) {
    if (def.type != SAGE_TAG_DICT) return sage_nil();
    return sage_dict_get(def.as.dict, "__size__");
}

typedef SageValue (*SageMethodFn)(SageValue, int, SageValue*);
typedef struct { const char* class_name; const char* method_name; SageMethodFn fn; } SageMethodEntry;
typedef struct { const char* name; const char* parent; } SageClassEntry;
#define SAGE_MAX_METHODS 256
#define SAGE_MAX_CLASSES 64
static SageMethodEntry sage_method_table[SAGE_MAX_METHODS];
static int sage_method_count = 0;
static SageClassEntry sage_class_registry[SAGE_MAX_CLASSES];
static int sage_class_count = 0;

static void sage_register_class(const char* name, const char* parent) {
    if (sage_class_count >= SAGE_MAX_CLASSES) sage_fail("too many classes");
    sage_class_registry[sage_class_count].name = name;
    sage_class_registry[sage_class_count].parent = parent;
    sage_class_count++;
}

static void sage_register_method(const char* cls, const char* name, SageMethodFn fn) {
    if (sage_method_count >= SAGE_MAX_METHODS) sage_fail("too many methods");
    sage_method_table[sage_method_count].class_name = cls;
    sage_method_table[sage_method_count].method_name = name;
    sage_method_table[sage_method_count].fn = fn;
    sage_method_count++;
}

static SageValue sage_call_method(SageValue obj, const char* method, int argc, SageValue* argv) {
    if (obj.type != SAGE_TAG_DICT) {
        fprintf(stderr, "Runtime Error: method call on non-instance (type=%d).\n", obj.type);
        exit(1);
    }
    SageValue class_val = sage_dict_get(obj.as.dict, "__class__");
    if (class_val.type != SAGE_TAG_STRING) {
        fprintf(stderr, "Runtime Error: no __class__ on instance (method=%s class_val_type=%d).\n", method, class_val.type);
        exit(1);
    }
    const char* current = class_val.as.string;
    while (current != NULL) {
        for (int i = 0; i < sage_method_count; i++) {
            if (strcmp(sage_method_table[i].class_name, current) == 0 &&
                strcmp(sage_method_table[i].method_name, method) == 0) {
                return sage_method_table[i].fn(obj, argc, argv);
            }
        }
        const char* parent = NULL;
        for (int j = 0; j < sage_class_count; j++) {
            if (strcmp(sage_class_registry[j].name, current) == 0) {
                parent = sage_class_registry[j].parent;
                break;
            }
        }
        current = parent;
    }
    fprintf(stderr, "Runtime Error: Undefined method '%s'.\n", method);
    exit(1);
    return sage_nil();
}

static SageValue sage_construct(const char* class_name, const char* parent_name, int argc, SageValue* argv) {
    sage_gc_pin();
    SageValue inst = sage_make_dict();
    sage_dict_set(inst.as.dict, "__class__", sage_string(class_name));
    if (parent_name != NULL) sage_dict_set(inst.as.dict, "__parent__", sage_string(parent_name));
    sage_gc_unpin();
    const char* current = class_name;
    while (current != NULL) {
        for (int i = 0; i < sage_method_count; i++) {
            if (strcmp(sage_method_table[i].class_name, current) == 0 &&
                strcmp(sage_method_table[i].method_name, "init") == 0) {
                sage_method_table[i].fn(inst, argc, argv);
                return inst;
            }
        }
        const char* parent = NULL;
        for (int j = 0; j < sage_class_count; j++) {
            if (strcmp(sage_class_registry[j].name, current) == 0) {
                parent = sage_class_registry[j].parent;
                break;
            }
        }
        current = parent;
    }
    return inst;
}

static SageValue sage_arch_fn(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return sage_string("x86_64");
#elif defined(__aarch64__) || defined(_M_ARM64)
    return sage_string("aarch64");
#elif defined(__riscv) && __riscv_xlen == 64
    return sage_string("rv64");
#else
    return sage_string("unknown");
#endif
}

#include <time.h>
static SageValue sage_clock_fn(void) {
    return sage_number((double)clock() / CLOCKS_PER_SEC);
}
static SageValue sage_input_fn(SageValue prompt) {
    if (prompt.type == SAGE_TAG_STRING) fputs(prompt.as.string, stdout);
    char buf[4096];
    if (fgets(buf, sizeof(buf), stdin) == NULL) return sage_nil();
    size_t len = strlen(buf);
    if (len > 0 && buf[len-1] == '\n') buf[--len] = '\0';
    return sage_string(buf);
}
static SageValue sage_sys_args(void) {
    extern int sage_argc; extern char** sage_argv;
    SageValue list = sage_array();
    for(int i=0; i<sage_argc; i++) sage_push(list, sage_string(sage_argv[i]));
    return list;
}
static int sage_is_safe_command(const char* cmd) {
    if (!cmd) return 1;
    if (cmd[0] == '-') return 0;
    for (const char* p = cmd; *p; p++) {
        if (!isalnum((unsigned char)*p) && *p != '/' && *p != '.' &&
            *p != '-' && *p != '_' && *p != '~' && *p != ' ' && *p != '\'') {
            return 0;
        }
    }
    return 1;
}
static SageValue sage_sys_exec(SageValue cmd) {
    if(cmd.type != SAGE_TAG_STRING) return sage_number(-1);
    if(!sage_is_safe_command(cmd.as.string)) {
        fprintf(stderr, "Security Error: Unsafe characters in command\n");
        return sage_number(-1);
    }
    return sage_number(system(cmd.as.string));
}
static SageValue sage_io_readfile(SageValue p) {
    if(p.type != SAGE_TAG_STRING) return sage_nil();
    FILE* f = fopen(p.as.string, "rb"); if(!f) return sage_nil();
    fseek(f, 0, SEEK_END); long size = ftell(f); fseek(f, 0, SEEK_SET);
    if (size < 0 || size > SAGE_MAX_READ_SIZE) { fclose(f); return sage_nil(); }
    char* buf = malloc(size + 1); if(!buf) { fclose(f); return sage_nil(); }
    fread(buf, 1, size, f); buf[size] = 0; fclose(f);
    return sage_string_take(buf);
}
static SageValue sage_io_writefile(SageValue p, SageValue c) {
    if(p.type != SAGE_TAG_STRING || c.type != SAGE_TAG_STRING) return sage_bool(0);
    FILE* f = fopen(p.as.string, "wb"); if(!f) return sage_bool(0);
    fwrite(c.as.string, 1, strlen(c.as.string), f); fclose(f); return sage_bool(1);
}
static SageValue sage_io_writebytes(SageValue p, SageValue v) {
    if(p.type != SAGE_TAG_STRING) return sage_bool(0);
    if(v.type == SAGE_TAG_BYTES) {
        FILE* f = fopen(p.as.string, "wb"); if(!f) return sage_bool(0);
        fwrite(v.as.bytes->data, 1, v.as.bytes->count, f); fclose(f); return sage_bool(1);
    }
    if(v.type != SAGE_TAG_ARRAY) return sage_bool(0);
    FILE* f = fopen(p.as.string, "wb"); if(!f) return sage_bool(0);
    SageArray* a = v.as.array;
    unsigned char* buf = malloc(a->count);
    for(int i=0; i<a->count; i++) buf[i] = (unsigned char)a->elements[i].as.number;
    fwrite(buf, 1, a->count, f); fclose(f); free(buf); return sage_bool(1);
}
static SageValue sage_io_appendbytes(SageValue p, SageValue v) {
    if(p.type != SAGE_TAG_STRING) return sage_bool(0);
    if(v.type == SAGE_TAG_BYTES) {
        FILE* f = fopen(p.as.string, "ab"); if(!f) return sage_bool(0);
        fwrite(v.as.bytes->data, 1, v.as.bytes->count, f); fclose(f); return sage_bool(1);
    }
    if(v.type != SAGE_TAG_ARRAY) return sage_bool(0);
    FILE* f = fopen(p.as.string, "ab"); if(!f) return sage_bool(0);
    SageArray* a = v.as.array;
    unsigned char* buf = malloc(a->count);
    for(int i=0; i<a->count; i++) buf[i] = (unsigned char)a->elements[i].as.number;
    fwrite(buf, 1, a->count, f); fclose(f); free(buf); return sage_bool(1);
}
static SageValue sage_io_readbytes(SageValue p) {
    if(p.type != SAGE_TAG_STRING) return sage_nil();
    FILE* f = fopen(p.as.string, "rb"); if(!f) return sage_nil();
    SageValue arr = sage_array();
    if (fseek(f, 0, SEEK_END) == 0) {
        long size = ftell(f); fseek(f, 0, SEEK_SET);
        if (size < 0 || size > SAGE_MAX_READ_SIZE) { fclose(f); return sage_nil(); }
        if (size > 0) {
            unsigned char* buf = malloc(size);
            fread(buf, 1, size, f);
            for(int i=0; i<size; i++) sage_push(arr, sage_number((double)buf[i]));
            free(buf);
        }
        fclose(f);
        return arr;
    }
    // Non-seekable file (e.g., /dev/urandom) — read in chunks until EOF
    unsigned char chunk[4096];
    size_t nread;
    size_t total_read = 0;
    while ((nread = fread(chunk, 1, sizeof(chunk), f)) > 0) {
        if (total_read + nread > SAGE_MAX_READ_SIZE) {
            nread = SAGE_MAX_READ_SIZE - total_read;
        }
        for (size_t i = 0; i < nread; i++) sage_push(arr, sage_number((double)chunk[i]));
        total_read += nread;
        if (total_read >= SAGE_MAX_READ_SIZE) break;
    }
    fclose(f);
    return arr;
}
static SageValue sage_io_exists(SageValue p) {
    if(p.type != SAGE_TAG_STRING) return sage_bool(0);
    FILE* f = fopen(p.as.string, "r"); if(f){ fclose(f); return sage_bool(1); } return sage_bool(0);
}
static SageValue sage_string_substr(SageValue s, SageValue start, SageValue len) {
    if(s.type != SAGE_TAG_STRING || start.type != SAGE_TAG_NUMBER || len.type != SAGE_TAG_NUMBER) return sage_nil();
    int st = (int)start.as.number; int l = (int)len.as.number;
    int slen = strlen(s.as.string);
    if(st < 0 || st > slen) return sage_string("");
    if(l < 0) l = 0; if(st + l > slen) l = slen - st;
    char* buf = malloc(l + 1); if(!buf) return sage_nil();
    memcpy(buf, s.as.string + st, l); buf[l] = 0;
    return sage_string_take(buf);
}

static SageSlot sage_global_tcp_1;

void sage_gc_mark_program_globals(void) {
    if (sage_global_tcp_1.defined) sage_gc_mark_value(sage_global_tcp_1.value);
}


int sage_argc; char** sage_argv;
int main(int argc, char** argv) {
    sage_argc = argc; sage_argv = argv;
    sage_global_tcp_1 = sage_slot_undefined();
    SageSlot* sage_gc_global_roots[1] = {&sage_global_tcp_1};
    SageGcFrame sage_gc_main_frame;
    sage_gc_push_frame(&sage_gc_main_frame, sage_gc_global_roots, 1);
    sage_define_slot(&sage_global_tcp_1, sage_init_native_module("tcp"));
    (void)sage_call_method(sage_load_slot(&sage_global_tcp_1, "tcp"), "listen", 3, (SageValue[]){sage_string("0.0.0.0"), sage_number(42000), sage_number(32)});
    sage_gc_pop_frame(&sage_gc_main_frame);
    sage_gc_shutdown();
    return 0;
}
