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
