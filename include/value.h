#ifndef SAGE_VALUE_H
#define SAGE_VALUE_H

struct Value;
typedef struct Value Value;
typedef Value (*NativeFn)(int argCount, Value* args);

typedef enum {
    VAL_NUMBER,
    VAL_BOOL,
    VAL_NIL,
    VAL_STRING,
    VAL_FUNCTION,
    VAL_NATIVE
} ValueType;

struct Value {
    ValueType type;
    union {
        double number;
        int boolean;
        char* string; // Simple heap-allocated string for now
        NativeFn native;
    } as;
};

// Macros for checking type
#define IS_NUMBER(v) ((v).type == VAL_NUMBER)
#define IS_BOOL(v)   ((v).type == VAL_BOOL)
#define IS_NIL(v)    ((v).type == VAL_NIL)
#define IS_STRING(v) ((v).type == VAL_STRING)

// Macros for accessing values (unsafe if unchecked)
#define AS_NUMBER(v) ((v).as.number)
#define AS_BOOL(v)   ((v).as.boolean)
#define AS_STRING(v) ((v).as.string)

// Constructors
Value val_number(double value);
Value val_bool(int value);
Value val_nil();
Value val_string(char* value);
Value val_native(NativeFn fn);

// Helpers
void print_value(Value v);
int values_equal(Value a, Value b);

#endif
