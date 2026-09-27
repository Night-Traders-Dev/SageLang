/*
 * Portable SageValue runtime for native-assembly backend tests.
 *
 * The real kernel runtime (core/lib/os/kernel/runtime.c) is x86-64 only -- it
 * contains inline asm with `hlt`, so it cannot be assembled for any other
 * target. This file exists purely so that assembly emitted by the AOT backend
 * can be assembled, linked and *executed* on whatever host runs the test, which
 * is the only way to check the emitter rather than just the validator.
 *
 * Semantics are copied from core/lib/os/kernel/runtime.c and the value
 * formatting from core/src/c/llvm_runtime.c so that output matches the other
 * backends. Nothing here is target specific: every argument and return value is
 * a real C signature, so the compiler applies the correct ABI for the host and
 * the emitted assembly is measured against it.
 */

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

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

int32_t sage_rt_get_bool(SageValue v);

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

SageValue sage_rt_mod(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER && b.as.number != 0)
        return sage_rt_number(fmod(a.as.number, b.as.number));
    return sage_rt_nil();
}

SageValue sage_rt_neg(SageValue a) {
    if (a.type == SAGE_NUMBER) return sage_rt_number(-a.as.number);
    return sage_rt_nil();
}

/* Comparisons */
SageValue sage_rt_eq(SageValue a, SageValue b) {
    if (a.type != b.type) return sage_rt_bool(0);
    if (a.type == SAGE_NUMBER) return sage_rt_bool(a.as.number == b.as.number);
    if (a.type == SAGE_BOOL) return sage_rt_bool(a.as.boolean == b.as.boolean);
    if (a.type == SAGE_STRING)
        return sage_rt_bool(strcmp(a.as.string, b.as.string) == 0);
    return sage_rt_bool(1);
}

SageValue sage_rt_neq(SageValue a, SageValue b) {
    SageValue e = sage_rt_eq(a, b);
    return sage_rt_bool(!e.as.boolean);
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

SageValue sage_rt_lte(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_bool(a.as.number <= b.as.number);
    return sage_rt_bool(0);
}

SageValue sage_rt_gte(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_bool(a.as.number >= b.as.number);
    return sage_rt_bool(0);
}

/* Logic */
SageValue sage_rt_not(SageValue a) { return sage_rt_bool(!sage_rt_get_bool(a)); }

SageValue sage_rt_and(SageValue a, SageValue b) {
    return sage_rt_bool(sage_rt_get_bool(a) && sage_rt_get_bool(b));
}

SageValue sage_rt_or(SageValue a, SageValue b) {
    return sage_rt_bool(sage_rt_get_bool(a) || sage_rt_get_bool(b));
}

/* Globals */
typedef struct {
    char* name;
    SageValue value;
} GlobalEntry;

/* Not static: emitted assembly takes the address of this symbol and passes it
   as the first argument of sage_rt_get_global/sage_rt_set_global, so it has to
   be externally visible. core/lib/os/kernel/runtime.c declares its own copy
   static, which means a natively linked program that uses globals cannot
   resolve the reference against that runtime. */
GlobalEntry sage_globals[256];
static int sage_global_count = 0;

SageValue sage_rt_get_global(void* unused, const char* name) {
    (void)unused;
    for (int i = 0; i < sage_global_count; i++)
        if (strcmp(sage_globals[i].name, name) == 0) return sage_globals[i].value;
    return sage_rt_nil();
}

void sage_rt_set_global(void* unused, const char* name, SageValue val) {
    (void)unused;
    for (int i = 0; i < sage_global_count; i++) {
        if (strcmp(sage_globals[i].name, name) == 0) {
            sage_globals[i].value = val;
            return;
        }
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

/* Printing -- matches llvm_runtime.c's formatting */
static void sage_rt_format_number(double n, char* buf, size_t bufsize) {
    if (isfinite(n) && n >= -9007199254740992.0 && n <= 9007199254740992.0 &&
        n == (double)(long long)n) {
        snprintf(buf, bufsize, "%lld", (long long)n);
        return;
    }
    for (int prec = 15; prec <= 17; prec++) {
        snprintf(buf, bufsize, "%.*g", prec, n);
        if (strtod(buf, NULL) == n) return;
    }
}

void sage_rt_print(SageValue v) {
    switch (v.type) {
        case SAGE_NUMBER: {
            char buf[64];
            sage_rt_format_number(v.as.number, buf, sizeof(buf));
            printf("%s", buf);
            break;
        }
        case SAGE_BOOL: printf(v.as.boolean ? "true" : "false"); break;
        case SAGE_NIL: printf("nil"); break;
        case SAGE_STRING: printf("%s", v.as.string); break;
    }
    printf("\n");
}
