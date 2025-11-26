#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "interpreter.h"
#include "token.h"
#include "env.h"

// --- Function Registry (Simple Global Linked List) ---
typedef struct ProcNode {
    const char* name;
    int name_len;
    ProcStmt stmt; // Copy of the AST node struct
    struct ProcNode* next;
} ProcNode;

static ProcNode* functions = NULL;

static void define_function(ProcStmt* stmt) {
    ProcNode* node = malloc(sizeof(ProcNode));
    node->name = stmt->name.start; 
    node->name_len = stmt->name.length;
    node->stmt = *stmt;
    node->next = functions;
    functions = node;
}

static ProcStmt* find_function(const char* name, int len) {
    ProcNode* current = functions;
    while (current) {
        if (strncmp(current->name, name, len) == 0 && len == current->name_len) {
            return &current->stmt;
        }
        current = current->next;
    }
    return NULL;
}

// --- Evaluator ---

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
                fprintf(stderr, "Runtime Error: Division by zero.");
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
            Token t = expr->as.variable.name;
            if (env_get(env, t.start, t.length, &val)) {
                return val;
            }
            fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.", t.length, t.start);
            return 0;
        }
        case EXPR_CALL: {
            Token callee = expr->as.call.callee;
            ProcStmt* func = find_function(callee.start, callee.length);
            if (!func) {
                fprintf(stderr, "Runtime Error: Undefined procedure '%.*s'.", callee.length, callee.start);
                return 0;
            }

            if (expr->as.call.arg_count != func->param_count) {
                 fprintf(stderr, "Runtime Error: Expected %d arguments but got %d.",
                        func->param_count, expr->as.call.arg_count);
                 return 0;
            }

            // 1. Create new scope (child of global/current)
            // Using 'env' as parent creates a closure-like effect (lexical scope)
            // Using 'functions' implies global scope. For simplicity, use 'env'.
            Env* scope = env_create(env);

            // 2. Bind arguments
            for (int i = 0; i < func->param_count; i++) {
                double argVal = eval_expr(expr->as.call.args[i], env); // Eval in CALLER scope
                Token paramName = func->params[i];
                env_define(scope, paramName.start, paramName.length, argVal);
            }

            // 3. Execute body
            interpret(func->body, scope);
            // In future: return value from interpret or use a result register
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
            double val = eval_expr(stmt->as.print.expression, env);
            printf("%g", val);
            break;
        }
        case STMT_LET: {
            double val = 0;
            if (stmt->as.let.initializer != NULL) {
                val = eval_expr(stmt->as.let.initializer, env);
            }
            Token t = stmt->as.let.name;
            env_define(env, t.start, t.length, val);
            break;
        }
        case STMT_EXPRESSION: {
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
                double cond = eval_expr(stmt->as.while_stmt.condition, env);
                if (cond == 0.0) break;
                interpret(stmt->as.while_stmt.body, env);
            }
            break;
        }
        case STMT_PROC: {
            define_function(&stmt->as.proc);
            break;
        }
    }
}
