#include <stdlib.h>
#include <string.h>
#include "ast.h"
#include "gc.h"

// ========== EXPRESSION CONSTRUCTORS ==========

Expr* new_number_expr(double value) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_NUMBER;
    e->as.number.value = value;
    return e;
}

Expr* new_binary_expr(Expr* left, Token op, Expr* right) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_BINARY;
    e->as.binary.left = left;
    e->as.binary.op = op;
    e->as.binary.right = right;
    return e;
}

Expr* new_variable_expr(Token name) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_VARIABLE;
    e->as.variable.name = name;
    return e;
}

Expr* new_call_expr(Expr* callee, Expr** args, int arg_count) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_CALL;
    e->as.call.callee = callee;
    e->as.call.args = args;
    e->as.call.arg_count = arg_count;
    return e;
}

Expr* new_string_expr(char* value) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_STRING;
    e->as.string.value = value;
    return e;
}

Expr* new_bool_expr(int value) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_BOOL;
    e->as.boolean.value = value;
    return e;
}

Expr* new_nil_expr() {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_NIL;
    return e;
}

Expr* new_array_expr(Expr** elements, int count) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_ARRAY;
    e->as.array.elements = elements;
    e->as.array.count = count;
    return e;
}

Expr* new_index_expr(Expr* array, Expr* index) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_INDEX;
    e->as.index.array = array;
    e->as.index.index = index;
    return e;
}

Expr* new_index_set_expr(Expr* array, Expr* index, Expr* value) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_INDEX_SET;
    e->as.index_set.array = array;
    e->as.index_set.index = index;
    e->as.index_set.value = value;
    return e;
}

Expr* new_dict_expr(char** keys, Expr** values, int count) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_DICT;
    e->as.dict.keys = keys;
    e->as.dict.values = values;
    e->as.dict.count = count;
    return e;
}

Expr* new_tuple_expr(Expr** elements, int count) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_TUPLE;
    e->as.tuple.elements = elements;
    e->as.tuple.count = count;
    return e;
}

Expr* new_slice_expr(Expr* array, Expr* start, Expr* end) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_SLICE;
    e->as.slice.array = array;
    e->as.slice.start = start;
    e->as.slice.end = end;
    return e;
}

Expr* new_get_expr(Expr* object, Token property) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_GET;
    e->as.get.object = object;
    e->as.get.property = property;
    return e;
}

Expr* new_set_expr(Expr* object, Token property, Expr* value) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_SET;
    e->as.set.object = object;
    e->as.set.property = property;
    e->as.set.value = value;
    return e;
}

Expr* new_await_expr(Expr* expression) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_AWAIT;
    e->as.await.expression = expression;
    return e;
}

Expr* new_super_expr(Token method) {
    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = EXPR_SUPER;
    e->as.super_expr.method = method;
    return e;
}

// ========== STATEMENT CONSTRUCTORS ==========

Stmt* new_print_stmt(Expr* expression) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_PRINT;
    s->as.print.expression = expression;
    s->next = NULL;
    return s;
}

Stmt* new_expr_stmt(Expr* expression) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_EXPRESSION;
    s->as.expression = expression;
    s->next = NULL;
    return s;
}

Stmt* new_let_stmt(Token name, Expr* initializer) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_LET;
    s->as.let.name = name;
    s->as.let.initializer = initializer;
    s->next = NULL;
    return s;
}

Stmt* new_if_stmt(Expr* condition, Stmt* then_branch, Stmt* else_branch) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_IF;
    s->as.if_stmt.condition = condition;
    s->as.if_stmt.then_branch = then_branch;
    s->as.if_stmt.else_branch = else_branch;
    s->next = NULL;
    return s;
}

Stmt* new_for_stmt(Token variable, Expr* iterable, Stmt* body) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_FOR;
    s->as.for_stmt.variable = variable;
    s->as.for_stmt.iterable = iterable;
    s->as.for_stmt.body = body;
    s->next = NULL;
    return s;
}

Stmt* new_block_stmt(Stmt* statements) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_BLOCK;
    s->as.block.statements = statements;
    s->next = NULL;
    return s;
}

Stmt* new_while_stmt(Expr* condition, Stmt* body) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_WHILE;
    s->as.while_stmt.condition = condition;
    s->as.while_stmt.body = body;
    s->next = NULL;
    return s;
}

Stmt* new_proc_stmt(Token name, Token* params, int param_count, Stmt* body) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_PROC;
    s->as.proc.name = name;
    s->as.proc.params = params;
    s->as.proc.defaults = NULL;
    s->as.proc.param_count = param_count;
    s->as.proc.required_count = param_count;
    s->as.proc.body = body;
    s->next = NULL;
    return s;
}

Stmt* new_return_stmt(Expr* value) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_RETURN;
    s->as.ret.value = value;
    s->next = NULL;
    return s;
}

Stmt* new_break_stmt() {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_BREAK;
    s->next = NULL;
    return s;
}

Stmt* new_continue_stmt() {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_CONTINUE;
    s->next = NULL;
    return s;
}

Stmt* new_class_stmt(Token name, Token parent, int has_parent, Stmt* methods) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
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
    CaseClause* c = SAGE_ALLOC(sizeof(CaseClause));
    c->pattern = pattern;
    c->body = body;
    return c;
}

Stmt* new_match_stmt(Expr* value, CaseClause** cases, int case_count, Stmt* default_case) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
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
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_DEFER;
    s->as.defer.statement = statement;
    s->next = NULL;
    return s;
}

// ========== PHASE 7: EXCEPTION HANDLING ==========

CatchClause* new_catch_clause(Token exception_var, Stmt* body) {
    CatchClause* c = SAGE_ALLOC(sizeof(CatchClause));
    c->exception_var = exception_var;
    c->body = body;
    return c;
}

Stmt* new_try_stmt(Stmt* try_block, CatchClause** catches, int catch_count, Stmt* finally_block) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_TRY;
    s->as.try_stmt.try_block = try_block;
    s->as.try_stmt.catches = catches;
    s->as.try_stmt.catch_count = catch_count;
    s->as.try_stmt.finally_block = finally_block;
    s->next = NULL;
    return s;
}

Stmt* new_raise_stmt(Expr* exception) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_RAISE;
    s->as.raise.exception = exception;
    s->next = NULL;
    return s;
}

// ========== PHASE 7: GENERATORS (YIELD) ==========

Stmt* new_yield_stmt(Expr* value) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_YIELD;
    s->as.yield_stmt.value = value;
    s->next = NULL;
    return s;
}

// ========== PHASE 8: MODULE IMPORTS ==========

Stmt* new_import_stmt(char* module_name, char** items, char** item_aliases, int item_count, char* alias, int import_all) {
    Stmt* stmt = SAGE_ALLOC(sizeof(Stmt));
    stmt->type = STMT_IMPORT;
    stmt->as.import.module_name = module_name;
    stmt->as.import.items = items;
    stmt->as.import.item_aliases = item_aliases;
    stmt->as.import.item_count = item_count;
    stmt->as.import.alias = alias;
    stmt->as.import.import_all = import_all;
    stmt->next = NULL;
    return stmt;
}

Stmt* new_async_proc_stmt(Token name, Token* params, int param_count, Stmt* body) {
    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    s->type = STMT_ASYNC_PROC;
    s->as.async_proc.name = name;
    s->as.async_proc.params = params;
    s->as.async_proc.defaults = NULL;
    s->as.async_proc.param_count = param_count;
    s->as.async_proc.required_count = param_count;
    s->as.async_proc.body = body;
    s->next = NULL;
    return s;
}

static void free_case_clause(CaseClause* clause) {
    if (clause == NULL) {
        return;
    }

    free_expr(clause->pattern);
    free_stmt(clause->body);
    free(clause);
}

static void free_catch_clause(CatchClause* clause) {
    if (clause == NULL) {
        return;
    }

    free_stmt(clause->body);
    free(clause);
}

void free_expr(Expr* expr) {
    if (expr == NULL) {
        return;
    }

    switch (expr->type) {
        case EXPR_STRING:
            free(expr->as.string.value);
            break;
        case EXPR_BINARY:
            free_expr(expr->as.binary.left);
            free_expr(expr->as.binary.right);
            break;
        case EXPR_CALL:
            free_expr(expr->as.call.callee);
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                free_expr(expr->as.call.args[i]);
            }
            free(expr->as.call.args);
            break;
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                free_expr(expr->as.array.elements[i]);
            }
            free(expr->as.array.elements);
            break;
        case EXPR_INDEX:
            free_expr(expr->as.index.array);
            free_expr(expr->as.index.index);
            break;
        case EXPR_INDEX_SET:
            free_expr(expr->as.index_set.array);
            free_expr(expr->as.index_set.index);
            free_expr(expr->as.index_set.value);
            break;
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                free(expr->as.dict.keys[i]);
                free_expr(expr->as.dict.values[i]);
            }
            free(expr->as.dict.keys);
            free(expr->as.dict.values);
            break;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                free_expr(expr->as.tuple.elements[i]);
            }
            free(expr->as.tuple.elements);
            break;
        case EXPR_SLICE:
            free_expr(expr->as.slice.array);
            free_expr(expr->as.slice.start);
            free_expr(expr->as.slice.end);
            break;
        case EXPR_GET:
            free_expr(expr->as.get.object);
            break;
        case EXPR_SET:
            free_expr(expr->as.set.object);
            free_expr(expr->as.set.value);
            break;
        case EXPR_AWAIT:
            free_expr(expr->as.await.expression);
            break;
        case EXPR_NUMBER:
        case EXPR_BOOL:
        case EXPR_NIL:
        case EXPR_VARIABLE:
            break;
    }

    free(expr);
}

void free_stmt(Stmt* stmt) {
    while (stmt != NULL) {
        Stmt* next = stmt->next;

        switch (stmt->type) {
            case STMT_PRINT:
                free_expr(stmt->as.print.expression);
                break;
            case STMT_EXPRESSION:
                free_expr(stmt->as.expression);
                break;
            case STMT_LET:
                free_expr(stmt->as.let.initializer);
                break;
            case STMT_IF:
                free_expr(stmt->as.if_stmt.condition);
                free_stmt(stmt->as.if_stmt.then_branch);
                free_stmt(stmt->as.if_stmt.else_branch);
                break;
            case STMT_BLOCK:
                free_stmt(stmt->as.block.statements);
                break;
            case STMT_WHILE:
                free_expr(stmt->as.while_stmt.condition);
                free_stmt(stmt->as.while_stmt.body);
                break;
            case STMT_PROC:
                free(stmt->as.proc.params);
                free_stmt(stmt->as.proc.body);
                break;
            case STMT_FOR:
                free_expr(stmt->as.for_stmt.iterable);
                free_stmt(stmt->as.for_stmt.body);
                break;
            case STMT_RETURN:
                free_expr(stmt->as.ret.value);
                break;
            case STMT_CLASS:
                free_stmt(stmt->as.class_stmt.methods);
                break;
            case STMT_MATCH:
                free_expr(stmt->as.match_stmt.value);
                for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                    free_case_clause(stmt->as.match_stmt.cases[i]);
                }
                free(stmt->as.match_stmt.cases);
                free_stmt(stmt->as.match_stmt.default_case);
                break;
            case STMT_DEFER:
                free_stmt(stmt->as.defer.statement);
                break;
            case STMT_TRY:
                free_stmt(stmt->as.try_stmt.try_block);
                for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                    free_catch_clause(stmt->as.try_stmt.catches[i]);
                }
                free(stmt->as.try_stmt.catches);
                free_stmt(stmt->as.try_stmt.finally_block);
                break;
            case STMT_RAISE:
                free_expr(stmt->as.raise.exception);
                break;
            case STMT_YIELD:
                free_expr(stmt->as.yield_stmt.value);
                break;
            case STMT_IMPORT:
                free(stmt->as.import.module_name);
                for (int i = 0; i < stmt->as.import.item_count; i++) {
                    free(stmt->as.import.items[i]);
                    free(stmt->as.import.item_aliases[i]);
                }
                free(stmt->as.import.items);
                free(stmt->as.import.item_aliases);
                free(stmt->as.import.alias);
                break;
            case STMT_ASYNC_PROC:
                free(stmt->as.async_proc.params);
                free_stmt(stmt->as.async_proc.body);
                break;
            case STMT_BREAK:
            case STMT_CONTINUE:
                break;
        }

        free(stmt);
        stmt = next;
    }
}
