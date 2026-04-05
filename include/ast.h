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
    Expr* callee;
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

// Index assignment: arr[i] = val, dict[key] = val
typedef struct {
    Expr* array;
    Expr* index;
    Expr* value;
} IndexSetExpr;

// Dictionary literal: {"key1": val1, "key2": val2}
typedef struct {
    char** keys;
    Expr** values;
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
    Expr* start;
    Expr* end;
} SliceExpr;

// Property access: object.property
typedef struct {
    Expr* object;
    Token property;
} GetExpr;

// Property assignment: object.property = value
typedef struct {
    Expr* object;
    Token property;
    Expr* value;
} SetExpr;

// Await expression: await expr
typedef struct {
    Expr* expression;
} AwaitExpr;

// Super expression: super.method(args)
typedef struct {
    Token method;   // The method name after super.
} SuperExpr;

// Comptime expression: comptime value evaluated at compile time
typedef struct {
    Expr* expression;   // Expression to evaluate at compile time (single-expression form)
} ComptimeExpr;

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
        EXPR_SLICE,
        EXPR_GET,
        EXPR_SET,
        EXPR_INDEX_SET,
        EXPR_AWAIT,
        EXPR_SUPER,
        EXPR_COMPTIME       // Phase 17: compile-time expression
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
        IndexSetExpr index_set;
        DictExpr dict;
        TupleExpr tuple;
        SliceExpr slice;
        GetExpr get;
        SetExpr set;
        AwaitExpr await;
        SuperExpr super_expr;
        ComptimeExpr comptime;
    } as;
};

// --- Statement Types ---
typedef struct Stmt Stmt;

typedef struct {
    Expr* expression;
} PrintStmt;

// Type annotation (e.g., Int, String, Array[Int], Dict[String, Int])
typedef struct TypeAnnotation {
    Token name;                     // Base type name (e.g., "Int", "Array")
    struct TypeAnnotation** params; // Generic type parameters (e.g., [Int] in Array[Int])
    int param_count;
    int is_optional;                // T? syntax
} TypeAnnotation;

typedef struct {
    Token name;
    TypeAnnotation* type_ann;   // Optional type annotation (NULL if none)
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
    TypeAnnotation** param_types;  // Per-parameter type annotations (NULL entries if untyped)
    Expr** defaults;               // Default value expressions (NULL if no default)
    int param_count;
    int required_count;            // Number of params without defaults
    TypeAnnotation* return_type;   // Return type annotation (NULL if none)
    char* doc;                     // Doc comment (NULL if none)
    Token* type_params;            // Phase 17: Generic type parameters [T, U] (NULL if none)
    int type_param_count;          // Phase 17: Number of generic type parameters
    Stmt* body;
} ProcStmt;

typedef struct {
    Expr* value;
} ReturnStmt;

typedef struct {
    Token variable;
    Expr* iterable;
    Stmt* body;
} ForStmt;

// Class definition: class Name(Parent): ...
typedef struct {
    Token name;
    Token parent;  // Optional parent class
    int has_parent;
    Stmt* methods;  // Linked list of method definitions (ProcStmt)
} ClassStmt;

// Struct declaration: struct Point: x: Int, y: Int
typedef struct {
    Token name;
    Token* field_names;
    TypeAnnotation** field_types;
    int field_count;
    Token* type_params;            // Phase 17: Generic type parameters [T, U] (NULL if none)
    int type_param_count;          // Phase 17: Number of generic type parameters
} StructStmt;

// Enum declaration: enum Color: Red, Green, Blue
typedef struct {
    Token name;
    Token* variant_names;
    int variant_count;
} EnumStmt;

// Trait declaration: trait Printable: proc to_string(self) -> String
typedef struct {
    Token name;
    Stmt* methods;  // Linked list of proc signatures (ProcStmt with no body or empty body)
} TraitStmt;

// Match expression: match value: case pattern: ...
typedef struct {
    Expr* pattern;  // Pattern to match against
    Expr* guard;    // Optional guard: case X if cond (NULL if no guard)
    Stmt* body;     // Code to execute if matched
} CaseClause;

typedef struct {
    Expr* value;           // Value to match
    CaseClause** cases;    // Array of case clauses
    int case_count;
    Stmt* default_case;    // Optional default clause
} MatchStmt;

// PHASE 7: Defer statement
typedef struct {
    Stmt* statement;  // Statement to execute on scope exit
} DeferStmt;

// PHASE 7: Exception handling
typedef struct {
    Token exception_var;   // Variable to bind exception to
    Stmt* body;            // Code to execute if exception caught
} CatchClause;

typedef struct {
    Stmt* try_block;       // Code to try
    CatchClause** catches; // Array of catch handlers
    int catch_count;
    Stmt* finally_block;   // Optional finally block (always executes)
} TryStmt;

typedef struct {
    Expr* exception;       // Exception value to raise
} RaiseStmt;

// PHASE 7: Yield statement (generators)
typedef struct {
    Expr* value;  // Expression to yield (can be NULL for yield without value)
} YieldStmt;

// Phase 17: Pragma/decorator annotation
typedef struct Pragma {
    char* name;             // Pragma name (e.g., "packed", "inline", "section")
    char** args;            // Optional arguments (e.g., ".multiboot_header")
    int arg_count;
    struct Pragma* next;    // Linked list
} Pragma;

// Phase 17: Comptime block statement
typedef struct {
    Stmt* body;             // Block of code to execute at compile time
} ComptimeStmt;

// Phase 17: Macro definition
typedef struct {
    Token name;
    Token* params;          // Parameter names (AST node params)
    int param_count;
    Stmt* body;             // Macro body (contains quote blocks)
} MacroDefStmt;

typedef struct {
    char* module_name;      // Name of module to import
    char** items;           // Items to import (NULL for "import module")
    char** item_aliases;    // ✅ NEW: Aliases for items (from X import Y as Z)
    int item_count;         // Number of items (0 for "import module")
    char* alias;            // Alias for module (import X as Y)
    int import_all;         // 1 for "import module", 0 for "from module import"
} ImportStmt;

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
        STMT_CONTINUE,
        STMT_CLASS,
        STMT_MATCH,
        STMT_DEFER,
        STMT_TRY,
        STMT_RAISE,
        STMT_YIELD,     // Phase 7: Generator yield
        STMT_IMPORT,    // Phase 8: Module import
        STMT_ASYNC_PROC, // Phase 11: Async procedure
        STMT_STRUCT,    // Phase 1.7: Struct declaration
        STMT_ENUM,      // Phase 1.7: Enum declaration
        STMT_TRAIT,     // Phase 1.7: Trait declaration
        STMT_COMPTIME,  // Phase 17: Compile-time block
        STMT_MACRO_DEF  // Phase 17: Macro definition
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
        ClassStmt class_stmt;
        MatchStmt match_stmt;
        DeferStmt defer;
        TryStmt try_stmt;
        RaiseStmt raise;
        YieldStmt yield_stmt;   // Phase 7: Generator yield
        ImportStmt import;      // Phase 8: Module import
        ProcStmt async_proc;    // Phase 11: Async procedure (same layout as proc)
        StructStmt struct_stmt; // Phase 1.7: Struct declaration
        EnumStmt enum_stmt;     // Phase 1.7: Enum declaration
        TraitStmt trait_stmt;   // Phase 1.7: Trait declaration
        ComptimeStmt comptime;  // Phase 17: Compile-time block
        MacroDefStmt macro_def; // Phase 17: Macro definition
        Expr* expression;
    } as;
    Pragma* pragmas;            // Phase 17: Pragma/decorator list (NULL if none)
    Stmt* next;
};

// Expression Constructors
Expr* new_number_expr(double value);
Expr* new_binary_expr(Expr* left, Token op, Expr* right);
Expr* new_variable_expr(Token name);
Expr* new_call_expr(Expr* callee, Expr** args, int arg_count);
Expr* new_string_expr(char* value);
Expr* new_bool_expr(int value);
Expr* new_nil_expr();
Expr* new_array_expr(Expr** elements, int count);
Expr* new_index_expr(Expr* array, Expr* index);
Expr* new_index_set_expr(Expr* array, Expr* index, Expr* value);
Expr* new_dict_expr(char** keys, Expr** values, int count);
Expr* new_tuple_expr(Expr** elements, int count);
Expr* new_slice_expr(Expr* array, Expr* start, Expr* end);
Expr* new_get_expr(Expr* object, Token property);
Expr* new_set_expr(Expr* object, Token property, Expr* value);
Expr* new_await_expr(Expr* expression);
Expr* new_super_expr(Token method);
Expr* new_comptime_expr(Expr* expression);  // Phase 17

// Statement Constructors
Stmt* new_print_stmt(Expr* expression);
Stmt* new_expr_stmt(Expr* expression);
TypeAnnotation* new_type_annotation(Token name, TypeAnnotation** params, int param_count, int is_optional);
Stmt* new_let_stmt(Token name, Expr* initializer);
Stmt* new_if_stmt(Expr* condition, Stmt* then_branch, Stmt* else_branch);
Stmt* new_block_stmt(Stmt* statements);
Stmt* new_while_stmt(Expr* condition, Stmt* body);
Stmt* new_proc_stmt(Token name, Token* params, int param_count, Stmt* body);
Stmt* new_for_stmt(Token variable, Expr* iterable, Stmt* body);
Stmt* new_return_stmt(Expr* value);
Stmt* new_break_stmt();
Stmt* new_continue_stmt();
Stmt* new_class_stmt(Token name, Token parent, int has_parent, Stmt* methods);
Stmt* new_struct_stmt(Token name, Token* field_names, TypeAnnotation** field_types, int field_count);
Stmt* new_enum_stmt(Token name, Token* variant_names, int variant_count);
Stmt* new_trait_stmt(Token name, Stmt* methods);
Stmt* new_match_stmt(Expr* value, CaseClause** cases, int case_count, Stmt* default_case);
CaseClause* new_case_clause(Expr* pattern, Stmt* body);
Stmt* new_defer_stmt(Stmt* statement);
Stmt* new_try_stmt(Stmt* try_block, CatchClause** catches, int catch_count, Stmt* finally_block);
CatchClause* new_catch_clause(Token exception_var, Stmt* body);
Stmt* new_raise_stmt(Expr* exception);
Stmt* new_yield_stmt(Expr* value);  // Phase 7: Generator yield constructor
Stmt* new_import_stmt(char* module_name, char** items, char** item_aliases, int item_count, char* alias, int import_all);  // Phase 8: Import constructor
Stmt* new_async_proc_stmt(Token name, Token* params, int param_count, Stmt* body);  // Phase 11: Async proc
Stmt* new_comptime_stmt(Stmt* body);  // Phase 17: Compile-time block
Stmt* new_macro_def_stmt(Token name, Token* params, int param_count, Stmt* body);  // Phase 17: Macro definition
Pragma* new_pragma(char* name, char** args, int arg_count);  // Phase 17: Pragma constructor
void free_pragma(Pragma* pragma);  // Phase 17: Pragma cleanup

// AST cleanup
void free_expr(Expr* expr);
void free_stmt(Stmt* stmt);

#endif
