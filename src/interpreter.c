#include <stdio.h>
#include "interpreter.h"
#include "token.h"
#include "env.h"

static double eval_expr(Expr* expr, Env* env);

static double eval_binary(BinaryExpr* b, Env* env) {
    double left = eval_expr(b->left, env);
    double right = eval_expr(b->right, env);

    switch (b->op.type) {
        case TOKEN_PLUS:  return left + right;
        case TOKEN_MINUS: return left - right;
        case TOKEN_STAR:  return left * right;
        case TOKEN_SLASH:
            if (right == 0) {
                fprintf(stderr, "Runtime Error: Division by zero.\n");
                return 0;
            }
            return left / right;
        case TOKEN_GT:    return left > right ? 1.0 : 0.0;
        case TOKEN_LT:    return left < right ? 1.0 : 0.0;
        default:          return 0;
    }
}

static double eval_expr(Expr* expr, Env* env) {
    switch (expr->type) {
        case EXPR_NUMBER:
            return expr->as.number.value;
        case EXPR_BINARY:
            return eval_binary(&expr->as.binary, env);
        case EXPR_VARIABLE: {
            double val;
            // FIXED: Removed stray '2' here
            Token t = expr->as.variable.name;
            if (env_get(env, t.start, t.length, &val)) {
                return val;
            }
            fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.\n", t.length, t.start);
            return 0;
        }
        default:
            return 0;
    }
}

void interpret(Stmt* stmt, Env* env) {
    if (!stmt) return;

    switch (stmt->type) {
        case STMT_PRINT: {
            // FIXED: Pass 'env' directly, not '*env'
            double val = eval_expr(stmt->as.print.expression, env);
            printf("%g\n", val);
            break;
        }
        case STMT_LET: {
            double val = 0;
            if (stmt->as.let.initializer != NULL) {
                // FIXED: Pass 'env' directly
                val = eval_expr(stmt->as.let.initializer, env);
            }
            Token t = stmt->as.let.name;
            // FIXED: Pass 'env' directly
            env_define(env, t.start, t.length, val);
            break;
        }
        case STMT_EXPRESSION: {
            // FIXED: Pass 'env' directly
            (void)eval_expr(stmt->as.expression, env);
            break;
        }
        case STMT_BLOCK: {
            Stmt* current = stmt->as.block.statements;
            while (current != NULL) {
                interpret(current, env);
                current = current->next;
            }
            break;
        }
        case STMT_IF: {
            // FIXED: Pass 'env' directly
            double cond = eval_expr(stmt->as.if_stmt.condition, env);
            if (cond != 0.0) {
                interpret(stmt->as.if_stmt.then_branch, env);
            } else if (stmt->as.if_stmt.else_branch != NULL) {
                interpret(stmt->as.if_stmt.else_branch, env);
            }
            break;
        }
        case STMT_WHILE: {
            while (1) {
                // FIXED: Pass 'env' directly
                double cond = eval_expr(stmt->as.while_stmt.condition, env);
                if (cond == 0.0) break;
                interpret(stmt->as.while_stmt.body, env);
            }
            break;
        }
    }
}
