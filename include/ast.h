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

struct Expr {
    enum {
        EXPR_NUMBER,
        EXPR_BINARY,
        EXPR_VARIABLE
    } type;
    union {
        NumberExpr number;
        BinaryExpr binary;
        VariableExpr variable;
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
    Stmt* else_branch; // may be NULL
} IfStmt;

typedef struct {
    Expr* condition;
    Stmt* body;
} WhileStmt;

typedef struct {
    struct Stmt* statements; // Head of a linked list of statements
} BlockStmt;

struct Stmt {
    enum {
        STMT_PRINT,
        STMT_EXPRESSION,
        STMT_LET,
        STMT_IF,
        STMT_WHILE,
        STMT_BLOCK
    } type;
    union {
        PrintStmt print;
        LetStmt let;
        IfStmt if_stmt;
        WhileStmt while_stmt;
        BlockStmt block;
        Expr* expression;
    } as;
    Stmt* next;
};

// Constructors
Expr* new_number_expr(double value);
Expr* new_binary_expr(Expr* left, Token op, Expr* right);
Expr* new_variable_expr(Token name);

Stmt* new_print_stmt(Expr* expression);
Stmt* new_expr_stmt(Expr* expression);
Stmt* new_let_stmt(Token name, Expr* initializer);
Stmt* new_if_stmt(Expr* condition, Stmt* then_branch, Stmt* else_branch);
Stmt* new_while_stmt(Expr* condition, Stmt* body);
Stmt* new_block_stmt(Stmt* statements);

#endif
