#include "pass.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gc.h"

// ============================================================================
// Token Cloning
// ============================================================================

Token clone_token(Token tok) {
    Token t;
    t.type = tok.type;
    t.line = tok.line;
    t.column = tok.column;
    t.length = tok.length;
    t.line_start = tok.line_start;
    t.filename = tok.filename;
    // Token.start points into the original source; copy the string
    if (tok.start != NULL && tok.length > 0) {
        char* s = SAGE_ALLOC((size_t)tok.length + 1);
        memcpy(s, tok.start, (size_t)tok.length);
        s[tok.length] = '\0';
        t.start = s;
    } else {
        t.start = NULL;
    }
    return t;
}

// ============================================================================
// Expression Deep Clone
// ============================================================================

Expr* clone_expr(const Expr* expr) {
    if (expr == NULL) return NULL;

    Expr* e = SAGE_ALLOC(sizeof(Expr));
    e->type = expr->type;

    switch (expr->type) {
        case EXPR_NUMBER:
            e->as.number.value = expr->as.number.value;
            break;
        case EXPR_STRING:
            e->as.string.value = expr->as.string.value ? SAGE_STRDUP(expr->as.string.value) : NULL;
            break;
        case EXPR_BOOL:
            e->as.boolean.value = expr->as.boolean.value;
            break;
        case EXPR_NIL:
            break;
        case EXPR_BINARY:
            e->as.binary.op = clone_token(expr->as.binary.op);
            e->as.binary.left = clone_expr(expr->as.binary.left);
            e->as.binary.right = clone_expr(expr->as.binary.right);
            break;
        case EXPR_VARIABLE:
            e->as.variable.name = clone_token(expr->as.variable.name);
            break;
        case EXPR_CALL: {
            e->as.call.callee = clone_expr(expr->as.call.callee);
            e->as.call.arg_count = expr->as.call.arg_count;
            if (expr->as.call.arg_count > 0) {
                e->as.call.args = SAGE_ALLOC(sizeof(Expr*) * (size_t)expr->as.call.arg_count);
                for (int i = 0; i < expr->as.call.arg_count; i++) {
                    e->as.call.args[i] = clone_expr(expr->as.call.args[i]);
                }
            } else {
                e->as.call.args = NULL;
            }
            break;
        }
        case EXPR_ARRAY: {
            e->as.array.count = expr->as.array.count;
            if (expr->as.array.count > 0) {
                e->as.array.elements = SAGE_ALLOC(sizeof(Expr*) * (size_t)expr->as.array.count);
                for (int i = 0; i < expr->as.array.count; i++) {
                    e->as.array.elements[i] = clone_expr(expr->as.array.elements[i]);
                }
            } else {
                e->as.array.elements = NULL;
            }
            break;
        }
        case EXPR_INDEX:
            e->as.index.array = clone_expr(expr->as.index.array);
            e->as.index.index = clone_expr(expr->as.index.index);
            break;
        case EXPR_INDEX_SET:
            return new_index_set_expr(
                clone_expr(expr->as.index_set.array),
                clone_expr(expr->as.index_set.index),
                clone_expr(expr->as.index_set.value));
        case EXPR_DICT: {
            e->as.dict.count = expr->as.dict.count;
            if (expr->as.dict.count > 0) {
                e->as.dict.keys = SAGE_ALLOC(sizeof(char*) * (size_t)expr->as.dict.count);
                e->as.dict.values = SAGE_ALLOC(sizeof(Expr*) * (size_t)expr->as.dict.count);
                for (int i = 0; i < expr->as.dict.count; i++) {
                    e->as.dict.keys[i] = SAGE_STRDUP(expr->as.dict.keys[i]);
                    e->as.dict.values[i] = clone_expr(expr->as.dict.values[i]);
                }
            } else {
                e->as.dict.keys = NULL;
                e->as.dict.values = NULL;
            }
            break;
        }
        case EXPR_TUPLE: {
            e->as.tuple.count = expr->as.tuple.count;
            if (expr->as.tuple.count > 0) {
                e->as.tuple.elements = SAGE_ALLOC(sizeof(Expr*) * (size_t)expr->as.tuple.count);
                for (int i = 0; i < expr->as.tuple.count; i++) {
                    e->as.tuple.elements[i] = clone_expr(expr->as.tuple.elements[i]);
                }
            } else {
                e->as.tuple.elements = NULL;
            }
            break;
        }
        case EXPR_SLICE:
            e->as.slice.array = clone_expr(expr->as.slice.array);
            e->as.slice.start = clone_expr(expr->as.slice.start);
            e->as.slice.end = clone_expr(expr->as.slice.end);
            break;
        case EXPR_GET:
            e->as.get.object = clone_expr(expr->as.get.object);
            e->as.get.property = clone_token(expr->as.get.property);
            break;
        case EXPR_SET:
            e->as.set.object = clone_expr(expr->as.set.object);
            e->as.set.property = clone_token(expr->as.set.property);
            e->as.set.value = clone_expr(expr->as.set.value);
            break;
        case EXPR_AWAIT:
            return new_await_expr(clone_expr(expr->as.await.expression));
    }

    return e;
}

// ============================================================================
// Statement Deep Clone
// ============================================================================

static CaseClause* clone_case_clause(const CaseClause* c) {
    if (c == NULL) return NULL;
    CaseClause* nc = SAGE_ALLOC(sizeof(CaseClause));
    nc->pattern = clone_expr(c->pattern);
    nc->body = clone_stmt_list(c->body);
    return nc;
}

static CatchClause* clone_catch_clause(const CatchClause* c) {
    if (c == NULL) return NULL;
    CatchClause* nc = SAGE_ALLOC(sizeof(CatchClause));
    nc->exception_var = clone_token(c->exception_var);
    nc->body = clone_stmt_list(c->body);
    return nc;
}

Stmt* clone_stmt(const Stmt* stmt) {
    if (stmt == NULL) return NULL;

    Stmt* s = SAGE_ALLOC(sizeof(Stmt));
    memset(s, 0, sizeof(Stmt));
    s->type = stmt->type;
    s->next = NULL;

    switch (stmt->type) {
        case STMT_PRINT:
            s->as.print.expression = clone_expr(stmt->as.print.expression);
            break;
        case STMT_EXPRESSION:
            s->as.expression = clone_expr(stmt->as.expression);
            break;
        case STMT_LET:
            s->as.let.name = clone_token(stmt->as.let.name);
            s->as.let.initializer = clone_expr(stmt->as.let.initializer);
            break;
        case STMT_IF:
            s->as.if_stmt.condition = clone_expr(stmt->as.if_stmt.condition);
            s->as.if_stmt.then_branch = clone_stmt_list(stmt->as.if_stmt.then_branch);
            s->as.if_stmt.else_branch = clone_stmt_list(stmt->as.if_stmt.else_branch);
            break;
        case STMT_BLOCK:
            s->as.block.statements = clone_stmt_list(stmt->as.block.statements);
            break;
        case STMT_WHILE:
            s->as.while_stmt.condition = clone_expr(stmt->as.while_stmt.condition);
            s->as.while_stmt.body = clone_stmt_list(stmt->as.while_stmt.body);
            break;
        case STMT_PROC: {
            s->as.proc.name = clone_token(stmt->as.proc.name);
            s->as.proc.param_count = stmt->as.proc.param_count;
            if (stmt->as.proc.param_count > 0) {
                s->as.proc.params = SAGE_ALLOC(sizeof(Token) * (size_t)stmt->as.proc.param_count);
                for (int i = 0; i < stmt->as.proc.param_count; i++) {
                    s->as.proc.params[i] = clone_token(stmt->as.proc.params[i]);
                }
            } else {
                s->as.proc.params = NULL;
            }
            s->as.proc.body = clone_stmt_list(stmt->as.proc.body);
            break;
        }
        case STMT_FOR:
            s->as.for_stmt.variable = clone_token(stmt->as.for_stmt.variable);
            s->as.for_stmt.iterable = clone_expr(stmt->as.for_stmt.iterable);
            s->as.for_stmt.body = clone_stmt_list(stmt->as.for_stmt.body);
            break;
        case STMT_RETURN:
            s->as.ret.value = clone_expr(stmt->as.ret.value);
            break;
        case STMT_BREAK:
        case STMT_CONTINUE:
            break;
        case STMT_CLASS:
            s->as.class_stmt.name = clone_token(stmt->as.class_stmt.name);
            s->as.class_stmt.parent = clone_token(stmt->as.class_stmt.parent);
            s->as.class_stmt.has_parent = stmt->as.class_stmt.has_parent;
            s->as.class_stmt.methods = clone_stmt_list(stmt->as.class_stmt.methods);
            break;
        case STMT_MATCH: {
            s->as.match_stmt.value = clone_expr(stmt->as.match_stmt.value);
            s->as.match_stmt.case_count = stmt->as.match_stmt.case_count;
            if (stmt->as.match_stmt.case_count > 0) {
                s->as.match_stmt.cases = SAGE_ALLOC(sizeof(CaseClause*) * (size_t)stmt->as.match_stmt.case_count);
                for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                    s->as.match_stmt.cases[i] = clone_case_clause(stmt->as.match_stmt.cases[i]);
                }
            } else {
                s->as.match_stmt.cases = NULL;
            }
            s->as.match_stmt.default_case = clone_stmt_list(stmt->as.match_stmt.default_case);
            break;
        }
        case STMT_DEFER:
            s->as.defer.statement = clone_stmt_list(stmt->as.defer.statement);
            break;
        case STMT_TRY: {
            s->as.try_stmt.try_block = clone_stmt_list(stmt->as.try_stmt.try_block);
            s->as.try_stmt.catch_count = stmt->as.try_stmt.catch_count;
            if (stmt->as.try_stmt.catch_count > 0) {
                s->as.try_stmt.catches = SAGE_ALLOC(sizeof(CatchClause*) * (size_t)stmt->as.try_stmt.catch_count);
                for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                    s->as.try_stmt.catches[i] = clone_catch_clause(stmt->as.try_stmt.catches[i]);
                }
            } else {
                s->as.try_stmt.catches = NULL;
            }
            s->as.try_stmt.finally_block = clone_stmt_list(stmt->as.try_stmt.finally_block);
            break;
        }
        case STMT_RAISE:
            s->as.raise.exception = clone_expr(stmt->as.raise.exception);
            break;
        case STMT_YIELD:
            s->as.yield_stmt.value = clone_expr(stmt->as.yield_stmt.value);
            break;
        case STMT_IMPORT: {
            s->as.import.module_name = stmt->as.import.module_name ? SAGE_STRDUP(stmt->as.import.module_name) : NULL;
            s->as.import.item_count = stmt->as.import.item_count;
            if (stmt->as.import.item_count > 0) {
                s->as.import.items = SAGE_ALLOC(sizeof(char*) * (size_t)stmt->as.import.item_count);
                s->as.import.item_aliases = SAGE_ALLOC(sizeof(char*) * (size_t)stmt->as.import.item_count);
                for (int i = 0; i < stmt->as.import.item_count; i++) {
                    s->as.import.items[i] = stmt->as.import.items[i] ? SAGE_STRDUP(stmt->as.import.items[i]) : NULL;
                    s->as.import.item_aliases[i] = stmt->as.import.item_aliases[i] ? SAGE_STRDUP(stmt->as.import.item_aliases[i]) : NULL;
                }
            } else {
                s->as.import.items = NULL;
                s->as.import.item_aliases = NULL;
            }
            s->as.import.alias = stmt->as.import.alias ? SAGE_STRDUP(stmt->as.import.alias) : NULL;
            s->as.import.import_all = stmt->as.import.import_all;
            break;
        }
        case STMT_ASYNC_PROC: {
            Stmt* body = clone_stmt_list(stmt->as.async_proc.body);
            Token* params = NULL;
            if (stmt->as.async_proc.param_count > 0) {
                params = SAGE_ALLOC(sizeof(Token) * (size_t)stmt->as.async_proc.param_count);
                for (int i = 0; i < stmt->as.async_proc.param_count; i++) {
                    params[i] = clone_token(stmt->as.async_proc.params[i]);
                }
            }
            return new_async_proc_stmt(stmt->as.async_proc.name, params, stmt->as.async_proc.param_count, body);
        }
    }

    return s;
}

Stmt* clone_stmt_list(const Stmt* head) {
    if (head == NULL) return NULL;

    Stmt* new_head = NULL;
    Stmt* new_tail = NULL;

    for (const Stmt* cur = head; cur != NULL; cur = cur->next) {
        Stmt* cloned = clone_stmt(cur);
        if (new_head == NULL) {
            new_head = cloned;
        } else {
            new_tail->next = cloned;
        }
        new_tail = cloned;
    }

    return new_head;
}

// ============================================================================
// Pass Registration and Runner
// ============================================================================

// Forward declarations for optimization passes
extern Stmt* pass_typecheck(Stmt* program, PassContext* ctx);
extern Stmt* pass_constfold(Stmt* program, PassContext* ctx);
extern Stmt* pass_dce(Stmt* program, PassContext* ctx);
extern Stmt* pass_inline(Stmt* program, PassContext* ctx);
extern Stmt* pass_safety(Stmt* program, PassContext* ctx);

static PassEntry g_passes[] = {
    { "typecheck",  pass_typecheck, 0 },  // always run type inference
    { "safety",     pass_safety,    0 },  // always run safety analysis
    { "constfold",  pass_constfold, 1 },  // -O1+
    { "dce",        pass_dce,       2 },  // -O2+
    { "inline",     pass_inline,    3 },  // -O3 only
};

static const int g_pass_count = (int)(sizeof(g_passes) / sizeof(g_passes[0]));

Stmt* run_passes(Stmt* program, PassContext* ctx) {
    if (ctx->opt_level <= 0 && !ctx->debug_info) {
        return program;  // no passes needed
    }

    for (int i = 0; i < g_pass_count; i++) {
        if (ctx->opt_level >= g_passes[i].min_opt_level) {
            if (ctx->verbose) {
                fprintf(stderr, "[pass] running %s\n", g_passes[i].name);
            }
            program = g_passes[i].fn(program, ctx);
        }
    }

    return program;
}
