#include "pass.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ============================================================================
// Dead Code Elimination Pass
//
// Removes:
// 1. Unreachable code after return/break/continue
// 2. Unused let bindings (variable assigned but never read)
// 3. Unused proc definitions (never called)
// ============================================================================

// ============================================================================
// Name Set - tracks used variable/proc names
// ============================================================================

typedef struct NameSet {
    char* name;
    struct NameSet* next;
} NameSet;

static void nameset_add(NameSet** set, const char* name) {
    for (NameSet* n = *set; n != NULL; n = n->next) {
        if (strcmp(n->name, name) == 0) return;
    }
    NameSet* n = malloc(sizeof(NameSet));
    n->name = strdup(name);
    n->next = *set;
    *set = n;
}

static int nameset_has(NameSet* set, const char* name) {
    for (NameSet* n = set; n != NULL; n = n->next) {
        if (strcmp(n->name, name) == 0) return 1;
    }
    return 0;
}

static void nameset_free(NameSet* set) {
    while (set != NULL) {
        NameSet* next = set->next;
        free(set->name);
        free(set);
        set = next;
    }
}

// ============================================================================
// Liveness Analysis - collect all referenced names
// ============================================================================

static void collect_used_names_expr(NameSet** used, const Expr* expr);

static void collect_used_names_expr(NameSet** used, const Expr* expr) {
    if (expr == NULL) return;

    switch (expr->type) {
        case EXPR_VARIABLE: {
            char name[256];
            int len = expr->as.variable.name.length;
            if (len > 255) len = 255;
            memcpy(name, expr->as.variable.name.start, (size_t)len);
            name[len] = '\0';
            nameset_add(used, name);
            break;
        }
        case EXPR_BINARY:
            collect_used_names_expr(used, expr->as.binary.left);
            collect_used_names_expr(used, expr->as.binary.right);
            break;
        case EXPR_CALL:
            collect_used_names_expr(used, expr->as.call.callee);
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                collect_used_names_expr(used, expr->as.call.args[i]);
            }
            break;
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                collect_used_names_expr(used, expr->as.array.elements[i]);
            }
            break;
        case EXPR_INDEX:
            collect_used_names_expr(used, expr->as.index.array);
            collect_used_names_expr(used, expr->as.index.index);
            break;
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                collect_used_names_expr(used, expr->as.dict.values[i]);
            }
            break;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                collect_used_names_expr(used, expr->as.tuple.elements[i]);
            }
            break;
        case EXPR_SLICE:
            collect_used_names_expr(used, expr->as.slice.array);
            collect_used_names_expr(used, expr->as.slice.start);
            collect_used_names_expr(used, expr->as.slice.end);
            break;
        case EXPR_GET:
            collect_used_names_expr(used, expr->as.get.object);
            break;
        case EXPR_SET:
            collect_used_names_expr(used, expr->as.set.object);
            collect_used_names_expr(used, expr->as.set.value);
            break;
        default:
            break;
    }
}

static void collect_used_names_stmt(NameSet** used, const Stmt* stmt);

static void collect_used_names_list(NameSet** used, const Stmt* head) {
    for (const Stmt* s = head; s != NULL; s = s->next) {
        collect_used_names_stmt(used, s);
    }
}

static void collect_used_names_stmt(NameSet** used, const Stmt* stmt) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT:
            collect_used_names_expr(used, stmt->as.print.expression);
            break;
        case STMT_EXPRESSION:
            collect_used_names_expr(used, stmt->as.expression);
            break;
        case STMT_LET:
            collect_used_names_expr(used, stmt->as.let.initializer);
            break;
        case STMT_IF:
            collect_used_names_expr(used, stmt->as.if_stmt.condition);
            collect_used_names_list(used, stmt->as.if_stmt.then_branch);
            collect_used_names_list(used, stmt->as.if_stmt.else_branch);
            break;
        case STMT_BLOCK:
            collect_used_names_list(used, stmt->as.block.statements);
            break;
        case STMT_WHILE:
            collect_used_names_expr(used, stmt->as.while_stmt.condition);
            collect_used_names_list(used, stmt->as.while_stmt.body);
            break;
        case STMT_PROC:
            collect_used_names_list(used, stmt->as.proc.body);
            break;
        case STMT_FOR:
            collect_used_names_expr(used, stmt->as.for_stmt.iterable);
            collect_used_names_list(used, stmt->as.for_stmt.body);
            break;
        case STMT_RETURN:
            collect_used_names_expr(used, stmt->as.ret.value);
            break;
        case STMT_CLASS:
            collect_used_names_list(used, stmt->as.class_stmt.methods);
            break;
        case STMT_MATCH:
            collect_used_names_expr(used, stmt->as.match_stmt.value);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                collect_used_names_expr(used, stmt->as.match_stmt.cases[i]->pattern);
                collect_used_names_list(used, stmt->as.match_stmt.cases[i]->body);
            }
            collect_used_names_list(used, stmt->as.match_stmt.default_case);
            break;
        case STMT_TRY:
            collect_used_names_list(used, stmt->as.try_stmt.try_block);
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                collect_used_names_list(used, stmt->as.try_stmt.catches[i]->body);
            }
            collect_used_names_list(used, stmt->as.try_stmt.finally_block);
            break;
        case STMT_RAISE:
            collect_used_names_expr(used, stmt->as.raise.exception);
            break;
        case STMT_YIELD:
            collect_used_names_expr(used, stmt->as.yield_stmt.value);
            break;
        case STMT_DEFER:
            collect_used_names_stmt(used, stmt->as.defer.statement);
            break;
        case STMT_IMPORT:
        case STMT_BREAK:
        case STMT_CONTINUE:
            break;
    }
}

// ============================================================================
// Check if an expression has side effects
// ============================================================================

static int has_side_effects(const Expr* expr) {
    if (expr == NULL) return 0;
    switch (expr->type) {
        case EXPR_CALL:
            return 1; // function calls always have potential side effects
        case EXPR_SET:
            return 1; // property assignment
        case EXPR_BINARY:
            return has_side_effects(expr->as.binary.left) || has_side_effects(expr->as.binary.right);
        case EXPR_INDEX:
            return has_side_effects(expr->as.index.array) || has_side_effects(expr->as.index.index);
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                if (has_side_effects(expr->as.array.elements[i])) return 1;
            }
            return 0;
        default:
            return 0;
    }
}

// ============================================================================
// Remove unreachable code after return/break/continue in a block
// ============================================================================

static int is_terminator(const Stmt* s) {
    return s->type == STMT_RETURN || s->type == STMT_BREAK || s->type == STMT_CONTINUE;
}

static Stmt* remove_unreachable(Stmt* head) {
    if (head == NULL) return NULL;

    for (Stmt* s = head; s != NULL; s = s->next) {
        if (is_terminator(s) && s->next != NULL) {
            // Free everything after this statement
            free_stmt(s->next);
            s->next = NULL;
            break;
        }
    }

    return head;
}

// ============================================================================
// DCE: remove unused lets and procs from a statement list
// ============================================================================

static Stmt* dce_stmt_list(Stmt* head, NameSet* used);

static void dce_stmt_body(Stmt* stmt, NameSet* used) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_IF:
            stmt->as.if_stmt.then_branch = dce_stmt_list(stmt->as.if_stmt.then_branch, used);
            stmt->as.if_stmt.else_branch = dce_stmt_list(stmt->as.if_stmt.else_branch, used);
            break;
        case STMT_BLOCK:
            stmt->as.block.statements = dce_stmt_list(stmt->as.block.statements, used);
            break;
        case STMT_WHILE:
            stmt->as.while_stmt.body = dce_stmt_list(stmt->as.while_stmt.body, used);
            break;
        case STMT_PROC:
            stmt->as.proc.body = dce_stmt_list(stmt->as.proc.body, used);
            break;
        case STMT_FOR:
            stmt->as.for_stmt.body = dce_stmt_list(stmt->as.for_stmt.body, used);
            break;
        case STMT_CLASS:
            stmt->as.class_stmt.methods = dce_stmt_list(stmt->as.class_stmt.methods, used);
            break;
        case STMT_TRY:
            stmt->as.try_stmt.try_block = dce_stmt_list(stmt->as.try_stmt.try_block, used);
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                stmt->as.try_stmt.catches[i]->body = dce_stmt_list(stmt->as.try_stmt.catches[i]->body, used);
            }
            stmt->as.try_stmt.finally_block = dce_stmt_list(stmt->as.try_stmt.finally_block, used);
            break;
        case STMT_MATCH:
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                stmt->as.match_stmt.cases[i]->body = dce_stmt_list(stmt->as.match_stmt.cases[i]->body, used);
            }
            stmt->as.match_stmt.default_case = dce_stmt_list(stmt->as.match_stmt.default_case, used);
            break;
        default:
            break;
    }
}

static Stmt* dce_stmt_list(Stmt* head, NameSet* used) {
    head = remove_unreachable(head);

    Stmt* new_head = NULL;
    Stmt* new_tail = NULL;
    Stmt* cur = head;

    while (cur != NULL) {
        Stmt* next = cur->next;
        int keep = 1;

        // Check if this is an unused let binding
        if (cur->type == STMT_LET) {
            char name[256];
            int len = cur->as.let.name.length;
            if (len > 255) len = 255;
            memcpy(name, cur->as.let.name.start, (size_t)len);
            name[len] = '\0';

            if (!nameset_has(used, name) && !has_side_effects(cur->as.let.initializer)) {
                keep = 0;
            }
        }

        // Check if this is an unused proc
        if (cur->type == STMT_PROC) {
            char name[256];
            int len = cur->as.proc.name.length;
            if (len > 255) len = 255;
            memcpy(name, cur->as.proc.name.start, (size_t)len);
            name[len] = '\0';

            if (!nameset_has(used, name)) {
                keep = 0;
            }
        }

        if (keep) {
            dce_stmt_body(cur, used);
            cur->next = NULL;
            if (new_head == NULL) {
                new_head = cur;
            } else {
                new_tail->next = cur;
            }
            new_tail = cur;
        } else {
            cur->next = NULL;
            free_stmt(cur);
        }

        cur = next;
    }

    return new_head;
}

// ============================================================================
// Pass Entry Point
// ============================================================================

Stmt* pass_dce(Stmt* program, PassContext* ctx) {
    (void)ctx;

    // Collect all used names
    NameSet* used = NULL;
    collect_used_names_list(&used, program);

    // Remove dead code
    program = dce_stmt_list(program, used);

    nameset_free(used);
    return program;
}
