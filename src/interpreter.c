#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "interpreter.h"
#include "token.h"
#include "env.h"
#include "value.h"

// --- Function Registry (User Defined Procs) ---
typedef struct ProcNode {
    const char* name;
    int name_len;
    ProcStmt stmt;
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

// --- Native Functions ---

static Value clock_native(int argCount, Value* args) {
    return val_number((double)clock() / CLOCKS_PER_SEC);
}

static Value input_native(int argCount, Value* args) {
    char buffer[1024];
    // Print prompt? No, just read.
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') buffer[len-1] = '\0';

        // Deep copy string
        char* str = malloc(len + 1);
        strcpy(str, buffer);
        return val_string(str);
    }
    return val_nil();
}

// Public API to init stdlib
void init_stdlib(Env* env) {
    env_define(env, "clock", 5, val_native(clock_native));
    env_define(env, "input", 5, val_native(input_native));
}

// --- Helper: Truthiness ---
static int is_truthy(Value v) {
    if (IS_NIL(v)) return 0;
    if (IS_BOOL(v)) return AS_BOOL(v);
    return 1; 
}

// --- Forward Declaration ---
static Value eval_expr(Expr* expr, Env* env);

// --- Evaluator ---

static Value eval_binary(BinaryExpr* b, Env* env) {
    Value left = eval_expr(b->left, env);
    Value right = eval_expr(b->right, env);

    // Comparison
    if (b->op.type == TOKEN_EQ || b->op.type == TOKEN_NEQ) {
        int equal = values_equal(left, right);
        if (b->op.type == TOKEN_EQ) return val_bool(equal);
        if (b->op.type == TOKEN_NEQ) return val_bool(!equal);
    }

    if (b->op.type == TOKEN_GT || b->op.type == TOKEN_LT) {
        if (!IS_NUMBER(left) || !IS_NUMBER(right)) {
            fprintf(stderr, "Runtime Error: Operands must be numbers.");
            return val_nil();
        }
        double l = AS_NUMBER(left);
        double r = AS_NUMBER(right);
        if (b->op.type == TOKEN_GT) return val_bool(l > r);
        if (b->op.type == TOKEN_LT) return val_bool(l < r);
    }

    // Arithmetic
    switch (b->op.type) {
        case TOKEN_PLUS:
            if (IS_NUMBER(left) && IS_NUMBER(right)) {
                return val_number(AS_NUMBER(left) + AS_NUMBER(right));
            }
            if (IS_STRING(left) && IS_STRING(right)) {
                char* s1 = AS_STRING(left);
                char* s2 = AS_STRING(right);
                int len1 = strlen(s1);
                int len2 = strlen(s2);
                char* result = malloc(len1 + len2 + 1);
                strcpy(result, s1);
                strcat(result, s2);
                return val_string(result);
            }
            fprintf(stderr, "Runtime Error: Operands must be numbers or strings.");
            return val_nil();

        case TOKEN_MINUS:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return val_nil();
            return val_number(AS_NUMBER(left) - AS_NUMBER(right));

        case TOKEN_STAR:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return val_nil();
            return val_number(AS_NUMBER(left) * AS_NUMBER(right));

        case TOKEN_SLASH:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return val_nil();
            if (AS_NUMBER(right) == 0) return val_nil();
            return val_number(AS_NUMBER(left) / AS_NUMBER(right));

        default:
            return val_nil();
    }
}

static Value eval_expr(Expr* expr, Env* env) {
    switch (expr->type) {
        case EXPR_NUMBER: return val_number(expr->as.number.value);
        case EXPR_STRING: return val_string(expr->as.string.value);
        case EXPR_BOOL:   return val_bool(expr->as.boolean.value);
        case EXPR_NIL:    return val_nil();

        case EXPR_BINARY:
            return eval_binary(&expr->as.binary, env);

        case EXPR_VARIABLE: {
            Value val;
            Token t = expr->as.variable.name;
            if (env_get(env, t.start, t.length, &val)) {
                return val;
            }
            fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.", t.length, t.start);
            return val_nil();
        }

        case EXPR_CALL: {
            Token callee = expr->as.call.callee;

            // 1. Check Environment (Variables / Native Functions)
            Value funcVal;
            if (env_get(env, callee.start, callee.length, &funcVal)) {
                if (funcVal.type == VAL_NATIVE) {
                    // Evaluate args
                    Value args[255];
                    int count = expr->as.call.arg_count;
                    for (int i = 0; i < count; i++) {
                        args[i] = eval_expr(expr->as.call.args[i], env);
                    }
                    return funcVal.as.native(count, args);
                }
                // If it's a variable but NOT a native fn (e.g. a number), error?
                // For now, fall through or error.
            }

            // 2. Check User Function Registry
            ProcStmt* func = find_function(callee.start, callee.length);
            if (func) {
                if (expr->as.call.arg_count != func->param_count) {
                     fprintf(stderr, "Runtime Error: Arity mismatch.");
                     return val_nil();
                }

                Env* scope = env_create(env); 
                for (int i = 0; i < func->param_count; i++) {
                    Value argVal = eval_expr(expr->as.call.args[i], env);
                    Token paramName = func->params[i];
                    env_define(scope, paramName.start, paramName.length, argVal);
                }
                interpret(func->body, scope);
                return val_nil(); 
            }

            fprintf(stderr, "Runtime Error: Undefined procedure '%.*s'.", callee.length, callee.start);
            return val_nil();
        }
        default:
            return val_nil();
    }
}

void interpret(Stmt* stmt, Env* env) {
    if (!stmt) return;

    switch (stmt->type) {
        case STMT_PRINT: {
            Value val = eval_expr(stmt->as.print.expression, env);
            print_value(val);
            printf("\n");
            break;
        }
        case STMT_LET: {
            Value val = val_nil();
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
            Value cond = eval_expr(stmt->as.if_stmt.condition, env);
            if (is_truthy(cond)) {
                interpret(stmt->as.if_stmt.then_branch, env);
            } else if (stmt->as.if_stmt.else_branch != NULL) {
                interpret(stmt->as.if_stmt.else_branch, env);
            }
            break;
        }
        case STMT_WHILE: {
            while (1) {
                Value cond = eval_expr(stmt->as.while_stmt.condition, env);
                if (!is_truthy(cond)) break;
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
