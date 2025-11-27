#ifndef SAGE_VALUE_H
#define SAGE_VALUE_H

struct Value;
typedef struct Value Value;
typedef Value (*NativeFn)(int argCount, Value* args);

// Array structure
typedef struct {
    Value* elements;
    int count;
    int capacity;
} ArrayValue;

// Dictionary entry (key-value pair)
typedef struct {
    char* key;
    Value value;
} DictEntry;

// Dictionary structure (simple hash map)
typedef struct {
    DictEntry* entries;
    int count;
    int capacity;
} DictValue;

// Tuple structure (fixed-size, immutable)
typedef struct {
    Value* elements;
    int count;
} TupleValue;

typedef enum {
    VAL_NUMBER,
    VAL_BOOL,
    VAL_NIL,
    VAL_STRING,
    VAL_FUNCTION,
    VAL_NATIVE,
    VAL_ARRAY,
    VAL_DICT,
    VAL_TUPLE
} ValueType;

struct Value {
    ValueType type;
    union {
        double number;
        int boolean;
        char* string;
        NativeFn native;
        ArrayValue* array;
        DictValue* dict;
        TupleValue* tuple;
    } as;
};

// Macros for checking type
#define IS_NUMBER(v) ((v).type == VAL_NUMBER)
#define IS_BOOL(v)   ((v).type == VAL_BOOL)
#define IS_NIL(v)    ((v).type == VAL_NIL)
#define IS_STRING(v) ((v).type == VAL_STRING)
#define IS_ARRAY(v)  ((v).type == VAL_ARRAY)
#define IS_DICT(v)   ((v).type == VAL_DICT)
#define IS_TUPLE(v)  ((v).type == VAL_TUPLE)

// Macros for accessing values (unsafe if unchecked)
#define AS_NUMBER(v) ((v).as.number)
#define AS_BOOL(v)   ((v).as.boolean)
#define AS_STRING(v) ((v).as.string)
#define AS_ARRAY(v)  ((v).as.array)
#define AS_DICT(v)   ((v).as.dict)
#define AS_TUPLE(v)  ((v).as.tuple)

// Constructors
Value val_number(double value);
Value val_bool(int value);
Value val_nil();
Value val_string(char* value);
Value val_native(NativeFn fn);
Value val_array();
Value val_dict();
Value val_tuple(Value* elements, int count);

// Helpers
void print_value(Value v);
int values_equal(Value a, Value b);

// Array operations
void array_push(Value* arr, Value val);
Value array_get(Value* arr, int index);
void array_set(Value* arr, int index, Value val);
Value array_slice(Value* arr, int start, int end);

// Dictionary operations
void dict_set(Value* dict, const char* key, Value value);
Value dict_get(Value* dict, const char* key);
int dict_has(Value* dict, const char* key);
void dict_delete(Value* dict, const char* key);
Value dict_keys(Value* dict);
Value dict_values(Value* dict);

// Tuple operations
Value tuple_get(Value* tuple, int index);

// String operations
Value string_split(const char* str, const char* delimiter);
Value string_join(Value* arr, const char* separator);
char* string_replace(const char* str, const char* old, const char* new_str);
char* string_upper(const char* str);
char* string_lower(const char* str);
char* string_strip(const char* str);

#endif