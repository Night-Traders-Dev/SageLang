#include <stdlib.h>
#include <string.h>
#include "ast.h"

// ========== EXPRESSION CONSTRUCTORS ==========

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

Expr* new_dict_expr(char** keys, Expr** values, int count) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_DICT;
    e->as.dict.keys = keys;
    e->as.dict.values = values;
    e->as.dict.count = count;
    return e;
}

Expr* new_tuple_expr(Expr** elements, int count) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_TUPLE;
    e->as.tuple.elements = elements;
    e->as.tuple.count = count;
    return e;
}

Expr* new_slice_expr(Expr* array, Expr* start, Expr* end) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_SLICE;
    e->as.slice.array = array;
    e->as.slice.start = start;
    e->as.slice.end = end;
    return e;
}

Expr* new_get_expr(Expr* object, Token property) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_GET;
    e->as.get.object = object;
    e->as.get.property = property;
    return e;
}

Expr* new_set_expr(Expr* object, Token property, Expr* value) {
    Expr* e = malloc(sizeof(Expr));
    e->type = EXPR_SET;
    e->as.set.object = object;
    e->as.set.property = property;
    e->as.set.value = value;
    return e;
}

// ========== STATEMENT CONSTRUCTORS ==========

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

Stmt* new_break_stmt() {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_BREAK;
    s->next = NULL;
    return s;
}

Stmt* new_continue_stmt() {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_CONTINUE;
    s->next = NULL;
    return s;
}

Stmt* new_class_stmt(Token name, Token parent, int has_parent, Stmt* methods) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_CLASS;
    s->as.class_stmt.name = name;
    s->as.class_stmt.parent = parent;
    s->as.class_stmt.has_parent = has_parent;
    s->as.class_stmt.methods = methods;
    s->next = NULL;
    return s;
}

// ========== PHASE 7: MATCH EXPRESSION ==========

CaseClause* new_case_clause(Expr* pattern, Stmt* body) {
    CaseClause* c = malloc(sizeof(CaseClause));
    c->pattern = pattern;
    c->body = body;
    return c;
}

Stmt* new_match_stmt(Expr* value, CaseClause** cases, int case_count, Stmt* default_case) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_MATCH;
    s->as.match_stmt.value = value;
    s->as.match_stmt.cases = cases;
    s->as.match_stmt.case_count = case_count;
    s->as.match_stmt.default_case = default_case;
    s->next = NULL;
    return s;
}

// ========== PHASE 7: DEFER STATEMENT ==========

Stmt* new_defer_stmt(Stmt* statement) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_DEFER;
    s->as.defer.statement = statement;
    s->next = NULL;
    return s;
}

// ========== PHASE 7: EXCEPTION HANDLING ==========

CatchClause* new_catch_clause(Token exception_var, Stmt* body) {
    CatchClause* c = malloc(sizeof(CatchClause));
    c->exception_var = exception_var;
    c->body = body;
    return c;
}

Stmt* new_try_stmt(Stmt* try_block, CatchClause** catches, int catch_count, Stmt* finally_block) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_TRY;
    s->as.try_stmt.try_block = try_block;
    s->as.try_stmt.catches = catches;
    s->as.try_stmt.catch_count = catch_count;
    s->as.try_stmt.finally_block = finally_block;
    s->next = NULL;
    return s;
}

Stmt* new_raise_stmt(Expr* exception) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_RAISE;
    s->as.raise.exception = exception;
    s->next = NULL;
    return s;
}

// ========== PHASE 7: GENERATORS (YIELD) ==========

Stmt* new_yield_stmt(Expr* value) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_YIELD;
    s->as.yield_stmt.value = value;
    s->next = NULL;
    return s;
}

// ========== PHASE 8: MODULE IMPORTS ==========

Stmt* new_import_stmt(char* module_name, char** items, int item_count, char* alias, int import_all) {
    Stmt* s = malloc(sizeof(Stmt));
    s->type = STMT_IMPORT;
    s->as.import.module_name = strdup(module_name);
    s->as.import.items = items;
    s->as.import.item_count = item_count;
    s->as.import.alias = alias ? strdup(alias) : NULL;
    s->as.import.import_all = import_all;
    s->next = NULL;
    return s;
}
