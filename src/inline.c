#include "pass.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gc.h"

// ============================================================================
// Function Inlining Pass
//
// Replaces calls to small, non-recursive procedures with their body.
// Only runs at -O3.
//
// Criteria for inlining:
// - Procedure body is a single return statement
// - Not recursive
// - Called with correct argument count
// ============================================================================

// ============================================================================
// Procedure Table - collect proc definitions for inlining
// ============================================================================

typedef struct InlineCandidate {
    char name[256];
    int param_count;
    Token* params;
    Expr* return_expr;     // non-NULL if body is single `return expr`
    int is_recursive;
    struct InlineCandidate* next;
} InlineCandidate;

static void free_candidates(InlineCandidate* list) {
    while (list != NULL) {
        InlineCandidate* next = list->next;
        free(list);
        list = next;
    }
}

// Check if a proc body is a single return statement
static Expr* get_single_return_expr(const Stmt* body) {
    if (body == NULL) return NULL;

    // Body might be a block containing statements
    const Stmt* first = body;
    if (first->type == STMT_BLOCK) {
        first = first->as.block.statements;
    }

    // Must be exactly one statement and it must be a return
    if (first == NULL) return NULL;
    if (first->next != NULL) return NULL;  // more than one statement
    if (first->type != STMT_RETURN) return NULL;

    return first->as.ret.value;
}

// Check if an expression references a name
static int expr_references_name(const Expr* expr, const char* name) {
    if (expr == NULL) return 0;

    switch (expr->type) {
        case EXPR_VARIABLE: {
            int len = expr->as.variable.name.length;
            if (len == (int)strlen(name) &&
                memcmp(expr->as.variable.name.start, name, (size_t)len) == 0) {
                return 1;
            }
            return 0;
        }
        case EXPR_BINARY:
            return expr_references_name(expr->as.binary.left, name) ||
                   expr_references_name(expr->as.binary.right, name);
        case EXPR_CALL:
            if (expr_references_name(expr->as.call.callee, name)) return 1;
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                if (expr_references_name(expr->as.call.args[i], name)) return 1;
            }
            return 0;
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                if (expr_references_name(expr->as.array.elements[i], name)) return 1;
            }
            return 0;
        case EXPR_INDEX:
            return expr_references_name(expr->as.index.array, name) ||
                   expr_references_name(expr->as.index.index, name);
        case EXPR_INDEX_SET:
            return expr_references_name(expr->as.index_set.array, name) ||
                   expr_references_name(expr->as.index_set.index, name) ||
                   expr_references_name(expr->as.index_set.value, name);
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                if (expr_references_name(expr->as.dict.values[i], name)) return 1;
            }
            return 0;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                if (expr_references_name(expr->as.tuple.elements[i], name)) return 1;
            }
            return 0;
        case EXPR_SLICE:
            return expr_references_name(expr->as.slice.array, name) ||
                   expr_references_name(expr->as.slice.start, name) ||
                   expr_references_name(expr->as.slice.end, name);
        case EXPR_GET:
            return expr_references_name(expr->as.get.object, name);
        case EXPR_SET:
            return expr_references_name(expr->as.set.object, name) ||
                   expr_references_name(expr->as.set.value, name);
        case EXPR_AWAIT:
            return 0;
        default:
            return 0;
    }
}

// Collect inline candidates from proc definitions
static InlineCandidate* collect_candidates(Stmt* program) {
    InlineCandidate* list = NULL;

    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type != STMT_PROC) continue;

        Expr* ret_expr = get_single_return_expr(s->as.proc.body);
        if (ret_expr == NULL) continue;

        char name[256];
        int len = s->as.proc.name.length;
        if (len > 255) len = 255;
        memcpy(name, s->as.proc.name.start, (size_t)len);
        name[len] = '\0';

        // Check for recursion
        if (expr_references_name(ret_expr, name)) continue;

        InlineCandidate* c = SAGE_ALLOC(sizeof(InlineCandidate));
        memcpy(c->name, name, (size_t)(len + 1));
        c->param_count = s->as.proc.param_count;
        c->params = s->as.proc.params;
        c->return_expr = ret_expr;
        c->is_recursive = 0;
        c->next = list;
        list = c;
    }

    return list;
}

// Find a candidate by name
static InlineCandidate* find_candidate(InlineCandidate* list, const char* name) {
    for (InlineCandidate* c = list; c != NULL; c = c->next) {
        if (strcmp(c->name, name) == 0) return c;
    }
    return NULL;
}

// ============================================================================
// Expression substitution - replace parameter references with argument exprs
// ============================================================================

static Expr* substitute_expr(const Expr* expr, Token* params, int param_count, Expr** args) {
    if (expr == NULL) return NULL;

    // Deep clone and substitute
    Expr* result = clone_expr(expr);

    if (result->type == EXPR_VARIABLE) {
        int vlen = result->as.variable.name.length;
        for (int i = 0; i < param_count; i++) {
            if (params[i].length == vlen &&
                memcmp(params[i].start, result->as.variable.name.start, (size_t)vlen) == 0) {
                // Replace with cloned argument
                free_expr(result);
                return clone_expr(args[i]);
            }
        }
    } else if (result->type == EXPR_BINARY) {
        free_expr(result->as.binary.left);
        free_expr(result->as.binary.right);
        result->as.binary.left = substitute_expr(expr->as.binary.left, params, param_count, args);
        result->as.binary.right = substitute_expr(expr->as.binary.right, params, param_count, args);
    } else if (result->type == EXPR_CALL) {
        free_expr(result->as.call.callee);
        result->as.call.callee = substitute_expr(expr->as.call.callee, params, param_count, args);
        for (int i = 0; i < result->as.call.arg_count; i++) {
            free_expr(result->as.call.args[i]);
            result->as.call.args[i] = substitute_expr(expr->as.call.args[i], params, param_count, args);
        }
    } else if (result->type == EXPR_INDEX) {
        free_expr(result->as.index.array);
        free_expr(result->as.index.index);
        result->as.index.array = substitute_expr(expr->as.index.array, params, param_count, args);
        result->as.index.index = substitute_expr(expr->as.index.index, params, param_count, args);
    } else if (result->type == EXPR_INDEX_SET) {
        free_expr(result->as.index_set.array);
        free_expr(result->as.index_set.index);
        free_expr(result->as.index_set.value);
        result->as.index_set.array = substitute_expr(expr->as.index_set.array, params, param_count, args);
        result->as.index_set.index = substitute_expr(expr->as.index_set.index, params, param_count, args);
        result->as.index_set.value = substitute_expr(expr->as.index_set.value, params, param_count, args);
    } else if (result->type == EXPR_ARRAY) {
        for (int i = 0; i < result->as.array.count; i++) {
            free_expr(result->as.array.elements[i]);
            result->as.array.elements[i] = substitute_expr(expr->as.array.elements[i], params, param_count, args);
        }
    } else if (result->type == EXPR_DICT) {
        for (int i = 0; i < result->as.dict.count; i++) {
            free_expr(result->as.dict.values[i]);
            result->as.dict.values[i] = substitute_expr(expr->as.dict.values[i], params, param_count, args);
        }
    } else if (result->type == EXPR_TUPLE) {
        for (int i = 0; i < result->as.tuple.count; i++) {
            free_expr(result->as.tuple.elements[i]);
            result->as.tuple.elements[i] = substitute_expr(expr->as.tuple.elements[i], params, param_count, args);
        }
    } else if (result->type == EXPR_SLICE) {
        free_expr(result->as.slice.array);
        free_expr(result->as.slice.start);
        free_expr(result->as.slice.end);
        result->as.slice.array = substitute_expr(expr->as.slice.array, params, param_count, args);
        result->as.slice.start = substitute_expr(expr->as.slice.start, params, param_count, args);
        result->as.slice.end = substitute_expr(expr->as.slice.end, params, param_count, args);
    } else if (result->type == EXPR_GET) {
        free_expr(result->as.get.object);
        result->as.get.object = substitute_expr(expr->as.get.object, params, param_count, args);
    } else if (result->type == EXPR_SET) {
        free_expr(result->as.set.object);
        free_expr(result->as.set.value);
        result->as.set.object = substitute_expr(expr->as.set.object, params, param_count, args);
        result->as.set.value = substitute_expr(expr->as.set.value, params, param_count, args);
    }

    return result;
}

// ============================================================================
// Inline call expressions
// ============================================================================

static Expr* inline_expr(Expr* expr, InlineCandidate* candidates) {
    if (expr == NULL) return NULL;

    switch (expr->type) {
        case EXPR_CALL: {
            // First inline args and callee
            expr->as.call.callee = inline_expr(expr->as.call.callee, candidates);
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                expr->as.call.args[i] = inline_expr(expr->as.call.args[i], candidates);
            }

            // Check if callee is a simple variable name matching a candidate
            if (expr->as.call.callee->type == EXPR_VARIABLE) {
                char name[256];
                int len = expr->as.call.callee->as.variable.name.length;
                if (len > 255) len = 255;
                memcpy(name, expr->as.call.callee->as.variable.name.start, (size_t)len);
                name[len] = '\0';

                InlineCandidate* c = find_candidate(candidates, name);
                if (c != NULL && expr->as.call.arg_count == c->param_count) {
                    // Perform inlining: substitute params with args in return expr
                    Expr* inlined = substitute_expr(c->return_expr, c->params,
                                                     c->param_count, expr->as.call.args);
                    free_expr(expr);
                    return inlined;
                }
            }
            break;
        }
        case EXPR_BINARY:
            expr->as.binary.left = inline_expr(expr->as.binary.left, candidates);
            expr->as.binary.right = inline_expr(expr->as.binary.right, candidates);
            break;
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                expr->as.array.elements[i] = inline_expr(expr->as.array.elements[i], candidates);
            }
            break;
        case EXPR_INDEX:
            expr->as.index.array = inline_expr(expr->as.index.array, candidates);
            expr->as.index.index = inline_expr(expr->as.index.index, candidates);
            break;
        case EXPR_INDEX_SET:
            expr->as.index_set.array = inline_expr(expr->as.index_set.array, candidates);
            expr->as.index_set.index = inline_expr(expr->as.index_set.index, candidates);
            expr->as.index_set.value = inline_expr(expr->as.index_set.value, candidates);
            break;
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                expr->as.dict.values[i] = inline_expr(expr->as.dict.values[i], candidates);
            }
            break;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                expr->as.tuple.elements[i] = inline_expr(expr->as.tuple.elements[i], candidates);
            }
            break;
        case EXPR_SLICE:
            expr->as.slice.array = inline_expr(expr->as.slice.array, candidates);
            expr->as.slice.start = inline_expr(expr->as.slice.start, candidates);
            expr->as.slice.end = inline_expr(expr->as.slice.end, candidates);
            break;
        case EXPR_GET:
            expr->as.get.object = inline_expr(expr->as.get.object, candidates);
            break;
        case EXPR_SET:
            expr->as.set.object = inline_expr(expr->as.set.object, candidates);
            expr->as.set.value = inline_expr(expr->as.set.value, candidates);
            break;
        case EXPR_AWAIT:
            break;
        default:
            break;
    }

    return expr;
}

static void inline_stmt(Stmt* stmt, InlineCandidate* candidates);

static void inline_stmt_list(Stmt* head, InlineCandidate* candidates) {
    for (Stmt* s = head; s != NULL; s = s->next) {
        inline_stmt(s, candidates);
    }
}

static void inline_stmt(Stmt* stmt, InlineCandidate* candidates) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT:
            stmt->as.print.expression = inline_expr(stmt->as.print.expression, candidates);
            break;
        case STMT_EXPRESSION:
            stmt->as.expression = inline_expr(stmt->as.expression, candidates);
            break;
        case STMT_LET:
            stmt->as.let.initializer = inline_expr(stmt->as.let.initializer, candidates);
            break;
        case STMT_IF:
            stmt->as.if_stmt.condition = inline_expr(stmt->as.if_stmt.condition, candidates);
            inline_stmt_list(stmt->as.if_stmt.then_branch, candidates);
            inline_stmt_list(stmt->as.if_stmt.else_branch, candidates);
            break;
        case STMT_BLOCK:
            inline_stmt_list(stmt->as.block.statements, candidates);
            break;
        case STMT_WHILE:
            stmt->as.while_stmt.condition = inline_expr(stmt->as.while_stmt.condition, candidates);
            inline_stmt_list(stmt->as.while_stmt.body, candidates);
            break;
        case STMT_PROC:
            inline_stmt_list(stmt->as.proc.body, candidates);
            break;
        case STMT_FOR:
            stmt->as.for_stmt.iterable = inline_expr(stmt->as.for_stmt.iterable, candidates);
            inline_stmt_list(stmt->as.for_stmt.body, candidates);
            break;
        case STMT_RETURN:
            stmt->as.ret.value = inline_expr(stmt->as.ret.value, candidates);
            break;
        case STMT_CLASS:
            inline_stmt_list(stmt->as.class_stmt.methods, candidates);
            break;
        case STMT_MATCH:
            stmt->as.match_stmt.value = inline_expr(stmt->as.match_stmt.value, candidates);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                stmt->as.match_stmt.cases[i]->pattern = inline_expr(stmt->as.match_stmt.cases[i]->pattern, candidates);
                inline_stmt_list(stmt->as.match_stmt.cases[i]->body, candidates);
            }
            inline_stmt_list(stmt->as.match_stmt.default_case, candidates);
            break;
        case STMT_TRY:
            inline_stmt_list(stmt->as.try_stmt.try_block, candidates);
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                inline_stmt_list(stmt->as.try_stmt.catches[i]->body, candidates);
            }
            inline_stmt_list(stmt->as.try_stmt.finally_block, candidates);
            break;
        case STMT_RAISE:
            stmt->as.raise.exception = inline_expr(stmt->as.raise.exception, candidates);
            break;
        case STMT_YIELD:
            stmt->as.yield_stmt.value = inline_expr(stmt->as.yield_stmt.value, candidates);
            break;
        case STMT_ASYNC_PROC:
            break;
        default:
            break;
    }
}

// ============================================================================
// Pass Entry Point
// ============================================================================

Stmt* pass_inline(Stmt* program, PassContext* ctx) {
    (void)ctx;

    InlineCandidate* candidates = collect_candidates(program);
    if (candidates == NULL) return program;

    inline_stmt_list(program, candidates);

    free_candidates(candidates);
    return program;
}
