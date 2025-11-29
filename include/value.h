#ifndef SAGE_VALUE_H
#define SAGE_VALUE_H

// Forward declarations
typedef struct Value Value;
typedef struct ClassValue ClassValue;
typedef struct InstanceValue InstanceValue;
typedef struct Env Env;  // Forward declare from env.h
typedef Env Environment;  // Alias for compatibility
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
    Value* value;
} DictEntry;

// Dictionary structure (simple hash map)
typedef struct {
    DictEntry* entries;  // FIXED: was DictValue* entries
    int count;
    int capacity;
} DictValue;

// Tuple structure (fixed-size, immutable)
typedef struct {
    Value* elements;
    int count;
} TupleValue;

// Method structure
typedef struct {
    char* name;
    int name_len;
    void* method_stmt;  // Pointer to ProcStmt (avoid circular dependency)
} Method;

// Class structure
struct ClassValue {
    char* name;
    int name_len;
    ClassValue* parent;  // For inheritance
    Method* methods;
    int method_count;
};

// Instance structure
struct InstanceValue {
    ClassValue* class_def;
    DictValue* fields;  // Instance variables
};

// PHASE 7: Exception structure
typedef struct {
    char* message;  // Error message
} ExceptionValue;

// PHASE 7: Generator structure (for yield support)
typedef struct {
    void* body;              // Pointer to Stmt (function body containing yields)
    void* params;            // Pointer to Token array (parameters)
    int param_count;         // Number of parameters
    Env* closure;            // Captured environment when generator was created
    Env* gen_env;            // Generator's execution environment (preserved state)
    int is_started;          // Has generator been started?
    int is_exhausted;        // Has generator finished?
    void* current_stmt;      // Current statement position (for resumption)
} GeneratorValue;

typedef enum {
    VAL_NUMBER,
    VAL_BOOL,
    VAL_NIL,
    VAL_STRING,
    VAL_FUNCTION,
    VAL_NATIVE,
    VAL_ARRAY,
    VAL_DICT,
    VAL_TUPLE,
    VAL_CLASS,
    VAL_INSTANCE,
    VAL_EXCEPTION,
    VAL_GENERATOR  // NEW: Generator type
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
        ClassValue* class_val;
        InstanceValue* instance;
        ExceptionValue* exception;
        GeneratorValue* generator;  // NEW: Generator value
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
#define IS_CLASS(v)  ((v).type == VAL_CLASS)
#define IS_INSTANCE(v) ((v).type == VAL_INSTANCE)
#define IS_EXCEPTION(v) ((v).type == VAL_EXCEPTION)
#define IS_GENERATOR(v) ((v).type == VAL_GENERATOR)  // NEW

// Macros for accessing values
#define AS_NUMBER(v) ((v).as.number)
#define AS_BOOL(v)   ((v).as.boolean)
#define AS_STRING(v) ((v).as.string)
#define AS_ARRAY(v)  ((v).as.array)
#define AS_DICT(v)   ((v).as.dict)
#define AS_TUPLE(v)  ((v).as.tuple)
#define AS_CLASS(v)  ((v).as.class_val)
#define AS_INSTANCE(v) ((v).as.instance)
#define AS_EXCEPTION(v) ((v).as.exception)
#define AS_GENERATOR(v) ((v).as.generator)  // NEW

// Constructors
Value val_number(double value);
Value val_bool(int value);
Value val_nil();
Value val_string(char* value);
Value val_native(NativeFn fn);
Value val_array();
Value val_dict();
Value val_tuple(Value* elements, int count);
Value val_class(ClassValue* class_val);
Value val_instance(InstanceValue* instance);
Value val_exception(const char* message);
Value val_generator(void* body, void* params, int param_count, Env* closure);  // NEW

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

// Class operations
ClassValue* class_create(const char* name, int name_len, ClassValue* parent);
void class_add_method(ClassValue* class_val, const char* name, int name_len, void* method_stmt);
Method* class_find_method(ClassValue* class_val, const char* name, int name_len);

// Instance operations
InstanceValue* instance_create(ClassValue* class_def);
void instance_set_field(InstanceValue* instance, const char* name, Value value);
Value instance_get_field(InstanceValue* instance, const char* name);

#endif