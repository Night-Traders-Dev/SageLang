#include <stdint.h>
#include <stddef.h>

/* Memory Management */
static uint8_t heap[1024 * 1024]; /* 1MB heap for kernel */
static size_t heap_ptr = 0;

void* kernel_malloc(size_t size) {
    if (heap_ptr + size > sizeof(heap)) return 0;
    void* ptr = &heap[heap_ptr];
    heap_ptr += (size + 7) & ~7; /* Align to 8 bytes */
    return ptr;
}

/* SageValue structure matching the AOT backend's expectation */
typedef enum {
    SAGE_NIL = 0,
    SAGE_NUMBER = 1,
    SAGE_BOOL = 2,
    SAGE_STRING = 3,
    SAGE_ARRAY = 4,
    SAGE_DICT = 5,
} SageTag;

typedef struct {
    int32_t type;
    union {
        double number;
        int32_t boolean;
        char* string;
        void* pointer;
    } as;
} SageValue;

/* Runtime Functions */

SageValue sage_rt_nil(void) {
    SageValue v;
    v.type = SAGE_NIL;
    v.as.number = 0;
    return v;
}

SageValue sage_rt_number(double n) {
    SageValue v;
    v.type = SAGE_NUMBER;
    v.as.number = n;
    return v;
}

SageValue sage_rt_bool(int32_t b) {
    SageValue v;
    v.type = SAGE_BOOL;
    v.as.boolean = b;
    return v;
}

SageValue sage_rt_string(const char* s) {
    SageValue v;
    v.type = SAGE_STRING;
    v.as.string = (char*)s;
    return v;
}

/* Arithmetic */
SageValue sage_rt_add(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_number(a.as.number + b.as.number);
    return sage_rt_nil();
}

SageValue sage_rt_sub(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_number(a.as.number - b.as.number);
    return sage_rt_nil();
}

SageValue sage_rt_mul(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_number(a.as.number * b.as.number);
    return sage_rt_nil();
}

SageValue sage_rt_div(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER && b.as.number != 0)
        return sage_rt_number(a.as.number / b.as.number);
    return sage_rt_nil();
}

/* Comparisons */
SageValue sage_rt_eq(SageValue a, SageValue b) {
    if (a.type != b.type) return sage_rt_bool(0);
    if (a.type == SAGE_NUMBER) return sage_rt_bool(a.as.number == b.as.number);
    if (a.type == SAGE_BOOL) return sage_rt_bool(a.as.boolean == b.as.boolean);
    return sage_rt_bool(0);
}

SageValue sage_rt_lt(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_bool(a.as.number < b.as.number);
    return sage_rt_bool(0);
}

SageValue sage_rt_gt(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_bool(a.as.number > b.as.number);
    return sage_rt_bool(0);
}

/* Globals */
typedef struct {
    char* name;
    SageValue value;
} GlobalEntry;

static GlobalEntry sage_globals[256];
static int sage_global_count = 0;

SageValue sage_rt_get_global(void* unused, const char* name) {
    for (int i = 0; i < sage_global_count; i++) {
        const char* gname = sage_globals[i].name;
        int match = 1;
        for (int j = 0; name[j] || gname[j]; j++) {
            if (name[j] != gname[j]) { match = 0; break; }
        }
        if (match) return sage_globals[i].value;
    }
    return sage_rt_nil();
}

void sage_rt_set_global(void* unused, const char* name, SageValue val) {
    for (int i = 0; i < sage_global_count; i++) {
        const char* gname = sage_globals[i].name;
        int match = 1;
        for (int j = 0; name[j] || gname[j]; j++) {
            if (name[j] != gname[j]) { match = 0; break; }
        }
        if (match) { sage_globals[i].value = val; return; }
    }
    if (sage_global_count < 256) {
        sage_globals[sage_global_count].name = (char*)name;
        sage_globals[sage_global_count].value = val;
        sage_global_count++;
    }
}

int32_t sage_rt_get_bool(SageValue v) {
    if (v.type == SAGE_BOOL) return v.as.boolean;
    if (v.type == SAGE_NIL) return 0;
    if (v.type == SAGE_NUMBER) return v.as.number != 0;
    return 1;
}

/* Built-ins */
SageValue sage_fn_append(SageValue arr, SageValue val) { return sage_rt_nil(); }
SageValue sage_fn_len(SageValue v) { return sage_rt_number(0); }
SageValue sage_fn_gc_disable(void) { return sage_rt_nil(); }
SageValue sage_fn_gc_enable(void) { return sage_rt_nil(); }
SageValue sage_fn_gc_collect(void) { return sage_rt_nil(); }

/* Entry points */
extern void sage_fn_kmain(SageValue args);

void _start(void) {
    sage_fn_kmain(sage_rt_nil());
    for (;;) { __asm__ volatile ("hlt"); }
}
