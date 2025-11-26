#include <stdlib.h>
#include "ast.h"

Expr* new_number_expr(double value) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_NUMBER;
    e->as.number.value = value;
    return e;
}

Expr* new_binary_expr(Expr* left, Token op, Expr* right) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_BINARY;
    e->as.binary.left = left;
    e->as.binary.op = op;
    e->as.binary.right = right;
    return e;
}

Expr* new_variable_expr(Token name) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_VARIABLE;
    e->as.variable.name = name;
    return e;
}

Expr* new_call_expr(Token callee, Expr** args, int arg_count) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_CALL;
    e->as.call.callee = callee;
    e->as.call.args = args;
    e->as.call.arg_count = arg_count;
    return e;
}

Expr* new_string_expr(char* value) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_STRING;
    e->as.string.value = value;
    return e;
}

Expr* new_bool_expr(int value) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_BOOL;
    e->as.boolean.value = value;
    return e;
}

Expr* new_nil_expr() {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_NIL;
    return e;
}

Expr* new_array_expr(Expr** elements, int count) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_ARRAY;
    e->as.array.elements = elements;
    e->as.array.count = count;
    return e;
}

Expr* new_index_expr(Expr* array, Expr* index) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_INDEX;
    e->as.index.array = array;
    e->as.index.index = index;
    return e;
}



Stmt* new_print_stmt(Expr* expression) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_PRINT;
    s->as.print.expression = expression;
    s->next = NULL;
    return s;
}

Stmt* new_expr_stmt(Expr* expression) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_EXPRESSION;
    s->as.expression = expression;
    s->next = NULL;
    return s;
}

Stmt* new_let_stmt(Token name, Expr* initializer) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_LET;
    s->as.let.name = name;
    s->as.let.initializer = initializer;
    s->next = NULL;
    return s;
}

Stmt* new_if_stmt(Expr* condition, Stmt* then_branch, Stmt* else_branch) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_IF;
    s->as.if_stmt.condition = condition;
    s->as.if_stmt.then_branch = then_branch;
    s->as.if_stmt.else_branch = else_branch;
    s->next = NULL;
    return s;
}

Stmt* new_for_stmt(Token variable, Expr* iterable, Stmt* body) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_FOR;
    s->as.for_stmt.variable = variable;
    s->as.for_stmt.iterable = iterable;
    s->as.for_stmt.body = body;
    s->next = NULL;
    return s;
}


Stmt* new_block_stmt(Stmt* statements) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_BLOCK;
    s->as.block.statements = statements;
    s->next = NULL;
    return s;
}

Stmt* new_while_stmt(Expr* condition, Stmt* body) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_WHILE;
    s->as.while_stmt.condition = condition;
    s->as.while_stmt.body = body;
    s->next = NULL;
    return s;
}

Stmt* new_proc_stmt(Token name, Token* params, int param_count, Stmt* body) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_PROC;
    s->as.proc.name = name;
    s->as.proc.params = params;
    s->as.proc.param_count = param_count;
    s->as.proc.body = body;
    s->next = NULL;
    return s;
}

Stmt* new_return_stmt(Expr* value) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_RETURN;
    s->as.ret.value = value;
    s->next = NULL;
    return s;
}
