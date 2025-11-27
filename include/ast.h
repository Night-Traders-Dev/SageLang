#ifndef SAGE_AST_H
#define SAGE_AST_H

#include "token.h"

// --- Expression Types ---
typedef struct Expr Expr;

typedef struct {
    double value;
} NumberExpr;

typedef struct {
    Token op;
    Expr* left;
    Expr* right;
} BinaryExpr;

typedef struct {
    Token name;
} VariableExpr;

typedef struct {
    Token callee;
    Expr** args;
    int arg_count;
} CallExpr;

typedef struct {
    char* value;
} StringExpr;

typedef struct {
    int value;
} BoolExpr;

typedef struct {
    Expr** elements;
    int count;
} ArrayExpr;

typedef struct {
    Expr* array;
    Expr* index;
} IndexExpr;

// Dictionary literal: {"key1": val1, "key2": val2}
typedef struct {
    char** keys;     // Array of string keys
    Expr** values;   // Array of value expressions
    int count;
} DictExpr;

// Tuple literal: (val1, val2, val3)
typedef struct {
    Expr** elements;
    int count;
} TupleExpr;

// Slice expression: arr[start:end]
typedef struct {
    Expr* array;
    Expr* start;  // Can be NULL for [:end]
    Expr* end;    // Can be NULL for [start:]
} SliceExpr;

struct Expr {
    enum {
        EXPR_NUMBER,
        EXPR_STRING,
        EXPR_BOOL,
        EXPR_NIL,
        EXPR_BINARY,
        EXPR_VARIABLE,
        EXPR_CALL,
        EXPR_ARRAY,
        EXPR_INDEX,
        EXPR_DICT,
        EXPR_TUPLE,
        EXPR_SLICE
    } type;
    union {
        NumberExpr number;
        StringExpr string;
        BoolExpr boolean;
        BinaryExpr binary;
        VariableExpr variable;
        CallExpr call;
        ArrayExpr array;
        IndexExpr index;
        DictExpr dict;
        TupleExpr tuple;
        SliceExpr slice;
    } as;
};

// --- Statement Types ---
typedef struct Stmt Stmt;

typedef struct {
    Expr* expression;
} PrintStmt;

typedef struct {
    Token name;
    Expr* initializer;
} LetStmt;

typedef struct {
    Expr* condition;
    Stmt* then_branch;
    Stmt* else_branch;
} IfStmt;

typedef struct {
    struct Stmt* statements;
} BlockStmt;

typedef struct {
    Expr* condition;
    Stmt* body;
} WhileStmt;

typedef struct {
    Token name;
    Token* params;
    int param_count;
    Stmt* body;
} ProcStmt;

typedef struct {
    Expr* value;
} ReturnStmt;

typedef struct {
    Token variable;  // Loop variable (e.g., 'i' or 'item')
    Expr* iterable;  // What we're iterating over (array or range)
    Stmt* body;      // Loop body
} ForStmt;

struct Stmt {
    enum {
        STMT_PRINT,
        STMT_EXPRESSION,
        STMT_LET,
        STMT_IF,
        STMT_BLOCK,
        STMT_WHILE,
        STMT_PROC,
        STMT_FOR,
        STMT_RETURN,
        STMT_BREAK,
        STMT_CONTINUE
    } type;
    union {
        PrintStmt print;
        LetStmt let;
        IfStmt if_stmt;
        BlockStmt block;
        WhileStmt while_stmt;
        ProcStmt proc;
        ReturnStmt ret;
        ForStmt for_stmt;
        Expr* expression;
    } as;
    Stmt* next;
};

// Expression Constructors
Expr* new_number_expr(double value);
Expr* new_binary_expr(Expr* left, Token op, Expr* right);
Expr* new_variable_expr(Token name);
Expr* new_call_expr(Token callee, Expr** args, int arg_count);
Expr* new_string_expr(char* value);
Expr* new_bool_expr(int value);
Expr* new_nil_expr();
Expr* new_array_expr(Expr** elements, int count);
Expr* new_index_expr(Expr* array, Expr* index);
Expr* new_dict_expr(char** keys, Expr** values, int count);
Expr* new_tuple_expr(Expr** elements, int count);
Expr* new_slice_expr(Expr* array, Expr* start, Expr* end);

// Statement Constructors
Stmt* new_print_stmt(Expr* expression);
Stmt* new_expr_stmt(Expr* expression);
Stmt* new_let_stmt(Token name, Expr* initializer);
Stmt* new_if_stmt(Expr* condition, Stmt* then_branch, Stmt* else_branch);
Stmt* new_block_stmt(Stmt* statements);
Stmt* new_while_stmt(Expr* condition, Stmt* body);
Stmt* new_proc_stmt(Token name, Token* params, int param_count, Stmt* body);
Stmt* new_for_stmt(Token variable, Expr* iterable, Stmt* body);
Stmt* new_return_stmt(Expr* value);
Stmt* new_break_stmt();
Stmt* new_continue_stmt();

#endif