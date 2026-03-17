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
    sv.as.array->elements = calloc((size_t)sv.as.array->capacity, sizeof(SageValue));
    if (!sv.as.array->elements) { fprintf(stderr, "OOM\n"); abort(); }
    return sv;
}

void sage_rt_array_set(SageValue arr, int32_t idx, SageValue val) {
    if (arr.type != SAGE_ARRAY) return;
    SageArray* a = arr.as.array;
    while (idx >= a->capacity) {
        a->capacity *= 2;
        a->elements = realloc(a->elements, sizeof(SageValue) * (size_t)a->capacity);
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
        a->elements = realloc(a->elements, sizeof(SageValue) * (size_t)a->capacity);
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
            d->keys = realloc(d->keys, sizeof(char*) * (size_t)d->capacity);
            d->values = realloc(d->values, sizeof(SageValue) * (size_t)d->capacity);
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
    sv.as.dict = calloc(1, sizeof(SageDict));
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
        d->keys = realloc(d->keys, sizeof(char*) * (size_t)d->capacity);
        d->values = realloc(d->values, sizeof(SageValue) * (size_t)d->capacity);
        if (!d->keys || !d->values) { fprintf(stderr, "OOM\n"); abort(); }
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
    sv.as.tuple->elements = calloc(count > 0 ? (size_t)count : 1, sizeof(SageValue));
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
            fields->keys = realloc(fields->keys, sizeof(char*) * (size_t)fields->capacity);
            fields->values = realloc(fields->values, sizeof(SageValue) * (size_t)fields->capacity);
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
