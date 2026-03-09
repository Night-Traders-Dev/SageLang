#include "pass.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gc.h"

// ============================================================================
// Constant Folding Pass
//
// Evaluates constant expressions at compile time:
// - Number arithmetic: 2 + 3 -> 5
// - String concatenation: "a" + "b" -> "ab"
// - Boolean logic: true and false -> false
// - Constant conditions: if true -> then-branch only
// ============================================================================

static Expr* fold_expr(Expr* expr);

static int is_number_literal(const Expr* e) {
    return e != NULL && e->type == EXPR_NUMBER;
}

static int is_string_literal(const Expr* e) {
    return e != NULL && e->type == EXPR_STRING;
}

static int is_bool_literal(const Expr* e) {
    return e != NULL && e->type == EXPR_BOOL;
}

static Expr* fold_binary(Expr* expr) {
    BinaryExpr* bin = &expr->as.binary;
    bin->left = fold_expr(bin->left);
    bin->right = fold_expr(bin->right);

    const char* op = bin->op.start;
    int op_len = bin->op.length;

    // Number + Number arithmetic
    if (is_number_literal(bin->left) && is_number_literal(bin->right)) {
        double l = bin->left->as.number.value;
        double r = bin->right->as.number.value;
        double result = 0;
        int is_bool_result = 0;
        int bool_val = 0;

        if (op_len == 1) {
            switch (*op) {
                case '+': result = l + r; break;
                case '-': result = l - r; break;
                case '*': result = l * r; break;
                case '/':
                    if (r == 0) return expr; // don't fold division by zero
                    result = l / r;
                    break;
                case '%':
                    if (r == 0) return expr;
                    result = fmod(l, r);
                    break;
                case '<': is_bool_result = 1; bool_val = l < r; break;
                case '>': is_bool_result = 1; bool_val = l > r; break;
                default: return expr;
            }
        } else if (op_len == 2) {
            if (op[0] == '=' && op[1] == '=') {
                is_bool_result = 1; bool_val = l == r;
            } else if (op[0] == '!' && op[1] == '=') {
                is_bool_result = 1; bool_val = l != r;
            } else if (op[0] == '<' && op[1] == '=') {
                is_bool_result = 1; bool_val = l <= r;
            } else if (op[0] == '>' && op[1] == '=') {
                is_bool_result = 1; bool_val = l >= r;
            } else {
                return expr;
            }
        } else {
            return expr;
        }

        // Replace with folded constant
        free_expr(bin->left);
        free_expr(bin->right);
        if (is_bool_result) {
            expr->type = EXPR_BOOL;
            expr->as.boolean.value = bool_val;
        } else {
            expr->type = EXPR_NUMBER;
            expr->as.number.value = result;
        }
        return expr;
    }

    // String + String concatenation
    if (is_string_literal(bin->left) && is_string_literal(bin->right)) {
        if (op_len == 1 && *op == '+') {
            const char* ls = bin->left->as.string.value;
            const char* rs = bin->right->as.string.value;
            size_t llen = strlen(ls);
            size_t rlen = strlen(rs);
            char* concat = SAGE_ALLOC(llen + rlen + 1);
            memcpy(concat, ls, llen);
            memcpy(concat + llen, rs, rlen + 1);

            free_expr(bin->left);
            free_expr(bin->right);
            expr->type = EXPR_STRING;
            expr->as.string.value = concat;
            return expr;
        }
    }

    // Boolean logic: true and false, true or false
    if (is_bool_literal(bin->left) && is_bool_literal(bin->right)) {
        int l = bin->left->as.boolean.value;
        int r = bin->right->as.boolean.value;
        int result = 0;
        int folded = 0;

        if (op_len == 3 && memcmp(op, "and", 3) == 0) {
            result = l && r; folded = 1;
        } else if (op_len == 2 && memcmp(op, "or", 2) == 0) {
            result = l || r; folded = 1;
        }

        if (folded) {
            free_expr(bin->left);
            free_expr(bin->right);
            expr->type = EXPR_BOOL;
            expr->as.boolean.value = result;
            return expr;
        }
    }

    return expr;
}

static Expr* fold_expr(Expr* expr) {
    if (expr == NULL) return NULL;

    switch (expr->type) {
        case EXPR_BINARY:
            return fold_binary(expr);
        case EXPR_CALL: {
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                expr->as.call.args[i] = fold_expr(expr->as.call.args[i]);
            }
            expr->as.call.callee = fold_expr(expr->as.call.callee);
            break;
        }
        case EXPR_ARRAY:
            for (int i = 0; i < expr->as.array.count; i++) {
                expr->as.array.elements[i] = fold_expr(expr->as.array.elements[i]);
            }
            break;
        case EXPR_INDEX:
            expr->as.index.array = fold_expr(expr->as.index.array);
            expr->as.index.index = fold_expr(expr->as.index.index);
            break;
        case EXPR_DICT:
            for (int i = 0; i < expr->as.dict.count; i++) {
                expr->as.dict.values[i] = fold_expr(expr->as.dict.values[i]);
            }
            break;
        case EXPR_TUPLE:
            for (int i = 0; i < expr->as.tuple.count; i++) {
                expr->as.tuple.elements[i] = fold_expr(expr->as.tuple.elements[i]);
            }
            break;
        case EXPR_SLICE:
            expr->as.slice.array = fold_expr(expr->as.slice.array);
            expr->as.slice.start = fold_expr(expr->as.slice.start);
            expr->as.slice.end = fold_expr(expr->as.slice.end);
            break;
        case EXPR_GET:
            expr->as.get.object = fold_expr(expr->as.get.object);
            break;
        case EXPR_SET:
            expr->as.set.object = fold_expr(expr->as.set.object);
            expr->as.set.value = fold_expr(expr->as.set.value);
            break;
        default:
            break;
    }
    return expr;
}

// ============================================================================
// Statement-level constant folding
// ============================================================================

static void fold_stmt(Stmt* stmt);

static void fold_stmt_list(Stmt* head) {
    for (Stmt* s = head; s != NULL; s = s->next) {
        fold_stmt(s);
    }
}

static void fold_stmt(Stmt* stmt) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT:
            stmt->as.print.expression = fold_expr(stmt->as.print.expression);
            break;
        case STMT_EXPRESSION:
            stmt->as.expression = fold_expr(stmt->as.expression);
            break;
        case STMT_LET:
            stmt->as.let.initializer = fold_expr(stmt->as.let.initializer);
            break;
        case STMT_IF: {
            stmt->as.if_stmt.condition = fold_expr(stmt->as.if_stmt.condition);
            fold_stmt_list(stmt->as.if_stmt.then_branch);
            fold_stmt_list(stmt->as.if_stmt.else_branch);

            // If condition is constant true, replace with then-branch
            Expr* cond = stmt->as.if_stmt.condition;
            if (cond != NULL && cond->type == EXPR_BOOL) {
                if (cond->as.boolean.value) {
                    // Replace if-stmt with its then-branch (block)
                    // We convert this to a block statement
                    Stmt* then_branch = stmt->as.if_stmt.then_branch;
                    free_expr(cond);
                    free_stmt(stmt->as.if_stmt.else_branch);
                    stmt->type = STMT_BLOCK;
                    stmt->as.block.statements = then_branch;
                } else {
                    // Replace with else-branch or empty
                    Stmt* else_branch = stmt->as.if_stmt.else_branch;
                    free_expr(cond);
                    free_stmt(stmt->as.if_stmt.then_branch);
                    if (else_branch != NULL) {
                        stmt->type = STMT_BLOCK;
                        stmt->as.block.statements = else_branch;
                    } else {
                        // Convert to no-op (empty expression)
                        stmt->type = STMT_EXPRESSION;
                        stmt->as.expression = new_nil_expr();
                    }
                }
            }
            break;
        }
        case STMT_BLOCK:
            fold_stmt_list(stmt->as.block.statements);
            break;
        case STMT_WHILE:
            stmt->as.while_stmt.condition = fold_expr(stmt->as.while_stmt.condition);
            fold_stmt_list(stmt->as.while_stmt.body);
            // If condition is constant false, eliminate loop
            if (stmt->as.while_stmt.condition != NULL &&
                stmt->as.while_stmt.condition->type == EXPR_BOOL &&
                !stmt->as.while_stmt.condition->as.boolean.value) {
                free_expr(stmt->as.while_stmt.condition);
                free_stmt(stmt->as.while_stmt.body);
                stmt->type = STMT_EXPRESSION;
                stmt->as.expression = new_nil_expr();
            }
            break;
        case STMT_PROC:
            fold_stmt_list(stmt->as.proc.body);
            break;
        case STMT_FOR:
            stmt->as.for_stmt.iterable = fold_expr(stmt->as.for_stmt.iterable);
            fold_stmt_list(stmt->as.for_stmt.body);
            break;
        case STMT_RETURN:
            stmt->as.ret.value = fold_expr(stmt->as.ret.value);
            break;
        case STMT_CLASS:
            fold_stmt_list(stmt->as.class_stmt.methods);
            break;
        case STMT_MATCH:
            stmt->as.match_stmt.value = fold_expr(stmt->as.match_stmt.value);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                stmt->as.match_stmt.cases[i]->pattern = fold_expr(stmt->as.match_stmt.cases[i]->pattern);
                fold_stmt_list(stmt->as.match_stmt.cases[i]->body);
            }
            fold_stmt_list(stmt->as.match_stmt.default_case);
            break;
        case STMT_TRY:
            fold_stmt_list(stmt->as.try_stmt.try_block);
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                fold_stmt_list(stmt->as.try_stmt.catches[i]->body);
            }
            fold_stmt_list(stmt->as.try_stmt.finally_block);
            break;
        case STMT_RAISE:
            stmt->as.raise.exception = fold_expr(stmt->as.raise.exception);
            break;
        case STMT_YIELD:
            stmt->as.yield_stmt.value = fold_expr(stmt->as.yield_stmt.value);
            break;
        case STMT_DEFER:
        case STMT_IMPORT:
        case STMT_BREAK:
        case STMT_CONTINUE:
            break;
    }
}

// ============================================================================
// Pass Entry Point
// ============================================================================

Stmt* pass_constfold(Stmt* program, PassContext* ctx) {
    (void)ctx;
    fold_stmt_list(program);
    return program;
}
