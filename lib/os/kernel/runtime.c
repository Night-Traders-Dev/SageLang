#include <stdint.h>

/* SageValue structure matching the AOT backend's expectation */
typedef enum {
    SAGE_NIL = 0,
    SAGE_NUMBER = 1,
    SAGE_BOOL = 2,
    SAGE_STRING = 3,
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

/* Dummy globals storage */
SageValue sage_globals[1024];

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
    v.as.string = (char*)s; /* Minimal: just point to the constant string */
    return v;
}

SageValue sage_rt_get_global(void* globals, const char* name) {
    /* Minimal: return nil for now */
    return sage_rt_nil();
}

void sage_rt_set_global(void* globals, const char* name, SageValue val) {
    /* Minimal: ignore for now */
}

int32_t sage_rt_get_bool(SageValue v) {
    if (v.type == SAGE_BOOL) return v.as.boolean;
    if (v.type == SAGE_NIL) return 0;
    return 1;
}

/* Built-in Sage Functions (prefixed with sage_fn_) */

SageValue sage_fn_gc_disable(void) {
    return sage_rt_nil();
}

SageValue sage_fn_gc_enable(void) {
    return sage_rt_nil();
}

SageValue sage_fn_gc_collect(void) {
    return sage_rt_nil();
}

/* Bare-metal entry point */
extern void sage_entry(void);

void _start(void) {
    sage_entry();
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}
