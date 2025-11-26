#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "value.h"

Value val_number(double value) {
    Value v;
    v.type = VAL_NUMBER;
    v.as.number = value;
    return v;
}

Value val_bool(int value) {
    Value v;
    v.type = VAL_BOOL;
    v.as.boolean = value;
    return v;
}

Value val_nil() {
    Value v;
    v.type = VAL_NIL;
    v.as.number = 0;
    return v;
}

Value val_native(NativeFn fn) {
    Value v;
    v.type = VAL_NATIVE;
    v.as.native = fn;
    return v;
}

Value val_array() {
    Value v;
    v.type = VAL_ARRAY;
    v.as.array = malloc(sizeof(ArrayValue));
    v.as.array->elements = NULL;
    v.as.array->count = 0;
    v.as.array->capacity = 0;
    return v;
}

void array_push(Value* arr, Value val) {
    if (arr->type != VAL_ARRAY) return;
    ArrayValue* a = arr->as.array;

    if (a->count >= a->capacity) {
        a->capacity = a->capacity == 0 ? 4 : a->capacity * 2;
        a->elements = realloc(a->elements, sizeof(Value) * a->capacity);
    }
    a->elements[a->count++] = val;
}

Value array_get(Value* arr, int index) {
    if (arr->type != VAL_ARRAY) return val_nil();
    ArrayValue* a = arr->as.array;
    if (index < 0 || index >= a->count) return val_nil();
    return a->elements[index];
}

void array_set(Value* arr, int index, Value val) {
    if (arr->type != VAL_ARRAY) return;
    ArrayValue* a = arr->as.array;
    if (index < 0 || index >= a->count) return;
    a->elements[index] = val;
}

Value val_string(char* value) {
    Value v;
    v.type = VAL_STRING;
    v.as.string = value;
    return v;
}

void print_value(Value v) {
    switch (v.type) {
        case VAL_NUMBER: printf("%g", AS_NUMBER(v)); break;
        case VAL_BOOL:   printf(AS_BOOL(v) ? "true" : "false"); break;
        case VAL_NIL:    printf("nil"); break;
        case VAL_STRING: printf("%s", AS_STRING(v)); break;
        case VAL_FUNCTION: printf("<fn>"); break;
        case VAL_NATIVE: printf("<native fn>"); break;
        case VAL_ARRAY: {
            printf("[");
            ArrayValue* a = v.as.array;
            for (int i = 0; i < a->count; i++) {
                if (i > 0) printf(", ");
                print_value(a->elements[i]);
            }
            printf("]");
            break;
        }
    }
}

int values_equal(Value a, Value b) {
    if (a.type != b.type) return 0;
    switch (a.type) {
        case VAL_NUMBER: return AS_NUMBER(a) == AS_NUMBER(b);
        case VAL_BOOL:   return AS_BOOL(a) == AS_BOOL(b);
        case VAL_NIL:    return 1;
        case VAL_STRING: return strcmp(AS_STRING(a), AS_STRING(b)) == 0;
        default:         return 0;
    }
}
