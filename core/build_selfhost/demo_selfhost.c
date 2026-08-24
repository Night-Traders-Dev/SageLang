#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

typedef struct SageValue SageValue;

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
    SAGE_TAG_GENERATOR
} SageTag;

typedef struct SageFunction SageFunction;
struct SageValue {
    SageTag type;
    union {
        double number;
        int boolean;
        const char* string;
        SageArray* array;
        SageDict* dict;
        SageTuple* tuple;
        SageFunction* function;
        void* generator;
    } as;
};

#define SAGE_MAX_FN_ARGS 8
struct SageFunction {
    const char* name;
    int param_count;
    void* fn;
    void* env;
};

static SageValue sage_function_value(SageFunction* f) {
    SageValue v; v.type = SAGE_TAG_FUNCTION; v.as.function = f; return v;
}
static SageValue sage_nil(void);
static void sage_fail(const char* message);
static SageValue sage_string(const char* value);
static SageValue sage_bool(int value);
static SageValue sage_number(double value);
static SageValue sage_nil(void);
static SageValue sage_str_startswith(SageValue hay, SageValue pre);
static SageValue sage_str_endswith(SageValue hay, SageValue suf);
static SageValue sage_number(double value);
static SageValue sage_read_file_v(SageValue path) {
    FILE* f = fopen(path.as.string, "rb");
    if (!f) return sage_nil();
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(sz + 1);
    size_t rd = fread(buf, 1, sz, f); fclose(f);
    buf[rd] = 0;
    return sage_string(buf);
}
static SageValue sage_write_file_v(SageValue path, SageValue data) {
    FILE* f = fopen(path.as.string, "wb");
    if (!f) return sage_bool(0);
    fwrite(data.as.string, 1, strlen(data.as.string), f); fclose(f);
    return sage_bool(1);
}
static SageValue sage_file_exists_v(SageValue path) {
    FILE* f = fopen(path.as.string, "rb");
    if (!f) return sage_bool(0);
    fclose(f);
    return sage_bool(1);
}
typedef struct SageGenerator SageGenerator;
struct SageGenerator {
    SageArray* items;
    int index;
};
static SageValue sage_make_generator_from_array(SageArray* items) {
    SageGenerator* g = (SageGenerator*)malloc(sizeof(SageGenerator));
    if (g == NULL) sage_fail("Runtime Error: out of memory");
    g->items = items;
    g->index = 0;
    SageValue v; v.type = SAGE_TAG_GENERATOR; v.as.generator = g; return v;
}
static SageValue sage_generator_next(SageValue gv) {
    if (gv.type != SAGE_TAG_GENERATOR) {
        fprintf(stderr, "Runtime Error: next() requires a generator.\n");
        return sage_nil();
    }
    SageGenerator* g = (SageGenerator*)gv.as.generator;
    if (g->index >= g->items->count) return sage_nil();
    return g->items->elements[g->index++];
}
static SageValue sage_call_function_value(SageValue callee, int argc, SageValue* args) {
    if (callee.type != SAGE_TAG_FUNCTION || callee.as.function == NULL) {
        fprintf(stderr, "Runtime Error: value is not callable.\n");
        return sage_nil();
    }
    SageFunction* sf = callee.as.function;
    if (argc != sf->param_count) {
        fprintf(stderr, "Runtime Error: Expected %d to %d arguments but got %d.\n", sf->param_count, sf->param_count, argc);
        return sage_nil();
    }
    if (sf->env != NULL) {
        switch (sf->param_count) {
            case 0: return ((SageValue(*)(void*))sf->fn)(sf->env);
            case 1: return ((SageValue(*)(void*, SageValue))sf->fn)(sf->env, args[0]);
            case 2: return ((SageValue(*)(void*, SageValue, SageValue))sf->fn)(sf->env, args[0], args[1]);
            case 3: { SageValue a3[3]; for (int i=0;i<3;i++) a3[i]=args[i]; return ((SageValue(*)(void*, SageValue, SageValue, SageValue))sf->fn)(sf->env, a3[0], a3[1], a3[2]); }
            case 4: { SageValue a4[4]; for (int i=0;i<4;i++) a4[i]=args[i]; return ((SageValue(*)(void*, SageValue, SageValue, SageValue, SageValue))sf->fn)(sf->env, a4[0], a4[1], a4[2], a4[3]); }
            default: return sage_nil();
        }
    }
    switch (sf->param_count) {
        case 0: return ((SageValue(*)(void))sf->fn)();
        case 1: return ((SageValue(*)(SageValue))sf->fn)(args[0]);
        case 2: return ((SageValue(*)(SageValue, SageValue))sf->fn)(args[0], args[1]);
        case 3: { SageValue b3[3]; for (int i=0;i<3;i++) b3[i]=args[i]; return ((SageValue(*)(SageValue, SageValue, SageValue))sf->fn)(b3[0], b3[1], b3[2]); }
        case 4: { SageValue b4[4]; for (int i=0;i<4;i++) b4[i]=args[i]; return ((SageValue(*)(SageValue, SageValue, SageValue, SageValue))sf->fn)(b4[0], b4[1], b4[2], b4[3]); }
        default: return sage_nil();
    }
}
static SageValue sage_bind_closure(SageFunction* proto, void* env) {
    SageFunction* f = (SageFunction*)malloc(sizeof(SageFunction));
    if (f == NULL) sage_fail("Runtime Error: out of memory");
    f->name = proto->name; f->param_count = proto->param_count;
    f->fn = proto->fn; f->env = env;
    SageValue v; v.type = SAGE_TAG_FUNCTION; v.as.function = f; return v;
}

typedef struct {
    int defined;
    SageValue value;
} SageSlot;

#define SAGE_MAX_TRY_DEPTH 1024
static jmp_buf sage_try_stack[SAGE_MAX_TRY_DEPTH];
static SageValue sage_exception_value;
static int sage_try_depth = 0;

static void sage_fail(const char* message) {
    fputs(message, stderr);
    fputc('\n', stderr);
    exit(1);
}

static char* sage_dup_string(const char* text) {
    size_t len = strlen(text);
    char* copy = (char*)malloc(len + 1);
    if (copy == NULL) sage_fail("Runtime Error: out of memory");
    memcpy(copy, text, len + 1);
    return copy;
}

static SageArray* sage_new_array(void) {
    SageArray* array = (SageArray*)malloc(sizeof(SageArray));
    if (array == NULL) sage_fail("Runtime Error: out of memory");
    array->count = 0;
    array->capacity = 0;
    array->elements = NULL;
    return array;
}

static SageValue sage_nil(void) { SageValue v; v.type = SAGE_TAG_NIL; v.as.number = 0; return v; }
static SageValue sage_number(double value) { SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = value; return v; }
static SageValue sage_bool(int value) { SageValue v; v.type = SAGE_TAG_BOOL; v.as.boolean = value ? 1 : 0; return v; }
static SageValue sage_string(const char* value) { SageValue v; v.type = SAGE_TAG_STRING; v.as.string = value; return v; }
static SageValue sage_array(void) { SageValue v; v.type = SAGE_TAG_ARRAY; v.as.array = sage_new_array(); return v; }
static SageSlot sage_slot_undefined(void) { SageSlot slot; slot.defined = 0; slot.value = sage_nil(); return slot; }

static SageValue sage_make_dict(void) {
    SageDict* dict = (SageDict*)malloc(sizeof(SageDict));
    if (dict == NULL) sage_fail("Runtime Error: out of memory");
    dict->capacity = 16;
    dict->keys = (char**)calloc(dict->capacity, sizeof(char*));
    dict->values = (SageValue*)calloc(dict->capacity, sizeof(SageValue));
    dict->count = 0;
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

static SageValue sage_dict_get(SageDict* dict, const char* key) {
    for (int i = 0; i < dict->count; i++) {
        if (strcmp(dict->keys[i], key) == 0) return dict->values[i];
    }
    return sage_nil();
}

static SageValue sage_make_tuple(int count, const SageValue* values) {
    SageTuple* tuple = (SageTuple*)malloc(sizeof(SageTuple));
    if (tuple == NULL) sage_fail("Runtime Error: out of memory");
    tuple->count = count;
    tuple->elements = (SageValue*)malloc(sizeof(SageValue) * (size_t)count);
    if (tuple->elements == NULL && count > 0) sage_fail("Runtime Error: out of memory");
    for (int i = 0; i < count; i++) tuple->elements[i] = values[i];
    SageValue v; v.type = SAGE_TAG_TUPLE; v.as.tuple = tuple;
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
    SageValue array = sage_array();
    for (int i = 0; i < count; i++) {
        sage_array_push_raw(array.as.array, values[i]);
    }
    return array;
}

static int sage_truthy(SageValue value) {
    if (value.type == SAGE_TAG_NIL) return 0;
    if (value.type == SAGE_TAG_BOOL) return value.as.boolean;
    return 1;
}

static SageValue sage_load_undefined(const char* name) {
        fprintf(stderr, "Runtime Error: Undefined variable '%s'.\n", name);
        return sage_nil();
}
static SageValue sage_load_slot(const SageSlot* slot, const char* name) {
    if (!slot->defined) {
        fprintf(stderr, "Runtime Error: Undefined variable '%s'.\n", name);
        return sage_nil();
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
        return sage_nil();
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
        case SAGE_TAG_ARRAY: return left.as.array == right.as.array;
        case SAGE_TAG_DICT: return left.as.dict == right.as.dict;
        case SAGE_TAG_TUPLE: return left.as.tuple == right.as.tuple;
    }
    return 0;
}

static void sage_print_value(SageValue value) {
    switch (value.type) {
        case SAGE_TAG_NUMBER: printf("%g", value.as.number); break;
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
        case SAGE_TAG_NUMBER:
            snprintf(buffer, sizeof(buffer), "%g", value.as.number);
            return sage_string(sage_dup_string(buffer));
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

static SageValue sage_len(SageValue value) {
    if (value.type == SAGE_TAG_STRING) return sage_number((double)strlen(value.as.string));
    if (value.type == SAGE_TAG_ARRAY) return sage_number((double)value.as.array->count);
    if (value.type == SAGE_TAG_DICT) return sage_number((double)value.as.dict->count);
    if (value.type == SAGE_TAG_TUPLE) return sage_number((double)value.as.tuple->count);
    return sage_nil();
}

static SageValue sage_index(SageValue collection, SageValue index) {
    if (collection.type == SAGE_TAG_ARRAY && index.type == SAGE_TAG_NUMBER) {
        int idx = (int)index.as.number;
        if (idx < 0 || idx >= collection.as.array->count) return sage_nil();
        return collection.as.array->elements[idx];
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
        int len = (int)strlen(collection.as.string);
        if (idx < 0) idx = len + idx;
        if (idx < 0 || idx >= len) return sage_nil();
        char buf[2] = {collection.as.string[idx], '\0'};
        return sage_string(sage_dup_string(buf));
    }
    return sage_nil();
}

static SageValue sage_index_set(SageValue collection, SageValue index, SageValue value) {
    if (collection.type == SAGE_TAG_ARRAY && index.type == SAGE_TAG_NUMBER) {
        int idx = (int)index.as.number;
        if (idx >= 0 && idx < collection.as.array->count) collection.as.array->elements[idx] = value;
    }
    if (collection.type == SAGE_TAG_DICT && index.type == SAGE_TAG_STRING) {
        sage_dict_set(collection.as.dict, index.as.string, value);
    }
    return value;
}

static SageValue sage_slice(SageValue array, SageValue start, SageValue end) {
    if (array.type == SAGE_TAG_STRING) {
        int len = (int)strlen(array.as.string);
        int sIdx = (start.type == SAGE_TAG_NUMBER) ? (int)start.as.number : 0;
        int eIdx = (end.type == SAGE_TAG_NUMBER) ? (int)end.as.number : len;
        if (sIdx < 0) sIdx = len + sIdx;
        if (eIdx < 0) eIdx = len + eIdx;
        if (sIdx < 0) sIdx = 0;
        if (eIdx > len) eIdx = len;
        if (sIdx >= eIdx) return sage_string(sage_dup_string(""));
        char* result = (char*)malloc((size_t)(eIdx - sIdx) + 1);
        memcpy(result, array.as.string + sIdx, (size_t)(eIdx - sIdx));
        result[eIdx - sIdx] = '\0';
        return sage_string(result);
    }
    if (array.type != SAGE_TAG_ARRAY) return sage_nil();
    int start_index = 0;
    int end_index = array.as.array->count;
    if (start.type == SAGE_TAG_NUMBER) start_index = (int)start.as.number;
    if (end.type == SAGE_TAG_NUMBER) end_index = (int)end.as.number;
    if (start_index < 0) start_index = array.as.array->count + start_index;
    if (end_index < 0) end_index = array.as.array->count + end_index;
    if (start_index < 0) start_index = 0;
    if (end_index > array.as.array->count) end_index = array.as.array->count;
    if (start_index >= end_index) return sage_array();
    SageValue result = sage_array();
    for (int i = start_index; i < end_index; i++) {
        sage_array_push_raw(result.as.array, array.as.array->elements[i]);
    }
    return result;
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

static SageValue sage_range2(SageValue start, SageValue end) {
    if (start.type != SAGE_TAG_NUMBER || end.type != SAGE_TAG_NUMBER) return sage_nil();
    SageValue result = sage_array();
    for (int i = (int)start.as.number; i < (int)end.as.number; i++) {
        sage_array_push_raw(result.as.array, sage_number((double)i));
    }
    return result;
}

static SageValue sage_range1(SageValue end) {
    return sage_range2(sage_number(0), end);
}

static const char* sage_type_name_of(SageValue v) {
    switch (v.type) {
        case SAGE_TAG_NIL: return "nil";
        case SAGE_TAG_BOOL: return "bool";
        case SAGE_TAG_NUMBER: return "number";
        case SAGE_TAG_STRING: return "string";
        case SAGE_TAG_ARRAY: return "array";
        case SAGE_TAG_DICT: return "dict";
        case SAGE_TAG_TUPLE: return "tuple";
        default: return "unknown";
    }
}
static SageValue sage_type_fn(SageValue v) { return sage_string(sage_dup_string(sage_type_name_of(v))); }
static SageValue sage_indexof_fn(SageValue hay, SageValue needle) {
    if (hay.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_number(-1);
    const char* pos = strstr(hay.as.string, needle.as.string);
    if (pos == NULL) return sage_number(-1);
    return sage_number((double)(pos - hay.as.string));
}
static SageValue sage_str_contains(SageValue hay, SageValue needle) {
    if (hay.type != SAGE_TAG_STRING || needle.type != SAGE_TAG_STRING) return sage_bool(0);
    return sage_bool(strstr(hay.as.string, needle.as.string) != NULL);
}
static SageValue sage_chr_fn(SageValue code) {
    char buf[2] = { (char)((int)code.as.number), '\0' };
    return sage_string(sage_dup_string(buf));
}
static SageValue sage_ord_fn(SageValue s) {
    if (s.type != SAGE_TAG_STRING || strlen(s.as.string) == 0) return sage_nil();
    return sage_number((double)(unsigned char)s.as.string[0]);
}
static SageValue sage_int_fn(SageValue v) {
    if (v.type == SAGE_TAG_NUMBER) return sage_number((double)(long long)v.as.number);
    if (v.type == SAGE_TAG_STRING) return sage_number((double)strtoll(v.as.string, NULL, 10));
    return sage_number(0);
}
static SageValue sage_bytes_fn(SageValue n) {
    int count = (int)n.as.number;
    SageValue out = sage_array();
    sage_array_reserve(out.as.array, count < 0 ? 0 : count);
    for (int i = 0; i < count; i++) sage_array_push_raw(out.as.array, sage_number(0));
    return out;
}
static void sage_bytes_set_fn(SageValue b, SageValue i, SageValue v) { sage_index_set(b, i, v); }
static SageValue sage_bytes_get_fn(SageValue b, SageValue i) { return sage_index(b, i); }
static SageValue sage_bytes_len_fn(SageValue b) { return sage_len(b); }
static SageValue sage_bytes_to_string_fn(SageValue b) {
    if (b.type != SAGE_TAG_ARRAY) return sage_string(sage_dup_string(""));
    int n = b.as.array->count;
    char* result = (char*)malloc((size_t)n + 1);
    for (int i = 0; i < n; i++) result[i] = (char)(int)b.as.array->elements[i].as.number;
    result[n] = '\0';
    return sage_string(result);
}
static SageValue sage_bytes_push_fn(SageValue b, SageValue v) { sage_array_push_raw(b.as.array, v); return b; }
static SageValue sage_str_startswith(SageValue hay, SageValue pre) {
    if (hay.type != SAGE_TAG_STRING || pre.type != SAGE_TAG_STRING) return sage_bool(0);
    return sage_bool(strncmp(hay.as.string, pre.as.string, strlen(pre.as.string)) == 0);
}
static SageValue sage_str_endswith(SageValue hay, SageValue suf) {
    if (hay.type != SAGE_TAG_STRING || suf.type != SAGE_TAG_STRING) return sage_bool(0);
    size_t hl = strlen(hay.as.string), sl = strlen(suf.as.string);
    if (sl > hl) return sage_bool(0);
    return sage_bool(strcmp(hay.as.string + hl - sl, suf.as.string) == 0);
}
static SageValue sage_sys_exec_v(SageValue cmd) {
    int rc = system(cmd.as.string);
    return sage_number((double)rc);
}
static SageValue sage_mem_alloc_v(SageValue size) {
    size_t n = (size_t)(long long)size.as.number;
    unsigned char* base = (unsigned char*)malloc(n + 16);
    if (base == NULL) sage_fail("Runtime Error: out of memory");
    *(size_t*)base = n;
    return sage_number((double)(uintptr_t)(base + 16));
}
static SageValue sage_mem_free(SageValue p) {
    free((unsigned char*)(uintptr_t)p.as.number - 16);
    return sage_nil();
}
static SageValue sage_mem_read(SageValue a, SageValue o, SageValue s) {
    if (a.type != SAGE_TAG_NUMBER || o.type != SAGE_TAG_NUMBER || s.type != SAGE_TAG_NUMBER) return sage_nil();
    unsigned char* base = (unsigned char*)(uintptr_t)a.as.number - 16;
    size_t cap = *(size_t*)base;
    size_t off = (size_t)(long long)o.as.number;
    size_t len = (size_t)(long long)s.as.number;
    if (off + len > cap) return sage_nil();
    unsigned long long v = 0; memcpy(&v, base + 16 + off, len);
    return sage_number((double)v);
}
static SageValue sage_mem_write(SageValue a, SageValue o, SageValue sz, SageValue v) {
    unsigned char* base = (unsigned char*)(uintptr_t)a.as.number - 16;
    size_t cap = *(size_t*)base;
    size_t off = (size_t)(long long)o.as.number;
    size_t wr = (size_t)(long long)sz.as.number; if (off + wr > cap) wr = cap - off;
    unsigned long long val = (unsigned long long)v.as.number;
    memcpy(base + 16 + off, &val, wr);
    return v;
}
static SageValue sage_mem_size(SageValue p) {
    unsigned char* base = (unsigned char*)(uintptr_t)p.as.number - 16;
    return sage_number((double)*(size_t*)base);
}
static SageValue sage_struct_new(SageValue defv) { (void)defv; return sage_make_dict(); }
static SageValue sage_struct_def(SageValue v) { (void)v; return sage_make_dict(); }
static SageValue sage_struct_size(SageValue v) { (void)v; return sage_number(0); }
static SageValue sage_struct_get(SageValue d, SageValue k, SageValue defv) {
    if (d.type != SAGE_TAG_DICT || k.type != SAGE_TAG_STRING) return defv;
    for (int i = 0; i < d.as.dict->count; i++) {
        if (strcmp(d.as.dict->keys[i], k.as.string) == 0) return d.as.dict->values[i];
    }
    return defv;
}
static SageValue sage_struct_set(SageValue d, SageValue k, SageValue t, SageValue val) {
    (void)t;
    if (d.type != SAGE_TAG_DICT || k.type != SAGE_TAG_STRING) return val;
        for (int i = 0; i < d.as.dict->count; i++) {
            if (strcmp(d.as.dict->keys[i], k.as.string) == 0) { d.as.dict->values[i] = val; return val; }
        }
        if (d.as.dict->count >= d.as.dict->capacity) {
            int nc = d.as.dict->capacity ? d.as.dict->capacity * 2 : 8;
            d.as.dict->keys = (char**)realloc(d.as.dict->keys, sizeof(char*) * nc);
            d.as.dict->values = (SageValue*)realloc(d.as.dict->values, sizeof(SageValue) * nc);
            d.as.dict->capacity = nc;
        }
        d.as.dict->keys[d.as.dict->count] = sage_dup_string(k.as.string);
        d.as.dict->values[d.as.dict->count] = val;
        d.as.dict->count++;
    return val;
}

static SageValue sage_add(SageValue left, SageValue right) {
    if (left.type == SAGE_TAG_NUMBER && right.type == SAGE_TAG_NUMBER) {
        return sage_number(left.as.number + right.as.number);
    }
    if (left.type == SAGE_TAG_STRING && right.type == SAGE_TAG_STRING) {
        size_t len1 = strlen(left.as.string);
        size_t len2 = strlen(right.as.string);
        char* result = (char*)malloc(len1 + len2 + 1);
        if (result == NULL) sage_fail("Runtime Error: out of memory");
        memcpy(result, left.as.string, len1);
        memcpy(result + len1, right.as.string, len2 + 1);
        return sage_string(result);
    }
    if (left.type == SAGE_TAG_ARRAY && right.type == SAGE_TAG_ARRAY) {
        SageValue out = sage_array();
        for (int i = 0; i < left.as.array->count; i++) sage_array_push_raw(out.as.array, left.as.array->elements[i]);
        for (int i = 0; i < right.as.array->count; i++) sage_array_push_raw(out.as.array, right.as.array->elements[i]);
        return out;
    }
    sage_fail("Runtime Error: Operands must be numbers or strings.");
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
    if (right.as.number == 0) { fprintf(stderr, "Runtime Error: Division by zero.\n"); sage_raise(sage_string(sage_dup_string("Division by zero"))); return sage_nil(); }
    return sage_number(left.as.number / right.as.number);
}
static SageValue sage_mod(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    if (right.as.number == 0) { fprintf(stderr, "Runtime Error: Modulo by zero.\n"); sage_raise(sage_string(sage_dup_string("Modulo by zero"))); return sage_nil(); }
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
    return sage_number((double)(((long long)left.as.number) << ((long long)right.as.number)));
}
static SageValue sage_rshift(SageValue left, SageValue right) {
    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail("Runtime Error: Operands must be numbers.");
    return sage_number((double)(((long long)left.as.number) >> ((long long)right.as.number)));
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
    SageValue result = sage_array();
    for (int i = 0; i < dict_val.as.dict->count; i++) {
        sage_array_push_raw(result.as.array, sage_string(dict_val.as.dict->keys[i]));
    }
    return result;
}

static SageValue sage_dict_values_fn(SageValue dict_val) {
    if (dict_val.type != SAGE_TAG_DICT) return sage_array();
    SageValue result = sage_array();
    for (int i = 0; i < dict_val.as.dict->count; i++) {
        sage_array_push_raw(result.as.array, dict_val.as.dict->values[i]);
    }
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

#include <ctype.h>
static SageValue sage_upper(SageValue value) {
    if (value.type != SAGE_TAG_STRING) return sage_nil();
    size_t len = strlen(value.as.string);
    char* result = (char*)malloc(len + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    for (size_t i = 0; i < len; i++) result[i] = (char)toupper((unsigned char)value.as.string[i]);
    result[len] = '\0';
    return sage_string(result);
}
static SageValue sage_lower(SageValue value) {
    if (value.type != SAGE_TAG_STRING) return sage_nil();
    size_t len = strlen(value.as.string);
    char* result = (char*)malloc(len + 1);
    if (result == NULL) sage_fail("Runtime Error: out of memory");
    for (size_t i = 0; i < len; i++) result[i] = (char)tolower((unsigned char)value.as.string[i]);
    result[len] = '\0';
    return sage_string(result);
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
    return sage_string(result);
}

static SageValue sage_split_fn(SageValue str_val, SageValue delim_val) {
    if (str_val.type != SAGE_TAG_STRING || delim_val.type != SAGE_TAG_STRING) return sage_array();
    const char* s = str_val.as.string;
    const char* delim = delim_val.as.string;
    size_t dlen = strlen(delim);
    SageValue result = sage_array();
    if (dlen == 0) {
        for (size_t i = 0; s[i]; i++) {
            char buf[2] = {s[i], '\0'};
            sage_array_push_raw(result.as.array, sage_string(sage_dup_string(buf)));
        }
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
        sage_array_push_raw(result.as.array, sage_string(part));
        start = found + dlen;
    }
    sage_array_push_raw(result.as.array, sage_string(sage_dup_string(start)));
    return result;
}

static SageValue sage_join_fn(SageValue arr_val, SageValue delim_val) {
    if (arr_val.type != SAGE_TAG_ARRAY || delim_val.type != SAGE_TAG_STRING) return sage_nil();
    SageArray* arr = arr_val.as.array;
    const char* delim = delim_val.as.string;
    size_t dlen = strlen(delim);
    if (arr->count == 0) return sage_string(sage_dup_string(""));
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
    return sage_string(result);
}

static SageValue sage_replace_fn(SageValue str_val, SageValue old_val, SageValue new_val) {
    if (str_val.type != SAGE_TAG_STRING || old_val.type != SAGE_TAG_STRING || new_val.type != SAGE_TAG_STRING)
        return sage_nil();
    const char* s = str_val.as.string;
    const char* old_s = old_val.as.string;
    const char* new_s = new_val.as.string;
    size_t old_len = strlen(old_s);
    size_t new_len = strlen(new_s);
    if (old_len == 0) return sage_string(sage_dup_string(s));
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
    return sage_string(result);
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
    return sage_string(sage_dup_string(buf));
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
        fprintf(stderr, "Runtime Error: method call on non-instance.\n");
        exit(1);
    }
    SageValue class_val = sage_dict_get(obj.as.dict, "__class__");
    if (class_val.type != SAGE_TAG_STRING) {
        /* Not a class instance: fall back to callable-field dispatch */
        SageValue fval = sage_dict_get(obj.as.dict, method);
        if (fval.type == SAGE_TAG_FUNCTION) return sage_call_function_value(fval, argc, argv);
        fprintf(stderr, "Runtime Error: no __class__ on instance.\n");
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
    SageValue inst = sage_make_dict();
    sage_dict_set(inst.as.dict, "__class__", sage_string(class_name));
    if (parent_name != NULL) sage_dict_set(inst.as.dict, "__parent__", sage_string(parent_name));
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

static SageValue sage_fn_fib_1(SageValue arg0);
static SageFunction sage_fnobj_sage_fn_fib_1 = { "fib", 1, (void*)sage_fn_fib_1, NULL };

static SageSlot sage_global_total_2;
static SageSlot sage_global_i_3;

static SageValue sage_fn_fib_1(SageValue arg0) {
    SageSlot sage_param_n_4 = sage_slot_undefined();
    sage_define_slot(&sage_param_n_4, arg0);
    if (sage_truthy(sage_lte(sage_load_slot(&sage_param_n_4, "n"), sage_number(1)))) {
        return sage_load_slot(&sage_param_n_4, "n");
    }
    return sage_add(sage_fn_fib_1(sage_sub(sage_load_slot(&sage_param_n_4, "n"), sage_number(1))), sage_fn_fib_1(sage_sub(sage_load_slot(&sage_param_n_4, "n"), sage_number(2))));
    return sage_nil();
}

static int g_sage_argc = 0;
static char** g_sage_argv = NULL;
static SageValue sage_args_v(void) { SageValue o = sage_array(); for (int i = 0; i < g_sage_argc; i++) sage_array_push_raw(o.as.array, sage_string(g_sage_argv[i])); return o; }
int main(int argc, char** argv) { g_sage_argc = argc; g_sage_argv = argv;
    sage_global_total_2 = sage_slot_undefined();
    sage_global_i_3 = sage_slot_undefined();
    (void)sage_load_undefined("end");
    sage_define_slot(&sage_global_total_2, sage_number(0));
    sage_define_slot(&sage_global_i_3, sage_number(0));
    while (sage_truthy(sage_lt(sage_load_slot(&sage_global_i_3, "i"), sage_number(1000)))) {
        (void)sage_assign_slot(&sage_global_total_2, "total", sage_add(sage_load_slot(&sage_global_total_2, "total"), sage_load_slot(&sage_global_i_3, "i")));
        (void)sage_assign_slot(&sage_global_i_3, "i", sage_add(sage_load_slot(&sage_global_i_3, "i"), sage_number(1)));
    }
    (void)sage_load_undefined("end");
    sage_print_ln(sage_add(sage_string("fib(15) = "), sage_str(sage_fn_fib_1(sage_number(15)))));
    sage_print_ln(sage_add(sage_string("sum(0..999) = "), sage_str(sage_load_slot(&sage_global_total_2, "total"))));
    return 0;
}
