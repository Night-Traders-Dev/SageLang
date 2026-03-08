#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "value.h"
#include "gc.h"
#include "module.h"


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

static char* gc_string_copy(const char* value) {
    size_t len = strlen(value);
    char* copy = gc_alloc(VAL_STRING, len + 1);
    memcpy(copy, value, len + 1);
    return copy;
}

Value val_string(const char* value) {
    Value v;
    v.type = VAL_STRING;
    v.as.string = gc_string_copy(value == NULL ? "" : value);
    return v;
}

Value val_string_take(char* value) {
    Value v = val_string(value == NULL ? "" : value);
    free(value);
    return v;
}

Value val_function(void* proc, Env* closure) {
    Value v;
    v.type = VAL_FUNCTION;
    v.as.function = gc_alloc(VAL_FUNCTION, sizeof(FunctionValue));
    v.as.function->proc = proc;
    v.as.function->closure = closure;
    return v;
}


Value val_array() {
    Value v;
    v.type = VAL_ARRAY;
    v.as.array = gc_alloc(VAL_ARRAY, sizeof(ArrayValue));
    v.as.array->elements = NULL;
    v.as.array->count = 0;
    v.as.array->capacity = 0;
    return v;
}

Value val_dict() {
    Value v;
    v.type = VAL_DICT;
    v.as.dict = gc_alloc(VAL_DICT, sizeof(DictValue));
    v.as.dict->entries = NULL;
    v.as.dict->count = 0;
    v.as.dict->capacity = 0;
    return v;
}

Value val_tuple(Value* elements, int count) {
    Value v;
    v.type = VAL_TUPLE;
    v.as.tuple = gc_alloc(VAL_TUPLE, sizeof(TupleValue));
    v.as.tuple->count = count;
    v.as.tuple->elements = SAGE_ALLOC(sizeof(Value) * count);
    for (int i = 0; i < count; i++) {
        v.as.tuple->elements[i] = elements[i];
    }
    return v;
}

Value val_class(ClassValue* class_val) {
    Value v;
    v.type = VAL_CLASS;
    v.as.class_val = class_val;
    return v;
}

Value val_instance(InstanceValue* instance) {
    Value v;
    v.type = VAL_INSTANCE;
    v.as.instance = instance;
    return v;
}

Value val_module(Module* module) {
    Value v;
    v.type = VAL_MODULE;
    v.as.module = gc_alloc(VAL_MODULE, sizeof(ModuleValue));
    v.as.module->module = module;
    return v;
}

// PHASE 7: Exception constructor
Value val_exception(const char* message) {
    Value v;
    v.type = VAL_EXCEPTION;
    v.as.exception = gc_alloc(VAL_EXCEPTION, sizeof(ExceptionValue));
    v.as.exception->message = SAGE_ALLOC(strlen(message) + 1);
    strcpy(v.as.exception->message, message);
    return v;
}

// PHASE 7: Generator constructor
Value val_generator(void* body, void* params, int param_count, Environment* closure) {
    Value v;
    v.type = VAL_GENERATOR;
    v.as.generator = gc_alloc(VAL_GENERATOR, sizeof(GeneratorValue));
    v.as.generator->body = body;
    v.as.generator->params = params;
    v.as.generator->param_count = param_count;
    v.as.generator->closure = closure;
    v.as.generator->gen_env = NULL;  // Created on first next() call
    v.as.generator->is_started = 0;
    v.as.generator->is_exhausted = 0;
    v.as.generator->current_stmt = NULL;
    v.as.generator->has_resume_target = 0;
    return v;
}

// ========== ARRAY OPERATIONS ==========

void array_push(Value* arr, Value val) {
    if (arr->type != VAL_ARRAY) return;
    ArrayValue* a = arr->as.array;

    if (a->count >= a->capacity) {
        a->capacity = a->capacity == 0 ? 4 : a->capacity * 2;
        a->elements = SAGE_REALLOC(a->elements, sizeof(Value) * a->capacity);
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
    
    if (start < 0) start = a->count + start;
    if (end < 0) end = a->count + end;
    
    if (start < 0) start = 0;
    if (end > a->count) end = a->count;
    if (start >= end) return val_array();
    
    Value result = val_array();
    for (int i = start; i < end; i++) {
        array_push(&result, a->elements[i]);
    }
    return result;
}

// ========== DICTIONARY OPERATIONS (HASH TABLE) ==========

// FNV-1a hash function
static unsigned int dict_hash(const char* key) {
    unsigned int hash = 2166136261u;
    for (const char* p = key; *p; p++) {
        hash ^= (unsigned char)*p;
        hash *= 16777619u;
    }
    return hash;
}

// Find the slot for a key (returns index). If key is not present,
// returns the index of the first empty slot where it should go.
static int dict_find_slot(DictValue* d, const char* key, unsigned int hash) {
    int mask = d->capacity - 1;  // capacity is always power of 2
    int idx = (int)(hash & (unsigned int)mask);
    for (;;) {
        DictEntry* e = &d->entries[idx];
        if (e->key == NULL) return idx;  // Empty slot
        if (e->hash == hash && strcmp(e->key, key) == 0) return idx;  // Found
        idx = (idx + 1) & mask;  // Linear probing
    }
}

// Grow the hash table and rehash all entries
static void dict_grow(DictValue* d) {
    int old_capacity = d->capacity;
    DictEntry* old_entries = d->entries;

    d->capacity = old_capacity == 0 ? 8 : old_capacity * 2;
    d->entries = SAGE_ALLOC(sizeof(DictEntry) * d->capacity);
    memset(d->entries, 0, sizeof(DictEntry) * d->capacity);
    d->count = 0;

    for (int i = 0; i < old_capacity; i++) {
        if (old_entries[i].key != NULL) {
            int slot = dict_find_slot(d, old_entries[i].key, old_entries[i].hash);
            d->entries[slot] = old_entries[i];
            d->count++;
        }
    }
    free(old_entries);
}

void dict_set(Value* dict, const char* key, Value value) {
    if (dict->type != VAL_DICT) return;
    DictValue* d = dict->as.dict;

    // Grow if load factor > 75%
    if (d->capacity == 0 || d->count * 4 >= d->capacity * 3) {
        dict_grow(d);
    }

    unsigned int hash = dict_hash(key);
    int slot = dict_find_slot(d, key, hash);

    if (d->entries[slot].key != NULL) {
        // Key exists, update value
        *(d->entries[slot].value) = value;
        return;
    }

    // New entry
    size_t klen = strlen(key);
    d->entries[slot].key = SAGE_ALLOC(klen + 1);
    memcpy(d->entries[slot].key, key, klen + 1);
    d->entries[slot].hash = hash;
    d->entries[slot].value = SAGE_ALLOC(sizeof(Value));
    *(d->entries[slot].value) = value;
    d->count++;
}

Value dict_get(Value* dict, const char* key) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;
    if (d->capacity == 0) return val_nil();

    unsigned int hash = dict_hash(key);
    int slot = dict_find_slot(d, key, hash);

    if (d->entries[slot].key == NULL) return val_nil();
    return *(d->entries[slot].value);
}

int dict_has(Value* dict, const char* key) {
    if (dict->type != VAL_DICT) return 0;
    DictValue* d = dict->as.dict;
    if (d->capacity == 0) return 0;

    unsigned int hash = dict_hash(key);
    int slot = dict_find_slot(d, key, hash);

    return d->entries[slot].key != NULL;
}

void dict_delete(Value* dict, const char* key) {
    if (dict->type != VAL_DICT) return;
    DictValue* d = dict->as.dict;
    if (d->capacity == 0) return;

    unsigned int hash = dict_hash(key);
    int slot = dict_find_slot(d, key, hash);

    if (d->entries[slot].key == NULL) return;  // Not found

    // Free the entry
    free(d->entries[slot].key);
    free(d->entries[slot].value);
    d->entries[slot].key = NULL;
    d->entries[slot].value = NULL;
    d->count--;

    // Rehash subsequent entries to fix probe chain (backward-shift deletion)
    int mask = d->capacity - 1;
    int idx = (slot + 1) & mask;
    while (d->entries[idx].key != NULL) {
        int natural = (int)(d->entries[idx].hash & (unsigned int)mask);
        // Check if this entry is displaced past the deleted slot
        if ((idx > slot && (natural <= slot || natural > idx)) ||
            (idx < slot && (natural <= slot && natural > idx))) {
            d->entries[slot] = d->entries[idx];
            d->entries[idx].key = NULL;
            d->entries[idx].value = NULL;
            slot = idx;
        }
        idx = (idx + 1) & mask;
    }
}

Value dict_keys(Value* dict) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;

    Value result = val_array();
    for (int i = 0; i < d->capacity; i++) {
        if (d->entries[i].key != NULL) {
            size_t klen = strlen(d->entries[i].key);
            char* key_copy = SAGE_ALLOC(klen + 1);
            memcpy(key_copy, d->entries[i].key, klen + 1);
            array_push(&result, val_string_take(key_copy));
        }
    }
    return result;
}

Value dict_values(Value* dict) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;

    Value result = val_array();
    for (int i = 0; i < d->capacity; i++) {
        if (d->entries[i].key != NULL) {
            array_push(&result, *(d->entries[i].value));
        }
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
        for (int i = 0; str[i]; i++) {
            char* ch = SAGE_ALLOC(2);
            ch[0] = str[i];
            ch[1] = '\0';
            array_push(&result, val_string_take(ch));
        }
        return result;
    }
    
    const char* start = str;
    const char* found;
    
    while ((found = strstr(start, delimiter)) != NULL) {
        int len = found - start;
        char* part = SAGE_ALLOC(len + 1);
        strncpy(part, start, len);
        part[len] = '\0';
        array_push(&result, val_string_take(part));
        start = found + del_len;
    }
    
    char* part = SAGE_ALLOC(strlen(start) + 1);
    strcpy(part, start);
    array_push(&result, val_string_take(part));
    
    return result;
}

Value string_join(Value* arr, const char* separator) {
    if (arr->type != VAL_ARRAY) return val_nil();
    ArrayValue* a = arr->as.array;

    if (a->count == 0) return val_string("");

    size_t total_len = 0;
    size_t sep_len = strlen(separator);

    for (int i = 0; i < a->count; i++) {
        if (a->elements[i].type == VAL_STRING) {
            total_len += strlen(AS_STRING(a->elements[i]));
        }
        if (i < a->count - 1) total_len += sep_len;
    }

    char* result = SAGE_ALLOC(total_len + 1);
    char* wp = result;  // Write pointer (O(n) instead of O(n²) strcat)

    for (int i = 0; i < a->count; i++) {
        if (a->elements[i].type == VAL_STRING) {
            size_t slen = strlen(AS_STRING(a->elements[i]));
            memcpy(wp, AS_STRING(a->elements[i]), slen);
            wp += slen;
        }
        if (i < a->count - 1) {
            memcpy(wp, separator, sep_len);
            wp += sep_len;
        }
    }
    *wp = '\0';

    return val_string_take(result);
}

char* string_replace(const char* str, const char* old, const char* new_str) {
    if (!str || !old || !new_str) return NULL;

    size_t old_len = strlen(old);
    size_t new_len = strlen(new_str);
    size_t str_len = strlen(str);

    // Count occurrences
    size_t count = 0;
    const char* tmp = str;
    while ((tmp = strstr(tmp, old)) != NULL) {
        count++;
        tmp += old_len;
    }

    if (count == 0) {
        char* result = SAGE_ALLOC(str_len + 1);
        memcpy(result, str, str_len + 1);
        return result;
    }

    size_t result_len = str_len + count * (new_len - old_len);
    char* result = SAGE_ALLOC(result_len + 1);
    char* wp = result;  // Write pointer (O(n) instead of O(n²) strcat)

    const char* src = str;
    const char* found;

    while ((found = strstr(src, old)) != NULL) {
        size_t prefix_len = (size_t)(found - src);
        memcpy(wp, src, prefix_len);
        wp += prefix_len;
        memcpy(wp, new_str, new_len);
        wp += new_len;
        src = found + old_len;
    }
    // Copy remaining tail
    size_t tail_len = strlen(src);
    memcpy(wp, src, tail_len + 1);

    return result;
}

char* string_upper(const char* str) {
    if (!str) return NULL;
    char* result = SAGE_ALLOC(strlen(str) + 1);
    for (int i = 0; str[i]; i++) {
        result[i] = toupper(str[i]);
    }
    result[strlen(str)] = '\0';
    return result;
}

char* string_lower(const char* str) {
    if (!str) return NULL;
    char* result = SAGE_ALLOC(strlen(str) + 1);
    for (int i = 0; str[i]; i++) {
        result[i] = tolower(str[i]);
    }
    result[strlen(str)] = '\0';
    return result;
}

char* string_strip(const char* str) {
    if (!str) return NULL;
    
    while (*str && isspace(*str)) str++;
    
    if (*str == '\0') {
        char* result = SAGE_ALLOC(1);
        result[0] = '\0';
        return result;
    }
    
    const char* end = str + strlen(str) - 1;
    while (end > str && isspace(*end)) end--;
    
    int len = end - str + 1;
    char* result = SAGE_ALLOC(len + 1);
    strncpy(result, str, len);
    result[len] = '\0';

    return result;
}

// ========== CLASS OPERATIONS ==========

ClassValue* class_create(const char* name, int name_len, ClassValue* parent) {
    gc_pin();  // Prevent GC during multi-step initialization
    ClassValue* class_val = gc_alloc(VAL_CLASS, sizeof(ClassValue));
    class_val->name = SAGE_ALLOC(name_len + 1);
    strncpy(class_val->name, name, name_len);
    class_val->name[name_len] = '\0';
    class_val->name_len = name_len;
    class_val->parent = parent;
    class_val->methods = NULL;
    class_val->method_count = 0;
    gc_unpin();
    return class_val;
}

void class_add_method(ClassValue* class_val, const char* name, int name_len, void* method_stmt) {
    class_val->methods = SAGE_REALLOC(class_val->methods, sizeof(Method) * (class_val->method_count + 1));
    
    Method* m = &class_val->methods[class_val->method_count];
    m->name = SAGE_ALLOC(name_len + 1);
    strncpy(m->name, name, name_len);
    m->name[name_len] = '\0';
    m->name_len = name_len;
    m->method_stmt = method_stmt;
    
    class_val->method_count++;
}

Method* class_find_method(ClassValue* class_val, const char* name, int name_len) {
    for (int i = 0; i < class_val->method_count; i++) {
        if (class_val->methods[i].name_len == name_len &&
            strncmp(class_val->methods[i].name, name, name_len) == 0) {
            return &class_val->methods[i];
        }
    }
    
    if (class_val->parent) {
        return class_find_method(class_val->parent, name, name_len);
    }
    
    return NULL;
}

// ========== INSTANCE OPERATIONS ==========

InstanceValue* instance_create(ClassValue* class_def) {
    gc_pin();  // Prevent GC between the two gc_alloc calls
    InstanceValue* instance = gc_alloc(VAL_INSTANCE, sizeof(InstanceValue));
    instance->class_def = class_def;

    Value fields_dict = val_dict();
    instance->fields = fields_dict.as.dict;
    gc_unpin();

    return instance;
}

void instance_set_field(InstanceValue* instance, const char* name, Value value) {
    if (!instance || !instance->fields) return;
    
    Value dict_val;
    dict_val.type = VAL_DICT;
    dict_val.as.dict = instance->fields;
    
    dict_set(&dict_val, name, value);
}

Value instance_get_field(InstanceValue* instance, const char* name) {
    if (!instance || !instance->fields) return val_nil();
    
    Value dict_val;
    dict_val.type = VAL_DICT;
    dict_val.as.dict = instance->fields;
    
    return dict_get(&dict_val, name);
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
                print_value(*(d->entries[i].value));
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
            if (t->count == 1) printf(",");
            printf(")");
            break;
        }
        
        case VAL_CLASS: {
            printf("<class %s>", v.as.class_val->name);
            break;
        }
        
        case VAL_INSTANCE: {
            printf("<instance of %s>", v.as.instance->class_def->name);
            break;
        }

        case VAL_MODULE: {
            printf("<module %s>", v.as.module->module->name);
            break;
        }
        
        case VAL_EXCEPTION: {
            printf("Exception: %s", v.as.exception->message);
            break;
        }
        
        case VAL_GENERATOR: {
            if (v.as.generator->is_exhausted) {
                printf("<generator (exhausted)>");
            } else if (v.as.generator->is_started) {
                printf("<generator (active)>");
            } else {
                printf("<generator>");
            }
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
        case VAL_FUNCTION: return a.as.function->proc == b.as.function->proc;
        case VAL_TUPLE: {
            TupleValue* ta = a.as.tuple;
            TupleValue* tb = b.as.tuple;
            if (ta->count != tb->count) return 0;
            for (int i = 0; i < ta->count; i++) {
                if (!values_equal(ta->elements[i], tb->elements[i])) return 0;
            }
            return 1;
        }
        case VAL_EXCEPTION: 
            return strcmp(a.as.exception->message, b.as.exception->message) == 0;
        case VAL_MODULE:
            return a.as.module->module == b.as.module->module;
        case VAL_GENERATOR:
            return a.as.generator == b.as.generator;  // Same generator object
        default: return 0;
    }
}
