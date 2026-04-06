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

Value val_bytes(const unsigned char* data, int length) {
    Value v;
    v.type = VAL_BYTES;
    v.as.bytes = gc_alloc(VAL_BYTES, sizeof(BytesValue));
    v.as.bytes->length = length;
    v.as.bytes->capacity = length > 0 ? length : 8;
    v.as.bytes->data = SAGE_ALLOC(v.as.bytes->capacity);
    if (data && length > 0) {
        memcpy(v.as.bytes->data, data, length);
    }
    return v;
}

Value val_bytes_empty(int capacity) {
    Value v;
    v.type = VAL_BYTES;
    v.as.bytes = gc_alloc(VAL_BYTES, sizeof(BytesValue));
    v.as.bytes->length = 0;
    v.as.bytes->capacity = capacity > 0 ? capacity : 8;
    v.as.bytes->data = SAGE_ALLOC(v.as.bytes->capacity);
    return v;
}

void bytes_push(Value* bytes_val, unsigned char byte) {
    if (bytes_val->type != VAL_BYTES) return;
    BytesValue* b = bytes_val->as.bytes;
    if (b->length >= b->capacity) {
        b->capacity = b->capacity * 2;
        b->data = SAGE_REALLOC(b->data, b->capacity);
    }
    b->data[b->length++] = byte;
}

Value val_function(void* proc, Env* closure) {
    Value v;
    v.type = VAL_FUNCTION;
    v.as.function = gc_alloc(VAL_FUNCTION, sizeof(FunctionValue));
    v.as.function->proc = proc;
    v.as.function->closure = closure;
    v.as.function->is_async = 0;
    v.as.function->is_vm = 0;
    v.as.function->vm_function = NULL;
    return v;
}

Value val_bytecode_function(BytecodeFunction* function, Env* closure) {
    Value v = val_function(NULL, closure);
    v.as.function->is_vm = 1;
    v.as.function->vm_function = function;
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
    gc_track_external_allocation(sizeof(Value) * (size_t)count);
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
    size_t msg_len = strlen(message);
    v.as.exception->message = SAGE_ALLOC(msg_len + 1);
    gc_track_external_allocation(msg_len + 1);
    memcpy(v.as.exception->message, message, msg_len + 1);
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

// Phase 9: FFI library handle constructor
Value val_clib(void* handle, const char* name) {
    Value v;
    v.type = VAL_CLIB;
    v.as.clib = SAGE_ALLOC(sizeof(CLibValue));
    v.as.clib->handle = handle;
    size_t name_len = strlen(name);
    v.as.clib->name = SAGE_ALLOC(name_len + 1);
    memcpy(v.as.clib->name, name, name_len + 1);
    return v;
}

// Phase 9: Raw pointer constructor
Value val_pointer(void* ptr, size_t size, int owned) {
    Value v;
    v.type = VAL_POINTER;
    v.as.pointer = SAGE_ALLOC(sizeof(PointerValue));
    v.as.pointer->ptr = ptr;
    v.as.pointer->size = size;
    v.as.pointer->owned = owned;
    return v;
}

Value val_thread(ThreadValue* tv) {
    Value v;
    v.type = VAL_THREAD;
    v.as.thread = tv;
    return v;
}

Value val_mutex(MutexValue* mv) {
    Value v;
    v.type = VAL_MUTEX;
    v.as.mutex = mv;
    return v;
}

// ========== ARRAY OPERATIONS ==========

void array_push(Value* arr, Value val) {
    if (arr->type != VAL_ARRAY) return;
    ArrayValue* a = arr->as.array;

    if (a->count >= a->capacity) {
        size_t old_bytes = sizeof(Value) * (size_t)a->capacity;
        a->capacity = a->capacity == 0 ? 4 : a->capacity * 2;
        a->elements = SAGE_REALLOC(a->elements, sizeof(Value) * a->capacity);
        gc_track_external_resize(old_bytes, sizeof(Value) * (size_t)a->capacity);
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
    GC_WRITE_BARRIER(a->elements[index]);  // SATB: shade old element
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
    gc_track_external_resize(sizeof(DictEntry) * (size_t)old_capacity,
                             sizeof(DictEntry) * (size_t)d->capacity);
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
        GC_WRITE_BARRIER(*(d->entries[slot].value));  // SATB: shade old value
        *(d->entries[slot].value) = value;
        return;
    }

    // New entry
    size_t klen = strlen(key);
    d->entries[slot].key = SAGE_ALLOC(klen + 1);
    gc_track_external_allocation(klen + 1);
    memcpy(d->entries[slot].key, key, klen + 1);
    d->entries[slot].hash = hash;
    d->entries[slot].value = SAGE_ALLOC(sizeof(Value));
    gc_track_external_allocation(sizeof(Value));
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
    gc_track_external_free(strlen(d->entries[slot].key) + 1);
    gc_track_external_free(sizeof(Value));
    free(d->entries[slot].key);
    free(d->entries[slot].value);
    d->entries[slot].key = NULL;
    d->entries[slot].value = NULL;
    d->count--;

    // Rehash subsequent entries to fix probe chain (backward-shift deletion)
    // Use modular distance to correctly handle wraparound
    int mask = d->capacity - 1;
    int idx = (slot + 1) & mask;
    while (d->entries[idx].key != NULL) {
        int natural = (int)(d->entries[idx].hash & (unsigned int)mask);
        // Entry needs to move if its natural slot is not between (slot, idx] circularly
        int dist_natural = (idx - natural + d->capacity) & mask;
        int dist_slot = (idx - slot + d->capacity) & mask;
        if (dist_natural >= dist_slot) {
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

    gc_pin();
    Value result = val_array();
    for (int i = 0; i < d->capacity; i++) {
        if (d->entries[i].key != NULL) {
            size_t klen = strlen(d->entries[i].key);
            char* key_copy = SAGE_ALLOC(klen + 1);
            memcpy(key_copy, d->entries[i].key, klen + 1);
            array_push(&result, val_string_take(key_copy));
        }
    }
    gc_unpin();
    return result;
}

Value dict_values(Value* dict) {
    if (dict->type != VAL_DICT) return val_nil();
    DictValue* d = dict->as.dict;

    gc_pin();
    Value result = val_array();
    for (int i = 0; i < d->capacity; i++) {
        if (d->entries[i].key != NULL) {
            array_push(&result, *(d->entries[i].value));
        }
    }
    gc_unpin();
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
    
    gc_pin();
    int del_len = strlen(delimiter);
    if (del_len == 0) {
        for (int i = 0; str[i]; i++) {
            char* ch = SAGE_ALLOC(2);
            ch[0] = str[i];
            ch[1] = '\0';
            array_push(&result, val_string_take(ch));
        }
        gc_unpin();
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
    
    size_t tail_len = strlen(start);
    char* part = SAGE_ALLOC(tail_len + 1);
    memcpy(part, start, tail_len + 1);
    array_push(&result, val_string_take(part));
    
    gc_unpin();
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

    // Use signed arithmetic to avoid underflow when new_len < old_len
    long long delta = (long long)new_len - (long long)old_len;
    size_t result_len = (size_t)((long long)str_len + (long long)count * delta);
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
    size_t len = strlen(str);
    char* result = SAGE_ALLOC(len + 1);
    for (size_t i = 0; i < len; i++) {
        result[i] = toupper((unsigned char)str[i]);
    }
    result[len] = '\0';
    return result;
}

char* string_lower(const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str);
    char* result = SAGE_ALLOC(len + 1);
    for (size_t i = 0; i < len; i++) {
        result[i] = tolower((unsigned char)str[i]);
    }
    result[len] = '\0';
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
    gc_track_external_allocation(name_len + 1);
    strncpy(class_val->name, name, name_len);
    class_val->name[name_len] = '\0';
    class_val->name_len = name_len;
    class_val->parent = parent;
    class_val->methods = NULL;
    class_val->method_count = 0;
    class_val->defining_env = NULL;
    gc_unpin();
    return class_val;
}

void class_add_method(ClassValue* class_val, const char* name, int name_len, void* method_stmt) {
    size_t old_bytes = sizeof(Method) * (size_t)class_val->method_count;
    class_val->methods = SAGE_REALLOC(class_val->methods, sizeof(Method) * (class_val->method_count + 1));
    gc_track_external_resize(old_bytes, sizeof(Method) * (size_t)(class_val->method_count + 1));
    
    Method* m = &class_val->methods[class_val->method_count];
    m->name = SAGE_ALLOC(name_len + 1);
    gc_track_external_allocation(name_len + 1);
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

ClassValue* class_find_method_owner(ClassValue* class_val, const char* name, int name_len) {
    for (int i = 0; i < class_val->method_count; i++) {
        if (class_val->methods[i].name_len == name_len &&
            strncmp(class_val->methods[i].name, name, name_len) == 0) {
            return class_val;
        }
    }
    if (class_val->parent) {
        return class_find_method_owner(class_val->parent, name, name_len);
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

static int print_depth = 0;
#define MAX_PRINT_DEPTH 32

void print_value(Value v) {
    if (++print_depth > MAX_PRINT_DEPTH) {
        printf("<...>");
        print_depth--;
        return;
    }
    switch (v.type) {
        case VAL_NUMBER: {
            double n = AS_NUMBER(v);
            if (n == (long long)n && n >= -9007199254740992.0 && n <= 9007199254740992.0) {
                printf("%lld", (long long)n);
            } else {
                printf("%g", n);
            }
            break;
        }
            
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
            int printed = 0;
            for (int i = 0; i < d->capacity; i++) {
                if (d->entries[i].key != NULL && d->entries[i].value != NULL) {
                    if (printed > 0) printf(", ");
                    printf("\"%s\": ", d->entries[i].key);
                    print_value(*(d->entries[i].value));
                    printed++;
                }
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
            if (v.as.instance && v.as.instance->class_def && v.as.instance->class_def->name) {
                printf("<instance of %s>", v.as.instance->class_def->name);
            } else {
                printf("<instance>");
            }
            break;
        }

        case VAL_MODULE: {
            if (v.as.module && v.as.module->module && v.as.module->module->name) {
                printf("<module %s>", v.as.module->module->name);
            } else {
                printf("<module>");
            }
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

        case VAL_CLIB: {
            printf("<clib \"%s\">", v.as.clib->name);
            break;
        }

        case VAL_POINTER: {
            printf("<pointer %p size=%zu>", v.as.pointer->ptr, v.as.pointer->size);
            break;
        }

        case VAL_THREAD: {
            printf("<thread %p>", v.as.thread->handle);
            break;
        }

        case VAL_MUTEX: {
            printf("<mutex %p>", v.as.mutex->handle);
            break;
        }

        case VAL_BYTES: {
            printf("b\"");
            for (int i = 0; i < v.as.bytes->length; i++) {
                unsigned char c = v.as.bytes->data[i];
                if (c >= 32 && c < 127 && c != '"' && c != '\\') {
                    putchar(c);
                } else {
                    printf("\\x%02x", c);
                }
            }
            printf("\"");
            break;
        }
    }
    print_depth--;
}

int values_equal(Value a, Value b) {
    if (a.type != b.type) return 0;
    switch (a.type) {
        case VAL_NUMBER: return AS_NUMBER(a) == AS_NUMBER(b);
        case VAL_BOOL:   return AS_BOOL(a) == AS_BOOL(b);
        case VAL_NIL:    return 1;
        case VAL_STRING:
            // Fast path: pointer equality (interned or same allocation)
            if (AS_STRING(a) == AS_STRING(b)) return 1;
            return strcmp(AS_STRING(a), AS_STRING(b)) == 0;
        case VAL_FUNCTION:
            if (a.as.function->is_vm != b.as.function->is_vm) return 0;
            if (a.as.function->is_vm) {
                return a.as.function->vm_function == b.as.function->vm_function;
            }
            return a.as.function->proc == b.as.function->proc;
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
        case VAL_CLIB:
            return a.as.clib->handle == b.as.clib->handle;
        case VAL_POINTER:
            return a.as.pointer->ptr == b.as.pointer->ptr;
        case VAL_THREAD:
            return a.as.thread == b.as.thread;
        case VAL_MUTEX:
            return a.as.mutex == b.as.mutex;
        case VAL_ARRAY: {
            ArrayValue* aa = a.as.array;
            ArrayValue* ab = b.as.array;
            if (aa == ab) return 1;
            if (aa->count != ab->count) return 0;
            for (int i = 0; i < aa->count; i++) {
                if (!values_equal(aa->elements[i], ab->elements[i])) return 0;
            }
            return 1;
        }
        case VAL_DICT: {
            DictValue* da = a.as.dict;
            DictValue* db = b.as.dict;
            if (da == db) return 1;
            if (da->count != db->count) return 0;
            for (int i = 0; i < da->capacity; i++) {
                if (da->entries[i].key == NULL) continue;
                if (!dict_has(&b, da->entries[i].key)) return 0;
                Value vb = dict_get(&b, da->entries[i].key);
                if (!values_equal(*da->entries[i].value, vb)) return 0;
            }
            return 1;
        }
        case VAL_INSTANCE: {
            InstanceValue* ia = a.as.instance;
            InstanceValue* ib = b.as.instance;
            if (ia == ib) return 1;
            if (ia->class_def != ib->class_def) return 0;
            Value da = (Value){ .type = VAL_DICT, .as.dict = ia->fields };
            Value db = (Value){ .type = VAL_DICT, .as.dict = ib->fields };
            return values_equal(da, db);
        }
        case VAL_CLASS:
            return a.as.class_val == b.as.class_val;
        case VAL_BYTES: {
            BytesValue* ba = a.as.bytes;
            BytesValue* bb = b.as.bytes;
            if (ba == bb) return 1;
            if (ba->length != bb->length) return 0;
            return memcmp(ba->data, bb->data, ba->length) == 0;
        }
        default: return 0;
    }
}
