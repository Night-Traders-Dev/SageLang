#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "value.h"

// ========== VALUE CONSTRUCTORS ==========

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

Value val_array() {
    Value v;
    v.type = VAL_ARRAY;
    v.as.array = malloc(sizeof(ArrayValue));
    v.as.array->elements = NULL;
    v.as.array->count = 0;
    v.as.array->capacity = 0;
    return v;
}

Value val_dict() {
    Value v;
    v.type = VAL_DICT;
    v.as.dict = malloc(sizeof(DictValue));
    v.as.dict->entries = NULL;
    v.as.dict->count = 0;
    v.as.dict->capacity = 0;
    return v;
}

Value val_tuple(Value* elements, int count) {
    Value v;
    v.type = VAL_TUPLE;
    v.as.tuple = malloc(sizeof(TupleValue));
    v.as.tuple->count = count;
    v.as.tuple->elements = malloc(sizeof(Value) * count);
    for (int i = 0; i < count; i++) {
        v.as.tuple->elements[i] = elements[i];
    }
    return v;
}

// ========== ARRAY OPERATIONS ==========

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

Value array_slice(Value* arr, int start, int end) {
    if (arr->type != VAL_ARRAY) return val_nil();
    ArrayValue* a = arr->as.array;
    
    // Handle negative indices
    if (start < 0) start = a->count + start;
    if (end < 0) end = a->count + end;
    
    // Clamp to valid range
    if (start < 0) start = 0;
    if (end > a->count) end = a->count;
    if (start >= end) return val_array();
    
    Value result = val_array();
    for (int i = start; i < end; i++) {
        array_push(&result, a->elements[i]);
    }
    return result;
}

// ========== DICTIONARY OPERATIONS ==========

void dict_set(Value* dict, const char* key, Value value) {
    if (dict->type != VAL_DICT) return;
    DictValue* d = dict->as.dict;
    
    // Check if key already exists
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->entries[i].key, key) == 0) {
            *(d->entries[i].value) = value;  // Update existing value
            return;
        }
    }
    
    // Add new entry
    if (d->count >= d->capacity) {
        d->capacity = d->capacity == 0 ? 8 : d->capacity * 2;
        d->entries = realloc(d->entries, sizeof(DictEntry) * d->capacity);
    }
    
    d->entries[d->count].key = malloc(strlen(key) + 1);
    strcpy(d->entries[d->count].key, key);
    
    d->entries[d->count].value = malloc(sizeof(Value));  // Allocate Value
    *(d->entries[d->count].value) = value;               // Copy value
    d->count++;
}

Value dict_get(Value* dict, const char* key) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;
    
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->entries[i].key, key) == 0) {
            return *(d->entries[i].value);  // Dereference pointer
        }
    }
    return val_nil();
}

int dict_has(Value* dict, const char* key) {
    if (dict->type != VAL_DICT) return 0;
    DictValue* d = dict->as.dict;
    
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->entries[i].key, key) == 0) {
            return 1;
        }
    }
    return 0;
}

void dict_delete(Value* dict, const char* key) {
    if (dict->type != VAL_DICT) return;
    DictValue* d = dict->as.dict;
    
    for (int i = 0; i < d->count; i++) {
        if (strcmp(d->entries[i].key, key) == 0) {
            free(d->entries[i].key);
            free(d->entries[i].value);  // Free Value pointer
            // Shift remaining entries
            for (int j = i; j < d->count - 1; j++) {
                d->entries[j] = d->entries[j + 1];
            }
            d->count--;
            return;
        }
    }
}

Value dict_keys(Value* dict) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;
    
    Value result = val_array();
    for (int i = 0; i < d->count; i++) {
        char* key_copy = malloc(strlen(d->entries[i].key) + 1);
        strcpy(key_copy, d->entries[i].key);
        array_push(&result, val_string(key_copy));
    }
    return result;
}

Value dict_values(Value* dict) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;
    
    Value result = val_array();
    for (int i = 0; i < d->count; i++) {
        array_push(&result, *(d->entries[i].value));  // Dereference pointer
    }
    return result;
}

// ========== TUPLE OPERATIONS ==========

Value tuple_get(Value* tuple, int index) {
    if (tuple->type != VAL_TUPLE) return val_nil();
    TupleValue* t = tuple->as.tuple;
    if (index < 0 || index >= t->count) return val_nil();
    return t->elements[index];
}

// ========== STRING OPERATIONS ==========

Value string_split(const char* str, const char* delimiter) {
    Value result = val_array();
    
    if (!str || !delimiter) return result;
    
    int del_len = strlen(delimiter);
    if (del_len == 0) {
        // Split into individual characters
        for (int i = 0; str[i]; i++) {
            char* ch = malloc(2);
            ch[0] = str[i];
            ch[1] = '\0';
            array_push(&result, val_string(ch));
        }
        return result;
    }
    
    const char* start = str;
    const char* found;
    
    while ((found = strstr(start, delimiter)) != NULL) {
        int len = found - start;
        char* part = malloc(len + 1);
        strncpy(part, start, len);
        part[len] = '\0';
        array_push(&result, val_string(part));
        start = found + del_len;
    }
    
    // Add remaining part
    char* part = malloc(strlen(start) + 1);
    strcpy(part, start);
    array_push(&result, val_string(part));
    
    return result;
}

Value string_join(Value* arr, const char* separator) {
    if (arr->type != VAL_ARRAY) return val_nil();
    ArrayValue* a = arr->as.array;
    
    if (a->count == 0) return val_string("");
    
    // Calculate total length
    int total_len = 0;
    int sep_len = strlen(separator);
    
    for (int i = 0; i < a->count; i++) {
        if (a->elements[i].type == VAL_STRING) {
            total_len += strlen(AS_STRING(a->elements[i]));
        }
        if (i < a->count - 1) total_len += sep_len;
    }
    
    char* result = malloc(total_len + 1);
    result[0] = '\0';
    
    for (int i = 0; i < a->count; i++) {
        if (a->elements[i].type == VAL_STRING) {
            strcat(result, AS_STRING(a->elements[i]));
        }
        if (i < a->count - 1) {
            strcat(result, separator);
        }
    }
    
    return val_string(result);
}

char* string_replace(const char* str, const char* old, const char* new_str) {
    if (!str || !old || !new_str) return NULL;
    
    int old_len = strlen(old);
    int new_len = strlen(new_str);
    
    // Count occurrences
    int count = 0;
    const char* tmp = str;
    while ((tmp = strstr(tmp, old)) != NULL) {
        count++;
        tmp += old_len;
    }
    
    if (count == 0) {
        char* result = malloc(strlen(str) + 1);
        strcpy(result, str);
        return result;
    }
    
    // Allocate result
    int result_len = strlen(str) + count * (new_len - old_len);
    char* result = malloc(result_len + 1);
    result[0] = '\0';
    
    // Build result
    const char* src = str;
    const char* found;
    
    while ((found = strstr(src, old)) != NULL) {
        int len = found - src;
        strncat(result, src, len);
        strcat(result, new_str);
        src = found + old_len;
    }
    strcat(result, src);
    
    return result;
}

char* string_upper(const char* str) {
    if (!str) return NULL;
    char* result = malloc(strlen(str) + 1);
    for (int i = 0; str[i]; i++) {
        result[i] = toupper(str[i]);
    }
    result[strlen(str)] = '\0';
    return result;
}

char* string_lower(const char* str) {
    if (!str) return NULL;
    char* result = malloc(strlen(str) + 1);
    for (int i = 0; str[i]; i++) {
        result[i] = tolower(str[i]);
    }
    result[strlen(str)] = '\0';
    return result;
}

char* string_strip(const char* str) {
    if (!str) return NULL;
    
    // Find start (skip leading whitespace)
    while (*str && isspace(*str)) str++;
    
    if (*str == '\0') {
        char* result = malloc(1);
        result[0] = '\0';
        return result;
    }
    
    // Find end (skip trailing whitespace)
    const char* end = str + strlen(str) - 1;
    while (end > str && isspace(*end)) end--;
    
    int len = end - str + 1;
    char* result = malloc(len + 1);
    strncpy(result, str, len);
    result[len] = '\0';
    
    return result;
}

// ========== HELPERS ==========

void print_value(Value v) {
    switch (v.type) {
        case VAL_NUMBER: 
            printf("%g", AS_NUMBER(v)); 
            break;
            
        case VAL_BOOL:   
            printf(AS_BOOL(v) ? "true" : "false"); 
            break;
            
        case VAL_NIL:    
            printf("nil"); 
            break;
            
        case VAL_STRING: 
            printf("%s", AS_STRING(v)); 
            break;
            
        case VAL_FUNCTION: 
            printf("<fn>"); 
            break;
            
        case VAL_NATIVE: 
            printf("<native fn>"); 
            break;
            
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
        
        case VAL_DICT: {
            printf("{");
            DictValue* d = v.as.dict;
            for (int i = 0; i < d->count; i++) {
                if (i > 0) printf(", ");
                printf("\"%s\": ", d->entries[i].key);
                print_value(*(d->entries[i].value));  // Dereference pointer
            }
            printf("}");
            break;
        }
        
        case VAL_TUPLE: {
            printf("(");
            TupleValue* t = v.as.tuple;
            for (int i = 0; i < t->count; i++) {
                if (i > 0) printf(", ");
                print_value(t->elements[i]);
            }
            if (t->count == 1) printf(","); // Single-element tuple
            printf(")");
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
        case VAL_TUPLE: {
            TupleValue* ta = a.as.tuple;
            TupleValue* tb = b.as.tuple;
            if (ta->count != tb->count) return 0;
            for (int i = 0; i < ta->count; i++) {
                if (!values_equal(ta->elements[i], tb->elements[i])) return 0;
            }
            return 1;
        }
        default: return 0; // Arrays and dicts compare by reference
    }
}