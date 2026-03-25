// llvm_runtime.c — Standalone C runtime for SageLang LLVM IR output
//
// This file is compiled separately and linked with LLVM-generated .ll files.
// It implements all sage_rt_* functions that the LLVM backend declares.
//
// The SageValue layout must match the LLVM IR declaration:
//   %SageValue = type { i32, [8 x i8] }
// Which maps to: struct { int32_t type; union { double; char*; void*; } }

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

#include "gpu_api.h"

// Safe allocation wrappers — abort on OOM instead of returning NULL
static void* safe_realloc(void* ptr, size_t size) {
    void* result = realloc(ptr, size);
    if (result == NULL && size > 0) {
        fprintf(stderr, "sage_rt: out of memory (realloc %zu bytes)\n", size);
        abort();
    }
    return result;
}

static void* safe_calloc(size_t count, size_t size) {
    void* result = calloc(count, size);
    if (result == NULL && count > 0 && size > 0) {
        fprintf(stderr, "sage_rt: out of memory (calloc %zu * %zu bytes)\n", count, size);
        abort();
    }
    return result;
}

// ============================================================================
// SageValue — matches LLVM IR %SageValue = type { i32, [8 x i8] }
// ============================================================================

typedef enum {
    SAGE_NIL = 0,
    SAGE_NUMBER = 1,
    SAGE_BOOL = 2,
    SAGE_STRING = 3,
    SAGE_FUNCTION = 4,
    SAGE_NATIVE = 5,
    SAGE_ARRAY = 6,
    SAGE_DICT = 7,
    SAGE_TUPLE = 8,
    SAGE_CLASS = 9,
    SAGE_INSTANCE = 10,
} SageTag;

typedef struct SageValue SageValue;

typedef struct {
    SageValue* elements;
    int count;
    int capacity;
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

typedef struct {
    char* name;
    SageDict* fields;
    void* class_def;
} SageInstance;

struct SageValue {
    int32_t type;
    union {
        double number;
        int32_t boolean;
        char* string;
        SageArray* array;
        SageDict* dict;
        SageTuple* tuple;
        SageInstance* instance;
        void* pointer;
    } as;
};

// ============================================================================
// Constructors
// ============================================================================

SageValue sage_rt_number(double v) {
    SageValue sv;
    sv.type = SAGE_NUMBER;
    sv.as.number = v;
    return sv;
}

SageValue sage_rt_bool(int32_t v) {
    SageValue sv;
    sv.type = SAGE_BOOL;
    sv.as.boolean = v;
    return sv;
}

SageValue sage_rt_string(const char* s) {
    SageValue sv;
    sv.type = SAGE_STRING;
    if (s == NULL) s = "";
    size_t len = strlen(s);
    sv.as.string = malloc(len + 1);
    if (!sv.as.string) { fprintf(stderr, "OOM\n"); abort(); }
    memcpy(sv.as.string, s, len + 1);
    return sv;
}

SageValue sage_rt_nil(void) {
    SageValue sv;
    sv.type = SAGE_NIL;
    sv.as.number = 0;
    return sv;
}

// ============================================================================
// Truthiness
// ============================================================================

static int is_truthy(SageValue v) {
    switch (v.type) {
        case SAGE_NIL: return 0;
        case SAGE_BOOL: return v.as.boolean != 0;
        // Sage: 0 is truthy, only nil and false are falsy
        default: return 1;
    }
}

SageValue sage_rt_is_truthy(SageValue v) {
    return sage_rt_bool(is_truthy(v));
}

int32_t sage_rt_get_bool(SageValue v) {
    return is_truthy(v);
}

// ============================================================================
// Arithmetic
// ============================================================================

static double as_num(SageValue v) {
    if (v.type == SAGE_NUMBER) return v.as.number;
    return 0.0;
}

SageValue sage_rt_add(SageValue a, SageValue b) {
    if (a.type == SAGE_NUMBER && b.type == SAGE_NUMBER)
        return sage_rt_number(a.as.number + b.as.number);
    if (a.type == SAGE_STRING && b.type == SAGE_STRING) {
        size_t la = strlen(a.as.string), lb = strlen(b.as.string);
        char* r = malloc(la + lb + 1);
        if (!r) { fprintf(stderr, "OOM\n"); abort(); }
        memcpy(r, a.as.string, la);
        memcpy(r + la, b.as.string, lb + 1);
        SageValue sv;
        sv.type = SAGE_STRING;
        sv.as.string = r;
        return sv;
    }
    return sage_rt_nil();
}

SageValue sage_rt_sub(SageValue a, SageValue b) {
    return sage_rt_number(as_num(a) - as_num(b));
}

SageValue sage_rt_mul(SageValue a, SageValue b) {
    return sage_rt_number(as_num(a) * as_num(b));
}

SageValue sage_rt_div(SageValue a, SageValue b) {
    double d = as_num(b);
    if (d == 0.0) { fprintf(stderr, "Runtime Error: Division by zero.\n"); return sage_rt_nil(); }
    return sage_rt_number(as_num(a) / d);
}

SageValue sage_rt_mod(SageValue a, SageValue b) {
    double d = as_num(b);
    if (d == 0.0) { fprintf(stderr, "Runtime Error: Modulo by zero.\n"); return sage_rt_nil(); }
    return sage_rt_number(fmod(as_num(a), d));
}

SageValue sage_rt_neg(SageValue a) {
    return sage_rt_number(-as_num(a));
}

// ============================================================================
// Comparison
// ============================================================================

static int vals_equal(SageValue a, SageValue b) {
    if (a.type != b.type) return 0;
    switch (a.type) {
        case SAGE_NUMBER: return a.as.number == b.as.number;
        case SAGE_BOOL: return a.as.boolean == b.as.boolean;
        case SAGE_NIL: return 1;
        case SAGE_STRING: return strcmp(a.as.string, b.as.string) == 0;
        default: return 0;
    }
}

SageValue sage_rt_eq(SageValue a, SageValue b)  { return sage_rt_bool(vals_equal(a, b)); }
SageValue sage_rt_neq(SageValue a, SageValue b) { return sage_rt_bool(!vals_equal(a, b)); }
SageValue sage_rt_lt(SageValue a, SageValue b)  { return sage_rt_bool(as_num(a) < as_num(b)); }
SageValue sage_rt_gt(SageValue a, SageValue b)  { return sage_rt_bool(as_num(a) > as_num(b)); }
SageValue sage_rt_lte(SageValue a, SageValue b) { return sage_rt_bool(as_num(a) <= as_num(b)); }
SageValue sage_rt_gte(SageValue a, SageValue b) { return sage_rt_bool(as_num(a) >= as_num(b)); }

// ============================================================================
// Logical
// ============================================================================

SageValue sage_rt_and(SageValue a, SageValue b) {
    if (!is_truthy(a)) return a;
    return b;
}

SageValue sage_rt_or(SageValue a, SageValue b) {
    if (is_truthy(a)) return a;
    return b;
}

SageValue sage_rt_not(SageValue a) {
    return sage_rt_bool(!is_truthy(a));
}

// ============================================================================
// Bitwise
// ============================================================================

SageValue sage_rt_bit_and(SageValue a, SageValue b) { return sage_rt_number((double)((long long)as_num(a) & (long long)as_num(b))); }
SageValue sage_rt_bit_or(SageValue a, SageValue b)  { return sage_rt_number((double)((long long)as_num(a) | (long long)as_num(b))); }
SageValue sage_rt_bit_xor(SageValue a, SageValue b) { return sage_rt_number((double)((long long)as_num(a) ^ (long long)as_num(b))); }
SageValue sage_rt_bit_not(SageValue a) { return sage_rt_number((double)(~(long long)as_num(a))); }
SageValue sage_rt_shl(SageValue a, SageValue b) { return sage_rt_number((double)((long long)as_num(a) << (long long)as_num(b))); }
SageValue sage_rt_shr(SageValue a, SageValue b) { return sage_rt_number((double)((long long)as_num(a) >> (long long)as_num(b))); }

// ============================================================================
// Print
// ============================================================================

static void print_value(SageValue v) {
    switch (v.type) {
        case SAGE_NUMBER: {
            double d = v.as.number;
            if (d == (long long)d && fabs(d) < 1e15)
                printf("%lld", (long long)d);
            else
                printf("%g", d);
            break;
        }
        case SAGE_BOOL: printf(v.as.boolean ? "true" : "false"); break;
        case SAGE_NIL: printf("nil"); break;
        case SAGE_STRING: printf("%s", v.as.string); break;
        case SAGE_ARRAY: {
            SageArray* a = v.as.array;
            printf("[");
            for (int i = 0; i < a->count; i++) {
                if (i > 0) printf(", ");
                print_value(a->elements[i]);
            }
            printf("]");
            break;
        }
        case SAGE_DICT: {
            SageDict* d = v.as.dict;
            printf("{");
            for (int i = 0; i < d->count; i++) {
                if (i > 0) printf(", ");
                printf("\"%s\": ", d->keys[i]);
                print_value(d->values[i]);
            }
            printf("}");
            break;
        }
        case SAGE_TUPLE: {
            SageTuple* t = v.as.tuple;
            printf("(");
            for (int i = 0; i < t->count; i++) {
                if (i > 0) printf(", ");
                print_value(t->elements[i]);
            }
            if (t->count == 1) printf(",");
            printf(")");
            break;
        }
        default: printf("<value type=%d>", v.type); break;
    }
}

void sage_rt_print(SageValue v) {
    print_value(v);
    printf("\n");
}

// ============================================================================
// Conversion
// ============================================================================

SageValue sage_rt_str(SageValue v) {
    char buf[64];
    switch (v.type) {
        case SAGE_NUMBER: {
            double d = v.as.number;
            if (d == (long long)d && fabs(d) < 1e15)
                snprintf(buf, sizeof(buf), "%lld", (long long)d);
            else
                snprintf(buf, sizeof(buf), "%g", d);
            return sage_rt_string(buf);
        }
        case SAGE_BOOL: return sage_rt_string(v.as.boolean ? "true" : "false");
        case SAGE_NIL: return sage_rt_string("nil");
        case SAGE_STRING: return sage_rt_string(v.as.string);
        default:
            snprintf(buf, sizeof(buf), "<value type=%d>", v.type);
            return sage_rt_string(buf);
    }
}

SageValue sage_rt_tonumber(SageValue v) {
    if (v.type == SAGE_NUMBER) return v;
    if (v.type == SAGE_STRING) return sage_rt_number(strtod(v.as.string, NULL));
    return sage_rt_nil();
}

SageValue sage_rt_len(SageValue v) {
    if (v.type == SAGE_STRING) return sage_rt_number((double)strlen(v.as.string));
    if (v.type == SAGE_ARRAY) return sage_rt_number((double)v.as.array->count);
    if (v.type == SAGE_DICT) return sage_rt_number((double)v.as.dict->count);
    if (v.type == SAGE_TUPLE) return sage_rt_number((double)v.as.tuple->count);
    return sage_rt_number(0);
}

// ============================================================================
// Array operations
// ============================================================================

SageValue sage_rt_array_new(int32_t count) {
    SageValue sv;
    sv.type = SAGE_ARRAY;
    sv.as.array = malloc(sizeof(SageArray));
    if (!sv.as.array) { fprintf(stderr, "OOM\n"); abort(); }
    sv.as.array->count = 0;
    sv.as.array->capacity = count > 0 ? count : 4;
    sv.as.array->elements = safe_calloc((size_t)sv.as.array->capacity, sizeof(SageValue));
    if (!sv.as.array->elements) { fprintf(stderr, "OOM\n"); abort(); }
    return sv;
}

void sage_rt_array_set(SageValue arr, int32_t idx, SageValue val) {
    if (arr.type != SAGE_ARRAY) return;
    SageArray* a = arr.as.array;
    while (idx >= a->capacity) {
        a->capacity *= 2;
        a->elements = safe_realloc(a->elements, sizeof(SageValue) * (size_t)a->capacity);
        if (!a->elements) { fprintf(stderr, "OOM\n"); abort(); }
    }
    a->elements[idx] = val;
    if (idx >= a->count) a->count = idx + 1;
}

SageValue sage_rt_array_push(SageValue arr, SageValue val) {
    if (arr.type != SAGE_ARRAY) return sage_rt_nil();
    SageArray* a = arr.as.array;
    if (a->count >= a->capacity) {
        a->capacity = a->capacity ? a->capacity * 2 : 4;
        a->elements = safe_realloc(a->elements, sizeof(SageValue) * (size_t)a->capacity);
        if (!a->elements) { fprintf(stderr, "OOM\n"); abort(); }
    }
    a->elements[a->count++] = val;
    return sage_rt_nil();
}

SageValue sage_rt_array_pop(SageValue arr) {
    if (arr.type != SAGE_ARRAY || arr.as.array->count == 0) return sage_rt_nil();
    return arr.as.array->elements[--arr.as.array->count];
}

int32_t sage_rt_array_len(SageValue arr) {
    if (arr.type != SAGE_ARRAY) return 0;
    return arr.as.array->count;
}

SageValue sage_rt_index(SageValue obj, SageValue idx) {
    if (obj.type == SAGE_ARRAY && idx.type == SAGE_NUMBER) {
        int i = (int)idx.as.number;
        SageArray* a = obj.as.array;
        if (i < 0) i += a->count;
        if (i < 0 || i >= a->count) return sage_rt_nil();
        return a->elements[i];
    }
    if (obj.type == SAGE_STRING && idx.type == SAGE_NUMBER) {
        int i = (int)idx.as.number;
        int len = (int)strlen(obj.as.string);
        if (i < 0) i += len;
        if (i < 0 || i >= len) return sage_rt_nil();
        char buf[2] = { obj.as.string[i], '\0' };
        return sage_rt_string(buf);
    }
    if (obj.type == SAGE_DICT && idx.type == SAGE_STRING) {
        SageDict* d = obj.as.dict;
        for (int i = 0; i < d->count; i++) {
            if (strcmp(d->keys[i], idx.as.string) == 0)
                return d->values[i];
        }
        return sage_rt_nil();
    }
    if (obj.type == SAGE_TUPLE && idx.type == SAGE_NUMBER) {
        int i = (int)idx.as.number;
        SageTuple* t = obj.as.tuple;
        if (i < 0) i += t->count;
        if (i < 0 || i >= t->count) return sage_rt_nil();
        return t->elements[i];
    }
    return sage_rt_nil();
}

void sage_rt_index_set(SageValue obj, SageValue idx, SageValue val) {
    if (obj.type == SAGE_ARRAY && idx.type == SAGE_NUMBER) {
        int i = (int)idx.as.number;
        SageArray* a = obj.as.array;
        if (i >= 0 && i < a->count) a->elements[i] = val;
    } else if (obj.type == SAGE_DICT && idx.type == SAGE_STRING) {
        // Set in dict by string key
        SageDict* d = obj.as.dict;
        for (int i = 0; i < d->count; i++) {
            if (strcmp(d->keys[i], idx.as.string) == 0) {
                d->values[i] = val;
                return;
            }
        }
        // New key
        if (d->count >= d->capacity) {
            d->capacity = d->capacity ? d->capacity * 2 : 8;
            d->keys = safe_realloc(d->keys, sizeof(char*) * (size_t)d->capacity);
            d->values = safe_realloc(d->values, sizeof(SageValue) * (size_t)d->capacity);
        }
        d->keys[d->count] = strdup(idx.as.string);
        d->values[d->count] = val;
        d->count++;
    }
}

// ============================================================================
// Dict operations (linear-scan for simplicity in compiled output)
// ============================================================================

SageValue sage_rt_dict_new(void) {
    SageValue sv;
    sv.type = SAGE_DICT;
    sv.as.dict = safe_calloc(1, sizeof(SageDict));
    if (!sv.as.dict) { fprintf(stderr, "OOM\n"); abort(); }
    return sv;
}

void sage_rt_dict_set(SageValue dict, const char* key, SageValue val) {
    if (dict.type != SAGE_DICT || key == NULL) return;
    SageDict* d = dict.as.dict;
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->keys[i], key) == 0) {
            d->values[i] = val;
            return;
        }
    }
    if (d->count >= d->capacity) {
        d->capacity = d->capacity ? d->capacity * 2 : 8;
        d->keys = safe_realloc(d->keys, sizeof(char*) * (size_t)d->capacity);
        d->values = safe_realloc(d->values, sizeof(SageValue) * (size_t)d->capacity);
    }
    d->keys[d->count] = strdup(key);
    d->values[d->count] = val;
    d->count++;
}

SageValue sage_rt_dict_get(SageValue dict, const char* key) {
    if (dict.type != SAGE_DICT || key == NULL) return sage_rt_nil();
    SageDict* d = dict.as.dict;
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->keys[i], key) == 0) return d->values[i];
    }
    return sage_rt_nil();
}

// ============================================================================
// Tuple operations
// ============================================================================

SageValue sage_rt_tuple_new(int32_t count) {
    SageValue sv;
    sv.type = SAGE_TUPLE;
    sv.as.tuple = malloc(sizeof(SageTuple));
    if (!sv.as.tuple) { fprintf(stderr, "OOM\n"); abort(); }
    sv.as.tuple->count = count;
    sv.as.tuple->elements = safe_calloc(count > 0 ? (size_t)count : 1, sizeof(SageValue));
    return sv;
}

void sage_rt_tuple_set(SageValue tup, int32_t idx, SageValue val) {
    if (tup.type != SAGE_TUPLE) return;
    if (idx >= 0 && idx < tup.as.tuple->count)
        tup.as.tuple->elements[idx] = val;
}

// ============================================================================
// Slice
// ============================================================================

SageValue sage_rt_slice(SageValue arr, SageValue start_v, SageValue end_v) {
    if (arr.type != SAGE_ARRAY) return sage_rt_nil();
    SageArray* a = arr.as.array;
    int s = (start_v.type == SAGE_NUMBER) ? (int)start_v.as.number : 0;
    int e = (end_v.type == SAGE_NUMBER) ? (int)end_v.as.number : a->count;
    if (s < 0) s += a->count;
    if (e < 0) e += a->count;
    if (s < 0) s = 0;
    if (e > a->count) e = a->count;
    if (s >= e) return sage_rt_array_new(0);

    SageValue result = sage_rt_array_new(e - s);
    for (int i = s; i < e; i++) {
        sage_rt_array_push(result, a->elements[i]);
    }
    return result;
}

// ============================================================================
// Property access (for dict-as-object pattern)
// ============================================================================

SageValue sage_rt_get_attr(SageValue obj, const char* name) {
    if (obj.type == SAGE_DICT) return sage_rt_dict_get(obj, name);
    if (obj.type == SAGE_INSTANCE && obj.as.instance != NULL) {
        SageDict* fields = obj.as.instance->fields;
        if (fields) {
            for (int i = 0; i < fields->count; i++) {
                if (strcmp(fields->keys[i], name) == 0)
                    return fields->values[i];
            }
        }
    }
    return sage_rt_nil();
}

void sage_rt_set_attr(SageValue obj, const char* name, SageValue val) {
    if (obj.type == SAGE_DICT) {
        sage_rt_dict_set(obj, name, val);
    } else if (obj.type == SAGE_INSTANCE && obj.as.instance != NULL) {
        SageDict* fields = obj.as.instance->fields;
        if (!fields) return;
        for (int i = 0; i < fields->count; i++) {
            if (strcmp(fields->keys[i], name) == 0) {
                fields->values[i] = val;
                return;
            }
        }
        // Add new field
        if (fields->count >= fields->capacity) {
            fields->capacity = fields->capacity ? fields->capacity * 2 : 8;
            fields->keys = safe_realloc(fields->keys, sizeof(char*) * (size_t)fields->capacity);
            fields->values = safe_realloc(fields->values, sizeof(SageValue) * (size_t)fields->capacity);
        }
        fields->keys[fields->count] = strdup(name);
        fields->values[fields->count] = val;
        fields->count++;
    }
}

// ============================================================================
// Range (for `for x in range(n)`)
// ============================================================================

SageValue sage_rt_range(SageValue n) {
    int count = (n.type == SAGE_NUMBER) ? (int)n.as.number : 0;
    if (count < 0) count = 0;
    SageValue arr = sage_rt_array_new(count);
    for (int i = 0; i < count; i++) {
        sage_rt_array_push(arr, sage_rt_number((double)i));
    }
    return arr;
}

// ============================================================================
// Dict query operations
// ============================================================================

SageValue sage_rt_dict_keys(SageValue dict) {
    if (dict.type != SAGE_DICT) return sage_rt_array_new(0);
    SageDict* d = dict.as.dict;
    SageValue arr = sage_rt_array_new(d->count);
    for (int i = 0; i < d->count; i++) {
        sage_rt_array_push(arr, sage_rt_string(d->keys[i]));
    }
    return arr;
}

SageValue sage_rt_dict_values(SageValue dict) {
    if (dict.type != SAGE_DICT) return sage_rt_array_new(0);
    SageDict* d = dict.as.dict;
    SageValue arr = sage_rt_array_new(d->count);
    for (int i = 0; i < d->count; i++) {
        sage_rt_array_push(arr, d->values[i]);
    }
    return arr;
}

SageValue sage_rt_dict_has(SageValue dict, SageValue key) {
    if (dict.type != SAGE_DICT || key.type != SAGE_STRING) return sage_rt_bool(0);
    SageDict* d = dict.as.dict;
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->keys[i], key.as.string) == 0) return sage_rt_bool(1);
    }
    return sage_rt_bool(0);
}

// ============================================================================
// Type introspection
// ============================================================================

SageValue sage_rt_type(SageValue v) {
    switch (v.type) {
        case SAGE_NUMBER: return sage_rt_string("number");
        case SAGE_BOOL: return sage_rt_string("bool");
        case SAGE_NIL: return sage_rt_string("nil");
        case SAGE_STRING: return sage_rt_string("string");
        case SAGE_ARRAY: return sage_rt_string("array");
        case SAGE_DICT: return sage_rt_string("dict");
        case SAGE_TUPLE: return sage_rt_string("tuple");
        case SAGE_INSTANCE: return sage_rt_string("instance");
        default: return sage_rt_string("unknown");
    }
}

// ============================================================================
// Input (stdin)
// ============================================================================

SageValue sage_rt_input(SageValue prompt) {
    if (prompt.type == SAGE_STRING) {
        printf("%s", prompt.as.string);
        fflush(stdout);
    }
    char buf[4096];
    if (fgets(buf, sizeof(buf), stdin) != NULL) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len - 1] == '\n') buf[len - 1] = '\0';
        return sage_rt_string(buf);
    }
    return sage_rt_nil();
}

// File I/O for compiled binaries
SageValue sage_rt_readfile(SageValue path) {
    if (path.type != SAGE_STRING) return sage_rt_nil();
    FILE* f = fopen(path.as.string, "rb");
    if (!f) return sage_rt_nil();
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || sz > 100 * 1024 * 1024) { fclose(f); return sage_rt_nil(); }
    char* buf = (char*)malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return sage_rt_nil(); }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[rd] = '\0';
    SageValue result = sage_rt_string(buf);
    free(buf);
    return result;
}

SageValue sage_rt_writefile(SageValue path, SageValue content) {
    if (path.type != SAGE_STRING || content.type != SAGE_STRING) return sage_rt_nil();
    FILE* f = fopen(path.as.string, "wb");
    if (!f) return sage_rt_nil();
    size_t len = strlen(content.as.string);
    fwrite(content.as.string, 1, len, f);
    fclose(f);
    return sage_rt_number((double)len);
}

// Load weight file: returns array of float arrays (one per CSV line)
// Used by compiled chatbot to load trained model weights
SageValue sage_rt_load_weights(SageValue path) {
    if (path.type != SAGE_STRING) return sage_rt_nil();
    FILE* f = fopen(path.as.string, "r");
    if (!f) return sage_rt_nil();

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(fsize + 1);
    if (!buf) { fclose(f); return sage_rt_nil(); }
    size_t rd = fread(buf, 1, fsize, f);
    fclose(f);
    buf[rd] = '\0';

    SageValue result = sage_rt_array_new(0);

    char* pos = buf;
    while (pos < buf + rd) {
        char* eol = pos;
        while (*eol && *eol != '\n') eol++;

        int nvals = 0;
        if (eol > pos) {
            nvals = 1;
            for (char* p = pos; p < eol; p++) {
                if (*p == ',') nvals++;
            }
        }

        SageValue line_arr = sage_rt_array_new(nvals);
        char* tok = pos;
        for (char* p = pos; p <= eol; p++) {
            if (*p == ',' || p == eol) {
                char saved = *p;
                *p = '\0';
                sage_rt_array_push(line_arr, sage_rt_number(atof(tok)));
                *p = saved;
                tok = p + 1;
            }
        }

        sage_rt_array_push(result, line_arr);
        pos = eol;
        if (*pos == '\n') pos++;
    }

    free(buf);
    return result;
}

SageValue sage_rt_chr(SageValue val) {
    if (val.type != SAGE_NUMBER) return sage_rt_nil();
    int code = (int)val.as.number;
    if (code < 0 || code > 127) return sage_rt_nil();
    char buf[2];
    buf[0] = (char)code;
    buf[1] = '\0';
    return sage_rt_string(buf);
}

SageValue sage_rt_ord(SageValue val) {
    if (val.type != SAGE_STRING || val.as.string == NULL || val.as.string[0] == '\0')
        return sage_rt_nil();
    return sage_rt_number((double)(unsigned char)val.as.string[0]);
}

// ============================================================================
// GPU Runtime Bridge — SageValue wrappers for sgpu_* API
// ============================================================================

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static SageValue sage_dict_get(SageValue dict, const char* key) {
    if (dict.type != SAGE_DICT) return sage_rt_nil();
    SageDict* d = dict.as.dict;
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->keys[i], key) == 0) return d->values[i];
    }
    return sage_rt_nil();
}

static int sage_dict_get_int(SageValue dict, const char* key, int def) {
    SageValue v = sage_dict_get(dict, key);
    if (v.type == SAGE_NUMBER) return (int)v.as.number;
    if (v.type == SAGE_BOOL) return v.as.boolean;
    return def;
}

static double sage_dict_get_num(SageValue dict, const char* key, double def) {
    SageValue v = sage_dict_get(dict, key);
    if (v.type == SAGE_NUMBER) return v.as.number;
    return def;
}

static const char* sage_dict_get_str(SageValue dict, const char* key, const char* def) {
    SageValue v = sage_dict_get(dict, key);
    if (v.type == SAGE_STRING) return v.as.string;
    return def;
}

static SageValue sage_make_dict_wh(int w, int h) {
    SageValue d = sage_rt_dict_new();
    sage_rt_dict_set(d, "width", sage_rt_number((double)w));
    sage_rt_dict_set(d, "height", sage_rt_number((double)h));
    return d;
}

// ---------------------------------------------------------------------------
// ===========================================================================
// ML Native Runtime (matmul, rms_norm, silu, etc.)
// ===========================================================================

// Forward pass: exact same computation as ml_backend.c train_step (without backprop)
SageValue sage_rt_forward_pass(SageValue e, SageValue qw, SageValue kw, SageValue vw,
    SageValue ow, SageValue gw, SageValue uw, SageValue dw,
    SageValue n1, SageValue n2, SageValue fn, SageValue lh,
    SageValue ids_v, SageValue d_v, SageValue ff_v, SageValue V_v, SageValue S_v);

// Helper: extract flat double array from SageValue array
static double* sv_to_doubles(SageValue arr, int* out_count) {
    if (arr.type != SAGE_ARRAY) { *out_count = 0; return NULL; }
    int n = arr.as.array->count;
    double* data = (double*)malloc(sizeof(double) * (n > 0 ? n : 1));
    for (int i = 0; i < n; i++) {
        SageValue v = arr.as.array->elements[i];
        data[i] = (v.type == SAGE_NUMBER) ? v.as.number : 0.0;
    }
    *out_count = n;
    return data;
}

static SageValue doubles_to_sv(const double* data, int n) {
    SageValue arr = sage_rt_array_new(n);
    for (int i = 0; i < n; i++) {
        sage_rt_array_push(arr, sage_rt_number(data[i]));
    }
    return arr;
}

SageValue sage_rt_matmul(SageValue a, SageValue b, SageValue m_v, SageValue k_v, SageValue n_v) {
    int ac, bc;
    double* A = sv_to_doubles(a, &ac);
    double* B = sv_to_doubles(b, &bc);
    int m = (int)(m_v.type == SAGE_NUMBER ? m_v.as.number : 0);
    int k = (int)(k_v.type == SAGE_NUMBER ? k_v.as.number : 0);
    int n = (int)(n_v.type == SAGE_NUMBER ? n_v.as.number : 0);
    if (!A || !B || m <= 0 || k <= 0 || n <= 0) {
        free(A); free(B);
        return sage_rt_nil();
    }
    double* C = (double*)calloc(m * n, sizeof(double));
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            double sum = 0;
            for (int p = 0; p < k; p++) {
                sum += A[i * k + p] * B[p * n + j];
            }
            C[i * n + j] = sum;
        }
    }
    SageValue result = doubles_to_sv(C, m * n);
    free(A); free(B); free(C);
    return result;
}

SageValue sage_rt_rms_norm(SageValue x, SageValue w, SageValue rows_v, SageValue cols_v, SageValue eps_v) {
    int xc, wc;
    double* X = sv_to_doubles(x, &xc);
    double* W = sv_to_doubles(w, &wc);
    int rows = (int)(rows_v.type == SAGE_NUMBER ? rows_v.as.number : 0);
    int cols = (int)(cols_v.type == SAGE_NUMBER ? cols_v.as.number : 0);
    double eps = eps_v.type == SAGE_NUMBER ? eps_v.as.number : 1e-5;
    if (!X || !W || rows <= 0 || cols <= 0) {
        free(X); free(W);
        return sage_rt_nil();
    }
    double* out = (double*)malloc(sizeof(double) * rows * cols);
    for (int i = 0; i < rows; i++) {
        double ss = 0;
        for (int j = 0; j < cols; j++) {
            double v = X[i * cols + j];
            ss += v * v;
        }
        double rms = sqrt(ss / cols + eps);
        for (int j = 0; j < cols; j++) {
            out[i * cols + j] = X[i * cols + j] / rms * W[j];
        }
    }
    SageValue result = doubles_to_sv(out, rows * cols);
    free(X); free(W); free(out);
    return result;
}

SageValue sage_rt_silu(SageValue x) {
    int n;
    double* X = sv_to_doubles(x, &n);
    if (!X) return sage_rt_nil();
    double* out = (double*)malloc(sizeof(double) * n);
    for (int i = 0; i < n; i++) {
        double s = 1.0 / (1.0 + exp(-X[i]));
        out[i] = X[i] * s;
    }
    SageValue result = doubles_to_sv(out, n);
    free(X); free(out);
    return result;
}

SageValue sage_rt_scale(SageValue x, SageValue s) {
    int n;
    double* X = sv_to_doubles(x, &n);
    double scale = s.type == SAGE_NUMBER ? s.as.number : 1.0;
    if (!X) return sage_rt_nil();
    for (int i = 0; i < n; i++) X[i] *= scale;
    SageValue result = doubles_to_sv(X, n);
    free(X);
    return result;
}

SageValue sage_rt_cross_entropy(SageValue logits, SageValue targets, SageValue batch_v, SageValue vocab_v) {
    int lc, tc;
    double* L = sv_to_doubles(logits, &lc);
    double* T = sv_to_doubles(targets, &tc);
    int batch = (int)(batch_v.type == SAGE_NUMBER ? batch_v.as.number : 1);
    int voc = (int)(vocab_v.type == SAGE_NUMBER ? vocab_v.as.number : lc);
    if (!L || !T || voc <= 0) { free(L); free(T); return sage_rt_number(0); }
    double loss = 0;
    for (int i = 0; i < batch; i++) {
        int target = (int)T[i];
        if (target < 0 || target >= voc) target = 0;
        double max_val = L[i * voc];
        for (int j = 1; j < voc; j++) {
            if (L[i * voc + j] > max_val) max_val = L[i * voc + j];
        }
        double sum = 0;
        for (int j = 0; j < voc; j++) {
            sum += exp(L[i * voc + j] - max_val);
        }
        loss += max_val + log(sum) - L[i * voc + target];
    }
    free(L); free(T);
    return sage_rt_number(loss / (batch > 0 ? batch : 1));
}

// Forward pass implementation for LLVM runtime
static void rt_softmax(double* x, int n) {
    double mx = x[0];
    for (int i = 1; i < n; i++) if (x[i] > mx) mx = x[i];
    double s = 0;
    for (int i = 0; i < n; i++) { x[i] = exp(x[i] - mx); s += x[i]; }
    for (int i = 0; i < n; i++) x[i] /= s;
}
static void rt_matmul(const double* A, const double* B, double* C, int m, int k, int n) {
    for (int i = 0; i < m; i++)
        for (int j = 0; j < n; j++) {
            double sum = 0;
            for (int p = 0; p < k; p++) sum += A[i*k+p] * B[p*n+j];
            C[i*n+j] = sum;
        }
}

SageValue sage_rt_forward_pass(SageValue e, SageValue qw_v, SageValue kw_v, SageValue vw_v,
    SageValue ow_v, SageValue gw_v, SageValue uw_v, SageValue dw_v,
    SageValue n1_v, SageValue n2_v, SageValue fn_v, SageValue lh_v,
    SageValue ids_v, SageValue d_v, SageValue ff_v, SageValue V_v, SageValue S_v) {
    int ec,qc,kc,vc,oc,gc2,uc,dc2,n1c,n2c,fnc,lhc,ic;
    double* embed=sv_to_doubles(e,&ec); double* Qw=sv_to_doubles(qw_v,&qc);
    double* Kw=sv_to_doubles(kw_v,&kc); double* Vw=sv_to_doubles(vw_v,&vc);
    double* Ow=sv_to_doubles(ow_v,&oc); double* Gate=sv_to_doubles(gw_v,&gc2);
    double* Up=sv_to_doubles(uw_v,&uc); double* Down=sv_to_doubles(dw_v,&dc2);
    double* N1=sv_to_doubles(n1_v,&n1c); double* N2=sv_to_doubles(n2_v,&n2c);
    double* FN=sv_to_doubles(fn_v,&fnc); double* LH=sv_to_doubles(lh_v,&lhc);
    double* ids=sv_to_doubles(ids_v,&ic);
    int d=(int)(d_v.type==SAGE_NUMBER?d_v.as.number:0);
    int ff=(int)(ff_v.type==SAGE_NUMBER?ff_v.as.number:0);
    int V=(int)(V_v.type==SAGE_NUMBER?V_v.as.number:0);
    int S=(int)(S_v.type==SAGE_NUMBER?S_v.as.number:0);
    if(!embed||d<=0||ff<=0||V<=0||S<=0){
        free(embed);free(Qw);free(Kw);free(Vw);free(Ow);free(Gate);free(Up);free(Down);
        free(N1);free(N2);free(FN);free(LH);free(ids);return sage_rt_nil();
    }
    int SD=S*d, SF=S*ff;
    double* hidden=(double*)calloc(SD,sizeof(double));
    for(int t=0;t<S;t++){int tid=(int)ids[t];if(tid<0||tid>=V)tid=0;
        for(int j=0;j<d;j++)hidden[t*d+j]=embed[tid*d+j];}
    double* nm1=(double*)calloc(SD,sizeof(double));
    for(int t=0;t<S;t++){double ss=0;
        for(int j=0;j<d;j++){double v=hidden[t*d+j];ss+=v*v;}
        double rms=sqrt(ss/d+1e-5);
        for(int j=0;j<d;j++)nm1[t*d+j]=hidden[t*d+j]/rms*N1[j];}
    double* Q=(double*)calloc(SD,sizeof(double));
    double* K=(double*)calloc(SD,sizeof(double));
    double* Vm=(double*)calloc(SD,sizeof(double));
    rt_matmul(nm1,Qw,Q,S,d,d);rt_matmul(nm1,Kw,K,S,d,d);rt_matmul(nm1,Vw,Vm,S,d,d);
    double sc=1.0/sqrt((double)d);
    double* ap=(double*)calloc(S*S,sizeof(double));
    for(int i=0;i<S;i++){
        for(int j=0;j<S;j++){double dot=0;
            for(int k=0;k<d;k++)dot+=Q[i*d+k]*K[j*d+k];
            ap[i*S+j]=(j<=i)?dot*sc:-1e9;}
        rt_softmax(ap+i*S,S);}
    double* ao=(double*)calloc(SD,sizeof(double));
    rt_matmul(ap,Vm,ao,S,S,d);
    double* proj=(double*)calloc(SD,sizeof(double));
    rt_matmul(ao,Ow,proj,S,d,d);
    double* h2=(double*)calloc(SD,sizeof(double));
    for(int i=0;i<SD;i++)h2[i]=hidden[i]+proj[i];
    double* nm2=(double*)calloc(SD,sizeof(double));
    for(int t=0;t<S;t++){double ss=0;
        for(int j=0;j<d;j++){double v=h2[t*d+j];ss+=v*v;}
        double rms=sqrt(ss/d+1e-5);
        for(int j=0;j<d;j++)nm2[t*d+j]=h2[t*d+j]/rms*N2[j];}
    double* go=(double*)calloc(SF,sizeof(double));
    double* uo=(double*)calloc(SF,sizeof(double));
    rt_matmul(nm2,Gate,go,S,d,ff);rt_matmul(nm2,Up,uo,S,d,ff);
    double* gated=(double*)calloc(SF,sizeof(double));
    for(int i=0;i<SF;i++){double s=1.0/(1.0+exp(-go[i]));gated[i]=go[i]*s*uo[i];}
    double* fo=(double*)calloc(SD,sizeof(double));
    rt_matmul(gated,Down,fo,S,ff,d);
    double* h3=(double*)calloc(SD,sizeof(double));
    for(int i=0;i<SD;i++)h3[i]=h2[i]+fo[i];
    double* ln=(double*)calloc(d,sizeof(double));
    {int t=S-1;double ss=0;
     for(int j=0;j<d;j++){double v=h3[t*d+j];ss+=v*v;}
     double rms=sqrt(ss/d+1e-5);
     for(int j=0;j<d;j++)ln[j]=h3[t*d+j]/rms*FN[j];}
    double* logits=(double*)calloc(V,sizeof(double));
    for(int j=0;j<V;j++){double dot=0;for(int k=0;k<d;k++)dot+=ln[k]*LH[k*V+j];logits[j]=dot;}
    SageValue result=doubles_to_sv(logits,V);
    free(embed);free(Qw);free(Kw);free(Vw);free(Ow);free(Gate);free(Up);free(Down);
    free(N1);free(N2);free(FN);free(LH);free(ids);
    free(hidden);free(nm1);free(Q);free(K);free(Vm);free(ap);free(ao);free(proj);
    free(h2);free(nm2);free(go);free(uo);free(gated);free(fo);free(h3);free(ln);free(logits);
    return result;
}

// ---------------------------------------------------------------------------
// Core Lifecycle
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_get_active_backend(void) {
    return sage_rt_number((double)sgpu_get_active_backend());
}

SageValue sage_rt_gpu_has_vulkan(void) {
    return sage_rt_bool(sgpu_has_vulkan());
}

SageValue sage_rt_gpu_has_opengl(void) {
    return sage_rt_bool(sgpu_has_opengl());
}

SageValue sage_rt_gpu_init(SageValue app_name, SageValue validation) {
    const char* name = app_name.type == SAGE_STRING ? app_name.as.string : "SageLang GPU";
    int val = validation.type == SAGE_BOOL ? validation.as.boolean : (validation.type == SAGE_NUMBER ? (int)validation.as.number : 0);
    return sage_rt_bool(sgpu_init(name, val));
}

SageValue sage_rt_gpu_init_opengl(SageValue app_name, SageValue major, SageValue minor) {
    const char* name = app_name.type == SAGE_STRING ? app_name.as.string : "SageLang GPU";
    int ma = major.type == SAGE_NUMBER ? (int)major.as.number : 4;
    int mi = minor.type == SAGE_NUMBER ? (int)minor.as.number : 5;
    return sage_rt_bool(sgpu_init_opengl(name, ma, mi));
}

SageValue sage_rt_gpu_shutdown(void) {
    sgpu_shutdown();
    return sage_rt_nil();
}

SageValue sage_rt_gpu_device_name(void) {
    const char* n = sgpu_device_name();
    return n ? sage_rt_string(n) : sage_rt_nil();
}

SageValue sage_rt_gpu_device_limits(void) {
    // Return basic device info dict in compiled mode
    const char* name = sgpu_device_name();
    SageValue d = sage_rt_dict_new();
    sage_rt_dict_set(d, "device_name", name ? sage_rt_string(name) : sage_rt_nil());
    return d;
}

SageValue sage_rt_gpu_last_error(void) {
    const char* e = sgpu_last_error();
    return e ? sage_rt_string(e) : sage_rt_nil();
}

// ---------------------------------------------------------------------------
// Buffer Operations
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_buffer(SageValue size, SageValue usage, SageValue mem_props) {
    return sage_rt_number((double)sgpu_create_buffer(
        (int)as_num(size), (int)as_num(usage), (int)as_num(mem_props)));
}

SageValue sage_rt_gpu_destroy_buffer(SageValue handle) {
    sgpu_destroy_buffer((int)as_num(handle));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_buffer_upload(SageValue handle, SageValue data) {
    if (data.type != SAGE_ARRAY) return sage_rt_bool(0);
    SageArray* a = data.as.array;
    float* buf = malloc(sizeof(float) * (size_t)a->count);
    if (!buf) return sage_rt_bool(0);
    for (int i = 0; i < a->count; i++) {
        buf[i] = (float)as_num(a->elements[i]);
    }
    int res = sgpu_buffer_upload((int)as_num(handle), buf, a->count);
    free(buf);
    return sage_rt_bool(res);
}

SageValue sage_rt_gpu_buffer_upload_bytes(SageValue handle, SageValue data) {
    if (data.type != SAGE_ARRAY) return sage_rt_bool(0);
    SageArray* a = data.as.array;
    uint8_t* buf = malloc((size_t)a->count);
    if (!buf) return sage_rt_bool(0);
    for (int i = 0; i < a->count; i++) {
        buf[i] = (uint8_t)(int)as_num(a->elements[i]);
    }
    int res = sgpu_buffer_upload_bytes((int)as_num(handle), buf, a->count);
    free(buf);
    return sage_rt_bool(res);
}

SageValue sage_rt_gpu_buffer_download(SageValue handle, SageValue max_count) {
    int mc = (int)as_num(max_count);
    if (mc <= 0) mc = 1024;
    float* buf = malloc(sizeof(float) * (size_t)mc);
    if (!buf) return sage_rt_array_new(0);
    int got = sgpu_buffer_download((int)as_num(handle), buf, mc);
    SageValue arr = sage_rt_array_new(got > 0 ? got : 0);
    for (int i = 0; i < got; i++) {
        sage_rt_array_push(arr, sage_rt_number((double)buf[i]));
    }
    free(buf);
    return arr;
}

SageValue sage_rt_gpu_buffer_size(SageValue handle) {
    return sage_rt_number((double)sgpu_buffer_size((int)as_num(handle)));
}

// ---------------------------------------------------------------------------
// Image Operations
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_image(SageValue width, SageValue height, SageValue format,
                                    SageValue usage, SageValue img_type) {
    return sage_rt_number((double)sgpu_create_image(
        (int)as_num(width), (int)as_num(height), (int)as_num(format),
        (int)as_num(usage), (int)as_num(img_type)));
}

SageValue sage_rt_gpu_create_image_3d(SageValue width, SageValue height, SageValue depth,
                                       SageValue format, SageValue usage) {
    return sage_rt_number((double)sgpu_create_image_3d(
        (int)as_num(width), (int)as_num(height), (int)as_num(depth),
        (int)as_num(format), (int)as_num(usage)));
}

SageValue sage_rt_gpu_destroy_image(SageValue handle) {
    sgpu_destroy_image((int)as_num(handle));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_image_dims(SageValue handle) {
    int w = 0, h = 0, d = 0;
    sgpu_image_dims((int)as_num(handle), &w, &h, &d);
    SageValue dict = sage_rt_dict_new();
    sage_rt_dict_set(dict, "width", sage_rt_number((double)w));
    sage_rt_dict_set(dict, "height", sage_rt_number((double)h));
    sage_rt_dict_set(dict, "depth", sage_rt_number((double)d));
    return dict;
}

// ---------------------------------------------------------------------------
// Sampler
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_sampler(SageValue min_filter, SageValue mag_filter,
                                      SageValue address_mode) {
    return sage_rt_number((double)sgpu_create_sampler(
        (int)as_num(min_filter), (int)as_num(mag_filter), (int)as_num(address_mode)));
}

SageValue sage_rt_gpu_create_sampler_advanced(SageValue min_filter, SageValue mag_filter,
                                               SageValue address_mode, SageValue mip_mode,
                                               SageValue max_anisotropy, SageValue compare_op) {
    return sage_rt_number((double)sgpu_create_sampler_advanced(
        (int)as_num(min_filter), (int)as_num(mag_filter), (int)as_num(address_mode),
        (int)as_num(mip_mode), (float)as_num(max_anisotropy), (int)as_num(compare_op)));
}

SageValue sage_rt_gpu_destroy_sampler(SageValue handle) {
    sgpu_destroy_sampler((int)as_num(handle));
    return sage_rt_nil();
}

// ---------------------------------------------------------------------------
// Shaders
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_load_shader(SageValue path, SageValue stage) {
    const char* p = path.type == SAGE_STRING ? path.as.string : "";
    return sage_rt_number((double)sgpu_load_shader(p, (int)as_num(stage)));
}

SageValue sage_rt_gpu_load_shader_glsl(SageValue source, SageValue stage) {
    const char* s = source.type == SAGE_STRING ? source.as.string : "";
    return sage_rt_number((double)sgpu_load_shader_glsl(s, (int)as_num(stage)));
}

SageValue sage_rt_gpu_reload_shader(SageValue handle, SageValue path) {
    const char* p = path.type == SAGE_STRING ? path.as.string : "";
    return sage_rt_number((double)sgpu_reload_shader((int)as_num(handle), p));
}

SageValue sage_rt_gpu_destroy_shader(SageValue handle) {
    sgpu_destroy_shader((int)as_num(handle));
    return sage_rt_nil();
}

// ---------------------------------------------------------------------------
// Descriptors
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_descriptor_layout(SageValue bindings_arr) {
    if (bindings_arr.type != SAGE_ARRAY) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    SageArray* a = bindings_arr.as.array;
    SageGPUDescBinding* bindings = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(SageGPUDescBinding));
    if (!bindings) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    for (int i = 0; i < a->count; i++) {
        SageValue item = a->elements[i];
        bindings[i].binding = sage_dict_get_int(item, "binding", 0);
        bindings[i].type    = sage_dict_get_int(item, "type", 0);
        bindings[i].stage   = sage_dict_get_int(item, "stage", SGPU_STAGE_ALL);
        bindings[i].count   = sage_dict_get_int(item, "count", 1);
    }
    int h = sgpu_create_descriptor_layout(bindings, a->count);
    free(bindings);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_create_descriptor_pool(SageValue max_sets, SageValue type_counts_arr) {
    if (type_counts_arr.type != SAGE_ARRAY) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    SageArray* a = type_counts_arr.as.array;
    int* tc = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(int));
    if (!tc) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    for (int i = 0; i < a->count; i++) {
        tc[i] = (int)as_num(a->elements[i]);
    }
    int h = sgpu_create_descriptor_pool((int)as_num(max_sets), tc, a->count);
    free(tc);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_allocate_descriptor_set(SageValue pool, SageValue layout) {
    return sage_rt_number((double)sgpu_allocate_descriptor_set(
        (int)as_num(pool), (int)as_num(layout)));
}

SageValue sage_rt_gpu_allocate_descriptor_sets(SageValue pool, SageValue layout, SageValue count) {
    int c = (int)as_num(count);
    if (c <= 0) return sage_rt_array_new(0);
    int* out = calloc((size_t)c, sizeof(int));
    if (!out) return sage_rt_array_new(0);
    int res = sgpu_allocate_descriptor_sets((int)as_num(pool), (int)as_num(layout), c, out);
    SageValue arr = sage_rt_array_new(c);
    if (res) {
        for (int i = 0; i < c; i++) {
            sage_rt_array_push(arr, sage_rt_number((double)out[i]));
        }
    }
    free(out);
    return arr;
}

SageValue sage_rt_gpu_update_descriptor(SageValue set, SageValue binding,
                                         SageValue type, SageValue resource_handle) {
    sgpu_update_descriptor((int)as_num(set), (int)as_num(binding),
                           (int)as_num(type), (int)as_num(resource_handle));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_update_descriptor_image(SageValue set, SageValue binding,
                                               SageValue type, SageValue image,
                                               SageValue sampler) {
    sgpu_update_descriptor_image((int)as_num(set), (int)as_num(binding),
                                 (int)as_num(type), (int)as_num(image),
                                 (int)as_num(sampler));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_update_descriptor_range(SageValue set, SageValue binding,
                                               SageValue type, SageValue handles_arr) {
    if (handles_arr.type != SAGE_ARRAY) return sage_rt_nil();
    SageArray* a = handles_arr.as.array;
    int* handles = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(int));
    if (!handles) return sage_rt_nil();
    for (int i = 0; i < a->count; i++) {
        handles[i] = (int)as_num(a->elements[i]);
    }
    sgpu_update_descriptor_range((int)as_num(set), (int)as_num(binding),
                                 (int)as_num(type), handles, a->count);
    free(handles);
    return sage_rt_nil();
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_pipeline_layout(SageValue desc_layouts_arr,
                                              SageValue push_constant_size,
                                              SageValue push_constant_stages) {
    int layout_count = 0;
    int* layouts = NULL;
    if (desc_layouts_arr.type == SAGE_ARRAY) {
        SageArray* a = desc_layouts_arr.as.array;
        layout_count = a->count;
        layouts = calloc((size_t)(layout_count > 0 ? layout_count : 1), sizeof(int));
        if (layouts) {
            for (int i = 0; i < layout_count; i++) {
                layouts[i] = (int)as_num(a->elements[i]);
            }
        }
    }
    int h = sgpu_create_pipeline_layout(layouts, layout_count,
                                        (int)as_num(push_constant_size),
                                        (int)as_num(push_constant_stages));
    free(layouts);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_create_compute_pipeline(SageValue layout, SageValue shader) {
    return sage_rt_number((double)sgpu_create_compute_pipeline(
        (int)as_num(layout), (int)as_num(shader)));
}

SageValue sage_rt_gpu_create_graphics_pipeline(SageValue config) {
    if (config.type != SAGE_DICT) return sage_rt_number((double)SGPU_INVALID_HANDLE);

    SageGPUGraphicsPipelineConfig cfg;
    memset(&cfg, 0, sizeof(cfg));

    cfg.layout          = sage_dict_get_int(config, "layout", -1);
    cfg.render_pass     = sage_dict_get_int(config, "render_pass", -1);
    cfg.vertex_shader   = sage_dict_get_int(config, "vertex_shader", -1);
    cfg.fragment_shader = sage_dict_get_int(config, "fragment_shader", -1);
    cfg.topology        = sage_dict_get_int(config, "topology", SGPU_TOPO_TRIANGLE_LIST);
    cfg.polygon_mode    = sage_dict_get_int(config, "polygon_mode", SGPU_POLY_FILL);
    cfg.cull_mode       = sage_dict_get_int(config, "cull_mode", SGPU_CULL_NONE);
    cfg.front_face      = sage_dict_get_int(config, "front_face", SGPU_FRONT_CCW);
    cfg.depth_test      = sage_dict_get_int(config, "depth_test", 0);
    cfg.depth_write     = sage_dict_get_int(config, "depth_write", 0);
    cfg.blend           = sage_dict_get_int(config, "blend", 0);
    cfg.subpass         = sage_dict_get_int(config, "subpass", 0);
    cfg.color_attachment_count = sage_dict_get_int(config, "color_attachment_count", 1);

    // Vertex bindings
    SageValue vb = sage_dict_get(config, "vertex_bindings");
    if (vb.type == SAGE_ARRAY && vb.as.array->count > 0) {
        SageArray* a = vb.as.array;
        cfg.vertex_binding_count = a->count;
        cfg.vertex_bindings = calloc((size_t)a->count, sizeof(SageGPUVertexBinding));
        for (int i = 0; i < a->count; i++) {
            SageValue item = a->elements[i];
            cfg.vertex_bindings[i].binding = sage_dict_get_int(item, "binding", 0);
            cfg.vertex_bindings[i].stride  = sage_dict_get_int(item, "stride", 0);
            cfg.vertex_bindings[i].rate    = sage_dict_get_int(item, "rate", SGPU_INPUT_RATE_VERTEX);
        }
    }

    // Vertex attribs
    SageValue va = sage_dict_get(config, "vertex_attribs");
    if (va.type == SAGE_ARRAY && va.as.array->count > 0) {
        SageArray* a = va.as.array;
        cfg.vertex_attrib_count = a->count;
        cfg.vertex_attribs = calloc((size_t)a->count, sizeof(SageGPUVertexAttrib));
        for (int i = 0; i < a->count; i++) {
            SageValue item = a->elements[i];
            cfg.vertex_attribs[i].location = sage_dict_get_int(item, "location", 0);
            cfg.vertex_attribs[i].binding  = sage_dict_get_int(item, "binding", 0);
            cfg.vertex_attribs[i].format   = sage_dict_get_int(item, "format", SGPU_ATTR_FLOAT);
            cfg.vertex_attribs[i].offset   = sage_dict_get_int(item, "offset", 0);
        }
    }

    int h = sgpu_create_graphics_pipeline(&cfg);
    free(cfg.vertex_bindings);
    free(cfg.vertex_attribs);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_destroy_pipeline(SageValue handle) {
    sgpu_destroy_pipeline((int)as_num(handle));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_create_pipeline_cache(void) {
    return sage_rt_number((double)sgpu_create_pipeline_cache());
}

// ---------------------------------------------------------------------------
// Render Pass & Framebuffer
// ---------------------------------------------------------------------------

static SageGPURenderPassAttachment* extract_attachments(SageValue arr, int* out_count) {
    *out_count = 0;
    if (arr.type != SAGE_ARRAY || arr.as.array->count == 0) return NULL;
    SageArray* a = arr.as.array;
    *out_count = a->count;
    SageGPURenderPassAttachment* att = calloc((size_t)a->count, sizeof(SageGPURenderPassAttachment));
    if (!att) { *out_count = 0; return NULL; }
    for (int i = 0; i < a->count; i++) {
        SageValue item = a->elements[i];
        att[i].format         = sage_dict_get_int(item, "format", SGPU_FORMAT_RGBA8);
        att[i].load_op        = sage_dict_get_int(item, "load_op", SGPU_LOAD_CLEAR);
        att[i].store_op       = sage_dict_get_int(item, "store_op", SGPU_STORE_STORE);
        att[i].initial_layout = sage_dict_get_int(item, "initial_layout", SGPU_LAYOUT_UNDEFINED);
        att[i].final_layout   = sage_dict_get_int(item, "final_layout", SGPU_LAYOUT_PRESENT);
    }
    return att;
}

SageValue sage_rt_gpu_create_render_pass(SageValue attachments, SageValue has_depth) {
    int count = 0;
    SageGPURenderPassAttachment* att = extract_attachments(attachments, &count);
    int h = sgpu_create_render_pass(att, count, (int)as_num(has_depth));
    free(att);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_create_render_pass_mrt(SageValue attachments, SageValue has_depth) {
    int count = 0;
    SageGPURenderPassAttachment* att = extract_attachments(attachments, &count);
    int h = sgpu_create_render_pass_mrt(att, count, (int)as_num(has_depth));
    free(att);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_destroy_render_pass(SageValue handle) {
    sgpu_destroy_render_pass((int)as_num(handle));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_create_framebuffer(SageValue render_pass, SageValue image_handles_arr,
                                          SageValue width, SageValue height) {
    int count = 0;
    int* handles = NULL;
    if (image_handles_arr.type == SAGE_ARRAY) {
        SageArray* a = image_handles_arr.as.array;
        count = a->count;
        handles = calloc((size_t)(count > 0 ? count : 1), sizeof(int));
        if (handles) {
            for (int i = 0; i < count; i++) {
                handles[i] = (int)as_num(a->elements[i]);
            }
        }
    }
    int h = sgpu_create_framebuffer((int)as_num(render_pass), handles, count,
                                    (int)as_num(width), (int)as_num(height));
    free(handles);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_destroy_framebuffer(SageValue handle) {
    sgpu_destroy_framebuffer((int)as_num(handle));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_create_depth_buffer(SageValue width, SageValue height, SageValue format) {
    return sage_rt_number((double)sgpu_create_depth_buffer(
        (int)as_num(width), (int)as_num(height), (int)as_num(format)));
}

// ---------------------------------------------------------------------------
// Command Buffers
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_command_pool(SageValue queue_family) {
    return sage_rt_number((double)sgpu_create_command_pool((int)as_num(queue_family)));
}

SageValue sage_rt_gpu_create_command_buffer(SageValue pool) {
    return sage_rt_number((double)sgpu_create_command_buffer((int)as_num(pool)));
}

SageValue sage_rt_gpu_create_secondary_command_buffer(SageValue pool) {
    return sage_rt_number((double)sgpu_create_secondary_command_buffer((int)as_num(pool)));
}

SageValue sage_rt_gpu_begin_commands(SageValue cmd) {
    return sage_rt_bool(sgpu_begin_commands((int)as_num(cmd)));
}

SageValue sage_rt_gpu_begin_secondary(SageValue cmd, SageValue render_pass,
                                       SageValue framebuffer, SageValue subpass) {
    return sage_rt_bool(sgpu_begin_secondary(
        (int)as_num(cmd), (int)as_num(render_pass),
        (int)as_num(framebuffer), (int)as_num(subpass)));
}

SageValue sage_rt_gpu_end_commands(SageValue cmd) {
    return sage_rt_bool(sgpu_end_commands((int)as_num(cmd)));
}

// ---------------------------------------------------------------------------
// Command Recording
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_cmd_bind_compute_pipeline(SageValue cmd, SageValue pipeline) {
    sgpu_cmd_bind_compute_pipeline((int)as_num(cmd), (int)as_num(pipeline));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_bind_graphics_pipeline(SageValue cmd, SageValue pipeline) {
    sgpu_cmd_bind_graphics_pipeline((int)as_num(cmd), (int)as_num(pipeline));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_bind_descriptor_set(SageValue cmd, SageValue pipeline_layout,
                                               SageValue set, SageValue bind_point) {
    sgpu_cmd_bind_descriptor_set((int)as_num(cmd), (int)as_num(pipeline_layout),
                                 (int)as_num(set), (int)as_num(bind_point));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_dispatch(SageValue cmd, SageValue gx, SageValue gy, SageValue gz) {
    sgpu_cmd_dispatch((int)as_num(cmd), (int)as_num(gx), (int)as_num(gy), (int)as_num(gz));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_dispatch_indirect(SageValue cmd, SageValue buffer, SageValue offset) {
    sgpu_cmd_dispatch_indirect((int)as_num(cmd), (int)as_num(buffer), (int)as_num(offset));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_push_constants(SageValue cmd, SageValue layout,
                                          SageValue stages, SageValue data_arr) {
    if (data_arr.type != SAGE_ARRAY) return sage_rt_nil();
    SageArray* a = data_arr.as.array;
    float* buf = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(float));
    if (!buf) return sage_rt_nil();
    for (int i = 0; i < a->count; i++) {
        buf[i] = (float)as_num(a->elements[i]);
    }
    sgpu_cmd_push_constants((int)as_num(cmd), (int)as_num(layout),
                            (int)as_num(stages), buf, a->count);
    free(buf);
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_begin_render_pass(SageValue cmd, SageValue render_pass,
                                             SageValue framebuffer, SageValue w, SageValue h,
                                             SageValue r, SageValue g, SageValue b, SageValue a) {
    sgpu_cmd_begin_render_pass((int)as_num(cmd), (int)as_num(render_pass),
                               (int)as_num(framebuffer),
                               (int)as_num(w), (int)as_num(h),
                               (float)as_num(r), (float)as_num(g),
                               (float)as_num(b), (float)as_num(a));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_end_render_pass(SageValue cmd) {
    sgpu_cmd_end_render_pass((int)as_num(cmd));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_draw(SageValue cmd, SageValue vertex_count,
                                SageValue instance_count, SageValue first_vertex,
                                SageValue first_instance) {
    sgpu_cmd_draw((int)as_num(cmd), (int)as_num(vertex_count),
                  (int)as_num(instance_count), (int)as_num(first_vertex),
                  (int)as_num(first_instance));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_draw_indexed(SageValue cmd, SageValue index_count,
                                        SageValue instance_count, SageValue first_index,
                                        SageValue vertex_offset, SageValue first_instance) {
    sgpu_cmd_draw_indexed((int)as_num(cmd), (int)as_num(index_count),
                          (int)as_num(instance_count), (int)as_num(first_index),
                          (int)as_num(vertex_offset), (int)as_num(first_instance));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_draw_indirect(SageValue cmd, SageValue buffer,
                                         SageValue offset, SageValue draw_count,
                                         SageValue stride) {
    sgpu_cmd_draw_indirect((int)as_num(cmd), (int)as_num(buffer),
                           (int)as_num(offset), (int)as_num(draw_count),
                           (int)as_num(stride));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_draw_indexed_indirect(SageValue cmd, SageValue buffer,
                                                 SageValue offset, SageValue draw_count,
                                                 SageValue stride) {
    sgpu_cmd_draw_indexed_indirect((int)as_num(cmd), (int)as_num(buffer),
                                   (int)as_num(offset), (int)as_num(draw_count),
                                   (int)as_num(stride));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_bind_vertex_buffer(SageValue cmd, SageValue buffer) {
    sgpu_cmd_bind_vertex_buffer((int)as_num(cmd), (int)as_num(buffer));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_bind_vertex_buffers(SageValue cmd, SageValue buffers_arr) {
    if (buffers_arr.type != SAGE_ARRAY) return sage_rt_nil();
    SageArray* a = buffers_arr.as.array;
    int* bufs = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(int));
    if (!bufs) return sage_rt_nil();
    for (int i = 0; i < a->count; i++) {
        bufs[i] = (int)as_num(a->elements[i]);
    }
    sgpu_cmd_bind_vertex_buffers((int)as_num(cmd), bufs, a->count);
    free(bufs);
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_bind_index_buffer(SageValue cmd, SageValue buffer) {
    sgpu_cmd_bind_index_buffer((int)as_num(cmd), (int)as_num(buffer));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_set_viewport(SageValue cmd, SageValue x, SageValue y,
                                        SageValue w, SageValue h,
                                        SageValue min_d, SageValue max_d) {
    sgpu_cmd_set_viewport((int)as_num(cmd),
                          (float)as_num(x), (float)as_num(y),
                          (float)as_num(w), (float)as_num(h),
                          (float)as_num(min_d), (float)as_num(max_d));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_set_scissor(SageValue cmd, SageValue x, SageValue y,
                                       SageValue w, SageValue h) {
    sgpu_cmd_set_scissor((int)as_num(cmd), (int)as_num(x), (int)as_num(y),
                         (int)as_num(w), (int)as_num(h));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_pipeline_barrier(SageValue cmd, SageValue src_stage,
                                            SageValue dst_stage, SageValue src_access,
                                            SageValue dst_access) {
    sgpu_cmd_pipeline_barrier((int)as_num(cmd), (int)as_num(src_stage),
                              (int)as_num(dst_stage), (int)as_num(src_access),
                              (int)as_num(dst_access));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_image_barrier(SageValue cmd, SageValue image,
                                         SageValue old_layout, SageValue new_layout,
                                         SageValue src_stage, SageValue dst_stage,
                                         SageValue src_access, SageValue dst_access) {
    sgpu_cmd_image_barrier((int)as_num(cmd), (int)as_num(image),
                           (int)as_num(old_layout), (int)as_num(new_layout),
                           (int)as_num(src_stage), (int)as_num(dst_stage),
                           (int)as_num(src_access), (int)as_num(dst_access));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_copy_buffer(SageValue cmd, SageValue src, SageValue dst,
                                       SageValue size) {
    sgpu_cmd_copy_buffer((int)as_num(cmd), (int)as_num(src),
                         (int)as_num(dst), (int)as_num(size));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_copy_buffer_to_image(SageValue cmd, SageValue buffer,
                                                SageValue image, SageValue w, SageValue h) {
    sgpu_cmd_copy_buffer_to_image((int)as_num(cmd), (int)as_num(buffer),
                                  (int)as_num(image), (int)as_num(w), (int)as_num(h));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_execute_commands(SageValue cmd, SageValue secondary_cmds_arr) {
    if (secondary_cmds_arr.type != SAGE_ARRAY) return sage_rt_nil();
    SageArray* a = secondary_cmds_arr.as.array;
    int* cmds = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(int));
    if (!cmds) return sage_rt_nil();
    for (int i = 0; i < a->count; i++) {
        cmds[i] = (int)as_num(a->elements[i]);
    }
    sgpu_cmd_execute_commands((int)as_num(cmd), cmds, a->count);
    free(cmds);
    return sage_rt_nil();
}

SageValue sage_rt_gpu_cmd_queue_transfer_barrier(SageValue cmd, SageValue buffer,
                                                  SageValue src_family, SageValue dst_family) {
    sgpu_cmd_queue_transfer_barrier((int)as_num(cmd), (int)as_num(buffer),
                                    (int)as_num(src_family), (int)as_num(dst_family));
    return sage_rt_nil();
}

// ---------------------------------------------------------------------------
// Synchronization
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_fence(SageValue signaled) {
    return sage_rt_number((double)sgpu_create_fence((int)as_num(signaled)));
}

SageValue sage_rt_gpu_wait_fence(SageValue fence, SageValue timeout_seconds) {
    return sage_rt_bool(sgpu_wait_fence((int)as_num(fence), as_num(timeout_seconds)));
}

SageValue sage_rt_gpu_reset_fence(SageValue fence) {
    sgpu_reset_fence((int)as_num(fence));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_destroy_fence(SageValue fence) {
    sgpu_destroy_fence((int)as_num(fence));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_create_semaphore(void) {
    return sage_rt_number((double)sgpu_create_semaphore());
}

SageValue sage_rt_gpu_destroy_semaphore(SageValue sem) {
    sgpu_destroy_semaphore((int)as_num(sem));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_submit(SageValue cmd, SageValue fence) {
    return sage_rt_bool(sgpu_submit((int)as_num(cmd), (int)as_num(fence)));
}

SageValue sage_rt_gpu_submit_compute(SageValue cmd, SageValue fence) {
    return sage_rt_bool(sgpu_submit_compute((int)as_num(cmd), (int)as_num(fence)));
}

SageValue sage_rt_gpu_submit_with_sync(SageValue cmd, SageValue wait_sem,
                                        SageValue signal_sem, SageValue fence) {
    return sage_rt_bool(sgpu_submit_with_sync(
        (int)as_num(cmd), (int)as_num(wait_sem),
        (int)as_num(signal_sem), (int)as_num(fence)));
}

SageValue sage_rt_gpu_queue_wait_idle(void) {
    sgpu_queue_wait_idle();
    return sage_rt_nil();
}

SageValue sage_rt_gpu_device_wait_idle(void) {
    sgpu_device_wait_idle();
    return sage_rt_nil();
}

// ---------------------------------------------------------------------------
// Window & Swapchain
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_window(SageValue width, SageValue height, SageValue title) {
    const char* t = title.type == SAGE_STRING ? title.as.string : "SageLang GPU";
    return sage_rt_bool(sgpu_create_window((int)as_num(width), (int)as_num(height), t));
}

SageValue sage_rt_gpu_destroy_window(void) {
    sgpu_destroy_window();
    return sage_rt_nil();
}

SageValue sage_rt_gpu_window_should_close(void) {
    return sage_rt_bool(sgpu_window_should_close());
}

SageValue sage_rt_gpu_poll_events(void) {
    sgpu_poll_events();
    return sage_rt_nil();
}

SageValue sage_rt_gpu_init_windowed(SageValue title, SageValue width, SageValue height,
                                     SageValue validation) {
    const char* t = title.type == SAGE_STRING ? title.as.string : "SageLang GPU";
    int val = validation.type == SAGE_BOOL ? validation.as.boolean : (int)as_num(validation);
    return sage_rt_bool(sgpu_init_windowed(t, (int)as_num(width), (int)as_num(height), val));
}

SageValue sage_rt_gpu_init_opengl_windowed(SageValue title, SageValue width, SageValue height,
                                            SageValue major, SageValue minor) {
    const char* t = title.type == SAGE_STRING ? title.as.string : "SageLang GPU";
    return sage_rt_bool(sgpu_init_opengl_windowed(
        t, (int)as_num(width), (int)as_num(height),
        (int)as_num(major), (int)as_num(minor)));
}

SageValue sage_rt_gpu_shutdown_windowed(void) {
    sgpu_shutdown_windowed();
    return sage_rt_nil();
}

SageValue sage_rt_gpu_swapchain_image_count(void) {
    return sage_rt_number((double)sgpu_swapchain_image_count());
}

SageValue sage_rt_gpu_swapchain_format(void) {
    return sage_rt_number((double)sgpu_swapchain_format());
}

SageValue sage_rt_gpu_swapchain_extent(void) {
    int w = 0, h = 0;
    sgpu_swapchain_extent(&w, &h);
    return sage_make_dict_wh(w, h);
}

SageValue sage_rt_gpu_acquire_next_image(SageValue semaphore) {
    int image_index = -1;
    int ok = sgpu_acquire_next_image((int)as_num(semaphore), &image_index);
    SageValue dict = sage_rt_dict_new();
    sage_rt_dict_set(dict, "ok", sage_rt_bool(ok));
    sage_rt_dict_set(dict, "image_index", sage_rt_number((double)image_index));
    return dict;
}

SageValue sage_rt_gpu_present(SageValue semaphore, SageValue image_index) {
    return sage_rt_bool(sgpu_present((int)as_num(semaphore), (int)as_num(image_index)));
}

SageValue sage_rt_gpu_create_swapchain_framebuffers(SageValue render_pass) {
    int handles[16];
    int count = sgpu_create_swapchain_framebuffers((int)as_num(render_pass), handles, 16);
    SageValue arr = sage_rt_array_new(count > 0 ? count : 0);
    for (int i = 0; i < count; i++) {
        sage_rt_array_push(arr, sage_rt_number((double)handles[i]));
    }
    return arr;
}

SageValue sage_rt_gpu_create_swapchain_framebuffers_depth(SageValue render_pass,
                                                           SageValue depth_image) {
    int handles[16];
    int count = sgpu_create_swapchain_framebuffers_depth(
        (int)as_num(render_pass), (int)as_num(depth_image), handles, 16);
    SageValue arr = sage_rt_array_new(count > 0 ? count : 0);
    for (int i = 0; i < count; i++) {
        sage_rt_array_push(arr, sage_rt_number((double)handles[i]));
    }
    return arr;
}

SageValue sage_rt_gpu_recreate_swapchain(void) {
    return sage_rt_bool(sgpu_recreate_swapchain());
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_key_pressed(SageValue key) {
    return sage_rt_bool(sgpu_key_pressed((int)as_num(key)));
}

SageValue sage_rt_gpu_key_down(SageValue key) {
    return sage_rt_bool(sgpu_key_down((int)as_num(key)));
}

SageValue sage_rt_gpu_key_just_pressed(SageValue key) {
    return sage_rt_bool(sgpu_key_just_pressed((int)as_num(key)));
}

SageValue sage_rt_gpu_key_just_released(SageValue key) {
    return sage_rt_bool(sgpu_key_just_released((int)as_num(key)));
}

SageValue sage_rt_gpu_mouse_pos(void) {
    double x = 0.0, y = 0.0;
    sgpu_mouse_pos(&x, &y);
    SageValue dict = sage_rt_dict_new();
    sage_rt_dict_set(dict, "x", sage_rt_number(x));
    sage_rt_dict_set(dict, "y", sage_rt_number(y));
    return dict;
}

SageValue sage_rt_gpu_mouse_button(SageValue button) {
    return sage_rt_bool(sgpu_mouse_button((int)as_num(button)));
}

SageValue sage_rt_gpu_mouse_just_pressed(SageValue button) {
    return sage_rt_bool(sgpu_mouse_just_pressed((int)as_num(button)));
}

SageValue sage_rt_gpu_mouse_just_released(SageValue button) {
    return sage_rt_bool(sgpu_mouse_just_released((int)as_num(button)));
}

SageValue sage_rt_gpu_mouse_delta(void) {
    double dx = 0.0, dy = 0.0;
    sgpu_mouse_delta(&dx, &dy);
    SageValue dict = sage_rt_dict_new();
    sage_rt_dict_set(dict, "dx", sage_rt_number(dx));
    sage_rt_dict_set(dict, "dy", sage_rt_number(dy));
    return dict;
}

SageValue sage_rt_gpu_scroll_delta(void) {
    double dx = 0.0, dy = 0.0;
    sgpu_scroll_delta(&dx, &dy);
    SageValue dict = sage_rt_dict_new();
    sage_rt_dict_set(dict, "dx", sage_rt_number(dx));
    sage_rt_dict_set(dict, "dy", sage_rt_number(dy));
    return dict;
}

SageValue sage_rt_gpu_set_cursor_mode(SageValue mode) {
    sgpu_set_cursor_mode((int)as_num(mode));
    return sage_rt_nil();
}

SageValue sage_rt_gpu_get_time(void) {
    return sage_rt_number(sgpu_get_time());
}

SageValue sage_rt_gpu_window_size(void) {
    int w = 0, h = 0;
    sgpu_window_size(&w, &h);
    return sage_make_dict_wh(w, h);
}

SageValue sage_rt_gpu_set_title(SageValue title) {
    const char* t = title.type == SAGE_STRING ? title.as.string : "";
    sgpu_set_title(t);
    return sage_rt_nil();
}

SageValue sage_rt_gpu_window_resized(void) {
    return sage_rt_bool(sgpu_window_resized());
}

SageValue sage_rt_gpu_update_input(void) {
    sgpu_update_input();
    return sage_rt_nil();
}

SageValue sage_rt_gpu_text_input_available(void) {
    return sage_rt_bool(sgpu_text_input_available());
}

SageValue sage_rt_gpu_text_input_read(void) {
    return sage_rt_number((double)sgpu_text_input_read());
}

// ---------------------------------------------------------------------------
// Texture Loading
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_load_texture(SageValue path, SageValue gen_mipmaps,
                                    SageValue filter, SageValue address) {
    const char* p = path.type == SAGE_STRING ? path.as.string : "";
    return sage_rt_number((double)sgpu_load_texture(
        p, (int)as_num(gen_mipmaps), (int)as_num(filter), (int)as_num(address)));
}

SageValue sage_rt_gpu_texture_dims(SageValue handle) {
    int w = 0, h = 0;
    sgpu_texture_dims((int)as_num(handle), &w, &h);
    return sage_make_dict_wh(w, h);
}

SageValue sage_rt_gpu_generate_mipmaps(SageValue image) {
    return sage_rt_bool(sgpu_generate_mipmaps((int)as_num(image)));
}

SageValue sage_rt_gpu_create_cubemap(SageValue face_paths_arr) {
    if (face_paths_arr.type != SAGE_ARRAY) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    SageArray* a = face_paths_arr.as.array;
    const char** paths = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(const char*));
    if (!paths) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    for (int i = 0; i < a->count; i++) {
        paths[i] = a->elements[i].type == SAGE_STRING ? a->elements[i].as.string : "";
    }
    int h = sgpu_create_cubemap(paths, a->count);
    free(paths);
    return sage_rt_number((double)h);
}

// ---------------------------------------------------------------------------
// Upload Helpers
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_upload_device_local(SageValue data_arr, SageValue usage) {
    if (data_arr.type != SAGE_ARRAY) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    SageArray* a = data_arr.as.array;
    float* buf = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(float));
    if (!buf) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    for (int i = 0; i < a->count; i++) {
        buf[i] = (float)as_num(a->elements[i]);
    }
    int h = sgpu_upload_device_local(buf, a->count, (int)as_num(usage));
    free(buf);
    return sage_rt_number((double)h);
}

SageValue sage_rt_gpu_upload_bytes(SageValue data_arr, SageValue usage) {
    if (data_arr.type != SAGE_ARRAY) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    SageArray* a = data_arr.as.array;
    uint8_t* buf = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(uint8_t));
    if (!buf) return sage_rt_number((double)SGPU_INVALID_HANDLE);
    for (int i = 0; i < a->count; i++) {
        buf[i] = (uint8_t)(int)as_num(a->elements[i]);
    }
    int h = sgpu_upload_bytes(buf, a->count, (int)as_num(usage));
    free(buf);
    return sage_rt_number((double)h);
}

// ---------------------------------------------------------------------------
// Uniform Buffers
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_uniform_buffer(SageValue size) {
    return sage_rt_number((double)sgpu_create_uniform_buffer((int)as_num(size)));
}

SageValue sage_rt_gpu_update_uniform(SageValue handle, SageValue data_arr) {
    if (data_arr.type != SAGE_ARRAY) return sage_rt_bool(0);
    SageArray* a = data_arr.as.array;
    float* buf = calloc((size_t)(a->count > 0 ? a->count : 1), sizeof(float));
    if (!buf) return sage_rt_bool(0);
    for (int i = 0; i < a->count; i++) {
        buf[i] = (float)as_num(a->elements[i]);
    }
    int res = sgpu_update_uniform((int)as_num(handle), buf, a->count);
    free(buf);
    return sage_rt_bool(res);
}

// ---------------------------------------------------------------------------
// Offscreen Rendering
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_create_offscreen_target(SageValue width, SageValue height,
                                               SageValue format, SageValue usage) {
    return sage_rt_number((double)sgpu_create_offscreen_target(
        (int)as_num(width), (int)as_num(height),
        (int)as_num(format), (int)as_num(usage)));
}

// ---------------------------------------------------------------------------
// Screenshot
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_screenshot(SageValue max_size) {
    int ms = (int)as_num(max_size);
    if (ms <= 0) ms = 4096 * 4096 * 4;
    uint8_t* pixels = malloc((size_t)ms);
    if (!pixels) return sage_rt_nil();
    int w = 0, h = 0;
    int ok = sgpu_screenshot(pixels, ms, &w, &h);
    if (!ok) { free(pixels); return sage_rt_nil(); }
    int pixel_count = w * h * 4;
    SageValue arr = sage_rt_array_new(pixel_count);
    for (int i = 0; i < pixel_count && i < ms; i++) {
        sage_rt_array_push(arr, sage_rt_number((double)pixels[i]));
    }
    free(pixels);
    SageValue dict = sage_rt_dict_new();
    sage_rt_dict_set(dict, "pixels", arr);
    sage_rt_dict_set(dict, "width", sage_rt_number((double)w));
    sage_rt_dict_set(dict, "height", sage_rt_number((double)h));
    return dict;
}

SageValue sage_rt_gpu_save_screenshot(SageValue path) {
    const char* p = path.type == SAGE_STRING ? path.as.string : "screenshot.png";
    return sage_rt_bool(sgpu_save_screenshot(p));
}

// ---------------------------------------------------------------------------
// Font Rendering
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_load_font(SageValue path, SageValue size) {
    const char* p = path.type == SAGE_STRING ? path.as.string : "";
    return sage_rt_number((double)sgpu_load_font(p, (int)as_num(size)));
}

SageValue sage_rt_gpu_font_atlas(SageValue font) {
    return sage_rt_number((double)sgpu_font_atlas((int)as_num(font)));
}

SageValue sage_rt_gpu_font_set_atlas(SageValue font, SageValue image, SageValue sampler) {
    return sage_rt_bool(sgpu_font_set_atlas(
        (int)as_num(font), (int)as_num(image), (int)as_num(sampler)));
}

SageValue sage_rt_gpu_font_text_verts(SageValue font, SageValue text,
                                       SageValue x, SageValue y, SageValue scale,
                                       SageValue max_verts) {
    const char* t = text.type == SAGE_STRING ? text.as.string : "";
    int mv = (int)as_num(max_verts);
    if (mv <= 0) mv = 4096;
    float* verts = calloc((size_t)mv, sizeof(float));
    if (!verts) return sage_rt_array_new(0);
    int got = sgpu_font_text_verts((int)as_num(font), t,
                                   (float)as_num(x), (float)as_num(y),
                                   (float)as_num(scale), verts, mv);
    SageValue arr = sage_rt_array_new(got > 0 ? got : 0);
    for (int i = 0; i < got; i++) {
        sage_rt_array_push(arr, sage_rt_number((double)verts[i]));
    }
    free(verts);
    return arr;
}

SageValue sage_rt_gpu_font_measure(SageValue font, SageValue text, SageValue scale) {
    const char* t = text.type == SAGE_STRING ? text.as.string : "";
    float w = 0.0f, h = 0.0f;
    sgpu_font_measure((int)as_num(font), t, (float)as_num(scale), &w, &h);
    return sage_make_dict_wh((int)w, (int)h);
}

// ---------------------------------------------------------------------------
// glTF Loading
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_load_gltf(SageValue path) {
    const char* p = path.type == SAGE_STRING ? path.as.string : "";
    return sage_rt_number((double)sgpu_load_gltf(p));
}

// ---------------------------------------------------------------------------
// Queue Families
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_graphics_family(void) {
    return sage_rt_number((double)sgpu_graphics_family());
}

SageValue sage_rt_gpu_compute_family(void) {
    return sage_rt_number((double)sgpu_compute_family());
}

// ---------------------------------------------------------------------------
// Platform Override
// ---------------------------------------------------------------------------

SageValue sage_rt_gpu_set_platform(SageValue platform) {
    const char* p = platform.type == SAGE_STRING ? platform.as.string : "";
    sgpu_set_platform(p);
    return sage_rt_nil();
}

SageValue sage_rt_gpu_get_platform(void) {
    const char* p = sgpu_get_platform();
    return p ? sage_rt_string(p) : sage_rt_nil();
}

SageValue sage_rt_gpu_detected_platform(void) {
    const char* p = sgpu_detected_platform();
    return p ? sage_rt_string(p) : sage_rt_nil();
}
