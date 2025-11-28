#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "interpreter.h"
#include "token.h"
#include "env.h"
#include "value.h"
#include "gc.h"
#include "ast.h"

// --- Function Registry ---
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
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len-1] == '\n') buffer[len-1] = '\0';

        char* str = malloc(len + 1);
        strcpy(str, buffer);
        return val_string(str);
    }
    return val_nil();
}

static Value tonumber_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (IS_NUMBER(args[0])) return args[0];
    if (IS_STRING(args[0])) {
        return val_number(strtod(AS_STRING(args[0]), NULL));
    }
    return val_nil();
}

static Value len_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (args[0].type == VAL_ARRAY) {
        return val_number(args[0].as.array->count);
    }
    if (args[0].type == VAL_STRING) {
        return val_number(strlen(AS_STRING(args[0])));
    }
    if (args[0].type == VAL_TUPLE) {
        return val_number(args[0].as.tuple->count);
    }
    if (args[0].type == VAL_DICT) {
        return val_number(args[0].as.dict->count);
    }
    return val_nil();
}

static Value push_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (args[0].type != VAL_ARRAY) return val_nil();
    array_push(&args[0], args[1]);
    return val_nil();
}

static Value pop_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (args[0].type != VAL_ARRAY) return val_nil();
    
    ArrayValue* a = args[0].as.array;
    if (a->count == 0) return val_nil();
    
    Value result = a->elements[a->count - 1];
    a->count--;
    return result;
}

static Value range_native(int argCount, Value* args) {
    if (argCount < 1 || argCount > 2) return val_nil();
    
    int start = 0, end = 0;
    
    if (argCount == 1) {
        if (!IS_NUMBER(args[0])) return val_nil();
        end = (int)AS_NUMBER(args[0]);
    } else {
        if (!IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
        start = (int)AS_NUMBER(args[0]);
        end = (int)AS_NUMBER(args[1]);
    }

    Value arr = val_array();
    for (int i = start; i < end; i++) {
        array_push(&arr, val_number(i));
    }
    return arr;
}

// String functions
static Value split_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    return string_split(AS_STRING(args[0]), AS_STRING(args[1]));
}

static Value join_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_ARRAY(args[0]) || !IS_STRING(args[1])) return val_nil();
    return string_join(&args[0], AS_STRING(args[1]));
}

static Value replace_native(int argCount, Value* args) {
    if (argCount != 3) return val_nil();
    if (!IS_STRING(args[0]) || !IS_STRING(args[1]) || !IS_STRING(args[2])) return val_nil();
    char* result = string_replace(AS_STRING(args[0]), AS_STRING(args[1]), AS_STRING(args[2]));
    return val_string(result);
}

static Value upper_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_STRING(args[0])) return val_nil();
    char* result = string_upper(AS_STRING(args[0]));
    return val_string(result);
}

static Value lower_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_STRING(args[0])) return val_nil();
    char* result = string_lower(AS_STRING(args[0]));
    return val_string(result);
}

static Value strip_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_STRING(args[0])) return val_nil();
    char* result = string_strip(AS_STRING(args[0]));
    return val_string(result);
}

static Value slice_native(int argCount, Value* args) {
    if (argCount != 3) return val_nil();
    if (!IS_ARRAY(args[0]) || !IS_NUMBER(args[1]) || !IS_NUMBER(args[2])) return val_nil();
    int start = (int)AS_NUMBER(args[1]);
    int end = (int)AS_NUMBER(args[2]);
    return array_slice(&args[0], start, end);
}

// Dictionary functions
static Value dict_keys_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_DICT(args[0])) return val_nil();
    return dict_keys(&args[0]);
}

static Value dict_values_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    if (!IS_DICT(args[0])) return val_nil();
    return dict_values(&args[0]);
}

static Value dict_has_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_DICT(args[0]) || !IS_STRING(args[1])) return val_nil();
    return val_bool(dict_has(&args[0], AS_STRING(args[1])));
}

static Value dict_delete_native(int argCount, Value* args) {
    if (argCount != 2) return val_nil();
    if (!IS_DICT(args[0]) || !IS_STRING(args[1])) return val_nil();
    dict_delete(&args[0], AS_STRING(args[1]));
    return val_nil();
}

// GC functions
static Value gc_collect_native(int argCount, Value* args) {
    gc_collect();
    return val_nil();
}

static Value gc_stats_native(int argCount, Value* args) {
    GCStats stats = gc_get_stats();
    Value dict = val_dict();
    
    dict_set(&dict, "bytes_allocated", val_number(stats.bytes_allocated));
    dict_set(&dict, "num_objects", val_number(stats.num_objects));
    dict_set(&dict, "collections", val_number(stats.collections));
    dict_set(&dict, "objects_freed", val_number(stats.objects_freed));
    dict_set(&dict, "next_gc", val_number(stats.next_gc));
    
    return dict;
}

static Value gc_enable_native(int argCount, Value* args) {
    gc_enable();
    return val_nil();
}

static Value gc_disable_native(int argCount, Value* args) {
    gc_disable();
    return val_nil();
}

void init_stdlib(Env* env) {
    // Core functions
    env_define(env, "clock", 5, val_native(clock_native));
    env_define(env, "input", 5, val_native(input_native));
    env_define(env, "tonumber", 8, val_native(tonumber_native));
    env_define(env, "len", 3, val_native(len_native));
    
    // Array functions
    env_define(env, "push", 4, val_native(push_native));
    env_define(env, "pop", 3, val_native(pop_native));
    env_define(env, "range", 5, val_native(range_native));
    env_define(env, "slice", 5, val_native(slice_native));
    
    // String functions
    env_define(env, "split", 5, val_native(split_native));
    env_define(env, "join", 4, val_native(join_native));
    env_define(env, "replace", 7, val_native(replace_native));
    env_define(env, "upper", 5, val_native(upper_native));
    env_define(env, "lower", 5, val_native(lower_native));
    env_define(env, "strip", 5, val_native(strip_native));
    
    // Dictionary functions
    env_define(env, "dict_keys", 9, val_native(dict_keys_native));
    env_define(env, "dict_values", 11, val_native(dict_values_native));
    env_define(env, "dict_has", 8, val_native(dict_has_native));
    env_define(env, "dict_delete", 11, val_native(dict_delete_native));
    
    // GC functions
    env_define(env, "gc_collect", 10, val_native(gc_collect_native));
    env_define(env, "gc_stats", 8, val_native(gc_stats_native));
    env_define(env, "gc_enable", 9, val_native(gc_enable_native));
    env_define(env, "gc_disable", 10, val_native(gc_disable_native));
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

    if (b->op.type == TOKEN_OR) {
        if (is_truthy(left)) {
            return val_bool(1);
        }
        Value right = eval_expr(b->right, env);
        return val_bool(is_truthy(right));
    }

    if (b->op.type == TOKEN_AND) {
        if (!is_truthy(left)) {
            return val_bool(0);
        }
        Value right = eval_expr(b->right, env);
        return val_bool(is_truthy(right));
    }

    Value right = eval_expr(b->right, env);

    if (b->op.type == TOKEN_EQ || b->op.type == TOKEN_NEQ) {
        int equal = values_equal(left, right);
        if (b->op.type == TOKEN_EQ) return val_bool(equal);
        if (b->op.type == TOKEN_NEQ) return val_bool(!equal);
    }

    if (b->op.type == TOKEN_GT || b->op.type == TOKEN_LT) {
        if (!IS_NUMBER(left) || !IS_NUMBER(right)) {
            fprintf(stderr, "Runtime Error: Operands must be numbers.\n");
            return val_nil();
        }
        double l = AS_NUMBER(left);
        double r = AS_NUMBER(right);
        if (b->op.type == TOKEN_GT) return val_bool(l > r);
        if (b->op.type == TOKEN_LT) return val_bool(l < r);
    }

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
            fprintf(stderr, "Runtime Error: Operands must be numbers or strings.\n");
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
        
        case EXPR_ARRAY: {
            Value arr = val_array();
            for (int i = 0; i < expr->as.array.count; i++) {
                Value elem = eval_expr(expr->as.array.elements[i], env);
                array_push(&arr, elem);
            }
            return arr;
        }

        case EXPR_DICT: {
            Value dict = val_dict();
            for (int i = 0; i < expr->as.dict.count; i++) {
                Value val = eval_expr(expr->as.dict.values[i], env);
                dict_set(&dict, expr->as.dict.keys[i], val);
            }
            return dict;
        }

        case EXPR_TUPLE: {
            Value* elements = malloc(sizeof(Value) * expr->as.tuple.count);
            for (int i = 0; i < expr->as.tuple.count; i++) {
                elements[i] = eval_expr(expr->as.tuple.elements[i], env);
            }
            return val_tuple(elements, expr->as.tuple.count);
        }

        case EXPR_INDEX: {
            Value arr = eval_expr(expr->as.index.array, env);
            Value idx = eval_expr(expr->as.index.index, env);
            
            if (arr.type == VAL_ARRAY && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                return array_get(&arr, index);
            }
            
            if (arr.type == VAL_TUPLE && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                return tuple_get(&arr, index);
            }
            
            if (arr.type == VAL_DICT && IS_STRING(idx)) {
                return dict_get(&arr, AS_STRING(idx));
            }
            
            fprintf(stderr, "Runtime Error: Invalid indexing operation.\n");
            return val_nil();
        }

        case EXPR_SLICE: {
            Value arr = eval_expr(expr->as.slice.array, env);
            
            if (arr.type != VAL_ARRAY) {
                fprintf(stderr, "Runtime Error: Can only slice arrays.\n");
                return val_nil();
            }
            
            int start = 0;
            int end = arr.as.array->count;
            
            if (expr->as.slice.start != NULL) {
                Value start_val = eval_expr(expr->as.slice.start, env);
                if (!IS_NUMBER(start_val)) return val_nil();
                start = (int)AS_NUMBER(start_val);
            }
            
            if (expr->as.slice.end != NULL) {
                Value end_val = eval_expr(expr->as.slice.end, env);
                if (!IS_NUMBER(end_val)) return val_nil();
                end = (int)AS_NUMBER(end_val);
            }
            
            return array_slice(&arr, start, end);
        }

        case EXPR_GET: {
            Value object = eval_expr(expr->as.get.object, env);
            
            if (!IS_INSTANCE(object)) {
                fprintf(stderr, "Runtime Error: Only instances have properties.\n");
                return val_nil();
            }
            
            Token prop = expr->as.get.property;
            return instance_get_field(object.as.instance, prop.start);
        }

        case EXPR_SET: {
            Value object = eval_expr(expr->as.set.object, env);
            
            if (!IS_INSTANCE(object)) {
                fprintf(stderr, "Runtime Error: Only instances have properties.\n");
                return val_nil();
            }
            
            Value value = eval_expr(expr->as.set.value, env);
            Token prop = expr->as.set.property;
            instance_set_field(object.as.instance, prop.start, value);
            return value;
        }

        case EXPR_BINARY:
            return eval_binary(&expr->as.binary, env);

        case EXPR_VARIABLE: {
            Value val;
            Token t = expr->as.variable.name;
            if (env_get(env, t.start, t.length, &val)) {
                return val;
            }
            fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.\n", t.length, t.start);
            return val_nil();
        }

        case EXPR_CALL: {
            Token callee = expr->as.call.callee;
            
            // Check for class constructor call
            Value classVal;
            if (env_get(env, callee.start, callee.length, &classVal)) {
                // Native function
                if (classVal.type == VAL_NATIVE) {
                    Value args[255];
                    int count = expr->as.call.arg_count;
                    for (int i = 0; i < count; i++) {
                        args[i] = eval_expr(expr->as.call.args[i], env);
                    }
                    return classVal.as.native(count, args);
                }
                
                // Class constructor
                if (classVal.type == VAL_CLASS) {
                    ClassValue* class_def = classVal.as.class_val;
                    InstanceValue* instance = instance_create(class_def);
                    Value inst_val = val_instance(instance);
                    
                    // Look for init method
                    Method* init_method = class_find_method(class_def, "init", 4);
                    if (init_method) {
                        ProcStmt* init_stmt = (ProcStmt*)init_method->method_stmt;
                        
                        // Create method scope with self
                        Env* method_env = env_create(env);
                        env_define(method_env, "self", 4, inst_val);
                        
                        // Bind parameters (skip self as first param)
                        int param_start = (init_stmt->param_count > 0 && 
                                          strncmp(init_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;
                        
                        for (int i = param_start; i < init_stmt->param_count; i++) {
                            if (i - param_start < expr->as.call.arg_count) {
                                Value arg = eval_expr(expr->as.call.args[i - param_start], env);
                                env_define(method_env, init_stmt->params[i].start, 
                                         init_stmt->params[i].length, arg);
                            }
                        }
                        
                        interpret(init_stmt->body, method_env);
                    }
                    
                    return inst_val;
                }
            }

            // Regular function call
            ProcStmt* func = find_function(callee.start, callee.length);
            if (func) {
                if (expr->as.call.arg_count != func->param_count) {
                     fprintf(stderr, "Runtime Error: Arity mismatch.\n");
                     return val_nil();
                }

                Env* scope = env_create(env); 
                for (int i = 0; i < func->param_count; i++) {
                    Value argVal = eval_expr(expr->as.call.args[i], env);
                    Token paramName = func->params[i];
                    env_define(scope, paramName.start, paramName.length, argVal);
                }

                ExecResult res = interpret(func->body, scope);
                return res.value;
            }

            fprintf(stderr, "Runtime Error: Undefined procedure '%.*s'.\n", callee.length, callee.start);
            return val_nil();
        }

        default:
            return val_nil();
    }
}

ExecResult interpret(Stmt* stmt, Env* env) {
    if (!stmt) return (ExecResult){ val_nil(), 0, 0, 0 };

    switch (stmt->type) {
        case STMT_PRINT: {
            Value val = eval_expr(stmt->as.print.expression, env);
            print_value(val);
            printf("\n");
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_LET: {
            Value val = val_nil();
            if (stmt->as.let.initializer != NULL) {
                val = eval_expr(stmt->as.let.initializer, env);
            }
            Token t = stmt->as.let.name;
            env_define(env, t.start, t.length, val);
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_EXPRESSION: {
            (void)eval_expr(stmt->as.expression, env);
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_BLOCK: {
            Stmt* current = stmt->as.block.statements;
            while (current != NULL) {
                ExecResult res = interpret(current, env);
                if (res.is_returning || res.is_breaking || res.is_continuing) return res;
                current = current->next;
            }
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_IF: {
            Value cond = eval_expr(stmt->as.if_stmt.condition, env);
            if (is_truthy(cond)) {
                return interpret(stmt->as.if_stmt.then_branch, env);
            } else if (stmt->as.if_stmt.else_branch != NULL) {
                return interpret(stmt->as.if_stmt.else_branch, env);
            }
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_WHILE: {
            while (1) {
                Value cond = eval_expr(stmt->as.while_stmt.condition, env);
                if (!is_truthy(cond)) break;
                
                ExecResult res = interpret(stmt->as.while_stmt.body, env);
                if (res.is_returning) return res;
                if (res.is_breaking) break;
                if (res.is_continuing) continue;
            }
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_FOR: {
            Value iterable = eval_expr(stmt->as.for_stmt.iterable, env);
            
            if (iterable.type != VAL_ARRAY) {
                fprintf(stderr, "Runtime Error: for loop iterable must be an array.\n");
                return (ExecResult){ val_nil(), 0, 0, 0 };
            }

            Env* loop_env = env_create(env);
            Token var = stmt->as.for_stmt.variable;

            ArrayValue* arr = iterable.as.array;
            for (int i = 0; i < arr->count; i++) {
                env_define(loop_env, var.start, var.length, arr->elements[i]);

                ExecResult res = interpret(stmt->as.for_stmt.body, loop_env);
                if (res.is_returning) return res;
                if (res.is_breaking) break;
                if (res.is_continuing) continue;
            }

            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_BREAK:
            return (ExecResult){ val_nil(), 0, 1, 0 };

        case STMT_CONTINUE:
            return (ExecResult){ val_nil(), 0, 0, 1 };

        case STMT_PROC: {
            define_function(&stmt->as.proc);
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_CLASS: {
            // Get parent class if specified
            ClassValue* parent = NULL;
            if (stmt->as.class_stmt.has_parent) {
                Value parent_val;
                Token parent_name = stmt->as.class_stmt.parent;
                if (env_get(env, parent_name.start, parent_name.length, &parent_val)) {
                    if (parent_val.type == VAL_CLASS) {
                        parent = parent_val.as.class_val;
                    } else {
                        fprintf(stderr, "Runtime Error: Parent must be a class.\n");
                        return (ExecResult){ val_nil(), 0, 0, 0 };
                    }
                } else {
                    fprintf(stderr, "Runtime Error: Undefined parent class.\n");
                    return (ExecResult){ val_nil(), 0, 0, 0 };
                }
            }
            
            // Create class
            Token name = stmt->as.class_stmt.name;
            ClassValue* class_val = class_create(name.start, name.length, parent);
            
            // Add methods
            Stmt* method = stmt->as.class_stmt.methods;
            while (method != NULL) {
                if (method->type == STMT_PROC) {
                    ProcStmt* proc = &method->as.proc;
                    class_add_method(class_val, proc->name.start, proc->name.length, (void*)proc);
                }
                method = method->next;
            }
            
            // Register class in environment
            Value class_value = val_class(class_val);
            env_define(env, name.start, name.length, class_value);
            
            return (ExecResult){ val_nil(), 0, 0, 0 };
        }

        case STMT_RETURN: {
            Value val = val_nil();
            if (stmt->as.ret.value) val = eval_expr(stmt->as.ret.value, env);
            return (ExecResult){ val, 1, 0, 0 };
        }
    }
    return (ExecResult){ val_nil(), 0, 0, 0 };
}