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

// Helper macro for creating normal expression results
#define EVAL_RESULT(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil(), 0, NULL })
#define EVAL_EXCEPTION(exc) ((ExecResult){ val_nil(), 0, 0, 0, 1, (exc), 0, NULL })
#define RESULT_NORMAL(v) ((ExecResult){ (v), 0, 0, 0, 0, val_nil(), 0, NULL })

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

// PHASE 7: str() function for number-to-string conversion
static Value str_native(int argCount, Value* args) {
    if (argCount != 1) return val_nil();
    
    char buffer[256];
    if (IS_NUMBER(args[0])) {
        snprintf(buffer, sizeof(buffer), "%g", AS_NUMBER(args[0]));
        char* str = malloc(strlen(buffer) + 1);
        strcpy(str, buffer);
        return val_string(str);
    }
    if (IS_STRING(args[0])) {
        return args[0];
    }
    if (IS_BOOL(args[0])) {
        char* str = AS_BOOL(args[0]) ? "true" : "false";
        char* result = malloc(strlen(str) + 1);
        strcpy(result, str);
        return val_string(result);
    }
    return val_string("nil");
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

// PHASE 7: Generator next() function - Forward declaration (REMOVED static keyword)
ExecResult interpret(Stmt* stmt, Env* env);

static Value native_next(int arg_count, Value* args) {
    if (arg_count != 1) {
        fprintf(stderr, "next() expects 1 argument\n");
        exit(1);
    }
    if (!IS_GENERATOR(args[0])) {
        fprintf(stderr, "next() expects a generator\n");
        exit(1);
    }
    
    GeneratorValue* gen = AS_GENERATOR(args[0]);
    if (gen->is_exhausted) return val_nil();
    
    // Initialize generator environment on first call
    if (!gen->is_started) {
        gen->gen_env = env_create(gen->closure);
        gen->current_stmt = gen->body;
        gen->is_started = 1;
    }
    
    Stmt* current = (Stmt*)gen->current_stmt;
    
    while (current != NULL) {
        ExecResult result = interpret(current, gen->gen_env);
        
        if (result.is_yielding) {
            gen->current_stmt = result.next_stmt;
            return result.value;
        }
        
        if (result.is_returning || current->next == NULL) {
            gen->is_exhausted = 1;
            return val_nil();
        }
        
        if (result.is_throwing) {
            gen->is_exhausted = 1;
            fprintf(stderr, "Exception in generator\n");
            exit(1);
        }
        
        current = current->next;
    }
    
    gen->is_exhausted = 1;
    return val_nil();
}

void init_stdlib(Env* env) {
    // Core functions
    env_define(env, "clock", 5, val_native(clock_native));
    env_define(env, "input", 5, val_native(input_native));
    env_define(env, "tonumber", 8, val_native(tonumber_native));
    env_define(env, "str", 3, val_native(str_native));
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
    
    // PHASE 7: Generator function
    env_define(env, "next", 4, val_native(native_next));
}

// --- Helper: Truthiness ---
static int is_truthy(Value v) {
    if (IS_NIL(v)) return 0;
    if (IS_BOOL(v)) return AS_BOOL(v);
    return 1; 
}

// PHASE 7: Helper to detect if a statement block contains yield
static int contains_yield(Stmt* body) {
    Stmt* current = body;
    while (current != NULL) {
        if (current->type == STMT_YIELD) return 1;
        if (current->type == STMT_BLOCK && contains_yield(current->as.block.statements)) return 1;
        if (current->type == STMT_IF) {
            if (contains_yield(current->as.if_stmt.then_branch)) return 1;
            if (current->as.if_stmt.else_branch && contains_yield(current->as.if_stmt.else_branch)) return 1;
        }
        if (current->type == STMT_WHILE && contains_yield(current->as.while_stmt.body)) return 1;
        if (current->type == STMT_FOR && contains_yield(current->as.for_stmt.body)) return 1;
        current = current->next;
    }
    return 0;
}

// --- Forward Declaration ---
static ExecResult eval_expr(Expr* expr, Env* env);

// --- Evaluator ---

static ExecResult eval_binary(BinaryExpr* b, Env* env) {
    ExecResult left_result = eval_expr(b->left, env);
    if (left_result.is_throwing) return left_result;
    Value left = left_result.value;

    if (b->op.type == TOKEN_OR) {
        if (is_truthy(left)) {
            return EVAL_RESULT(val_bool(1));
        }
        ExecResult right_result = eval_expr(b->right, env);
        if (right_result.is_throwing) return right_result;
        return EVAL_RESULT(val_bool(is_truthy(right_result.value)));
    }

    if (b->op.type == TOKEN_AND) {
        if (!is_truthy(left)) {
            return EVAL_RESULT(val_bool(0));
        }
        ExecResult right_result = eval_expr(b->right, env);
        if (right_result.is_throwing) return right_result;
        return EVAL_RESULT(val_bool(is_truthy(right_result.value)));
    }

    ExecResult right_result = eval_expr(b->right, env);
    if (right_result.is_throwing) return right_result;
    Value right = right_result.value;

    if (b->op.type == TOKEN_EQ || b->op.type == TOKEN_NEQ) {
        int equal = values_equal(left, right);
        if (b->op.type == TOKEN_EQ) return EVAL_RESULT(val_bool(equal));
        if (b->op.type == TOKEN_NEQ) return EVAL_RESULT(val_bool(!equal));
    }

    if (b->op.type == TOKEN_GT || b->op.type == TOKEN_LT || b->op.type == TOKEN_GTE || b->op.type == TOKEN_LTE) {
        if (!IS_NUMBER(left) || !IS_NUMBER(right)) {
            fprintf(stderr, "Runtime Error: Operands must be numbers.\n");
            return EVAL_RESULT(val_nil());
        }
        double l = AS_NUMBER(left);
        double r = AS_NUMBER(right);
        if (b->op.type == TOKEN_GT) return EVAL_RESULT(val_bool(l > r));
        if (b->op.type == TOKEN_LT) return EVAL_RESULT(val_bool(l < r));
        if (b->op.type == TOKEN_GTE) return EVAL_RESULT(val_bool(l >= r));
        if (b->op.type == TOKEN_LTE) return EVAL_RESULT(val_bool(l <= r));
    }

    switch (b->op.type) {
        case TOKEN_PLUS:
            if (IS_NUMBER(left) && IS_NUMBER(right)) {
                return EVAL_RESULT(val_number(AS_NUMBER(left) + AS_NUMBER(right)));
            }
            if (IS_STRING(left) && IS_STRING(right)) {
                char* s1 = AS_STRING(left);
                char* s2 = AS_STRING(right);
                int len1 = strlen(s1);
                int len2 = strlen(s2);
                char* result = malloc(len1 + len2 + 1);
                strcpy(result, s1);
                strcat(result, s2);
                return EVAL_RESULT(val_string(result));
            }
            fprintf(stderr, "Runtime Error: Operands must be numbers or strings.\n");
            return EVAL_RESULT(val_nil());

        case TOKEN_MINUS:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(AS_NUMBER(left) - AS_NUMBER(right)));

        case TOKEN_STAR:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(AS_NUMBER(left) * AS_NUMBER(right)));

        case TOKEN_SLASH:
            if (!IS_NUMBER(left) || !IS_NUMBER(right)) return EVAL_RESULT(val_nil());
            if (AS_NUMBER(right) == 0) return EVAL_RESULT(val_nil());
            return EVAL_RESULT(val_number(AS_NUMBER(left) / AS_NUMBER(right)));

        default:
            return EVAL_RESULT(val_nil());
    }
}

static ExecResult eval_expr(Expr* expr, Env* env) {
    switch (expr->type) {
        case EXPR_NUMBER: return EVAL_RESULT(val_number(expr->as.number.value));
        case EXPR_STRING: return EVAL_RESULT(val_string(expr->as.string.value));
        case EXPR_BOOL:   return EVAL_RESULT(val_bool(expr->as.boolean.value));
        case EXPR_NIL:    return EVAL_RESULT(val_nil());
        
        case EXPR_ARRAY: {
            Value arr = val_array();
            for (int i = 0; i < expr->as.array.count; i++) {
                ExecResult elem_result = eval_expr(expr->as.array.elements[i], env);
                if (elem_result.is_throwing) return elem_result;
                array_push(&arr, elem_result.value);
            }
            return EVAL_RESULT(arr);
        }

        case EXPR_DICT: {
            Value dict = val_dict();
            for (int i = 0; i < expr->as.dict.count; i++) {
                ExecResult val_result = eval_expr(expr->as.dict.values[i], env);
                if (val_result.is_throwing) return val_result;
                dict_set(&dict, expr->as.dict.keys[i], val_result.value);
            }
            return EVAL_RESULT(dict);
        }

        case EXPR_TUPLE: {
            Value* elements = malloc(sizeof(Value) * expr->as.tuple.count);
            for (int i = 0; i < expr->as.tuple.count; i++) {
                ExecResult elem_result = eval_expr(expr->as.tuple.elements[i], env);
                if (elem_result.is_throwing) {
                    free(elements);
                    return elem_result;
                }
                elements[i] = elem_result.value;
            }
            return EVAL_RESULT(val_tuple(elements, expr->as.tuple.count));
        }

        case EXPR_INDEX: {
            ExecResult arr_result = eval_expr(expr->as.index.array, env);
            if (arr_result.is_throwing) return arr_result;
            Value arr = arr_result.value;
            
            ExecResult idx_result = eval_expr(expr->as.index.index, env);
            if (idx_result.is_throwing) return idx_result;
            Value idx = idx_result.value;
            
            if (arr.type == VAL_ARRAY && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                return EVAL_RESULT(array_get(&arr, index));
            }
            
            if (arr.type == VAL_TUPLE && IS_NUMBER(idx)) {
                int index = (int)AS_NUMBER(idx);
                return EVAL_RESULT(tuple_get(&arr, index));
            }
            
            if (arr.type == VAL_DICT && IS_STRING(idx)) {
                return EVAL_RESULT(dict_get(&arr, AS_STRING(idx)));
            }
            
            fprintf(stderr, "Runtime Error: Invalid indexing operation.\n");
            return EVAL_RESULT(val_nil());
        }

        case EXPR_SLICE: {
            ExecResult arr_result = eval_expr(expr->as.slice.array, env);
            if (arr_result.is_throwing) return arr_result;
            Value arr = arr_result.value;
            
            if (arr.type != VAL_ARRAY) {
                fprintf(stderr, "Runtime Error: Can only slice arrays.\n");
                return EVAL_RESULT(val_nil());
            }
            
            int start = 0;
            int end = arr.as.array->count;
            
            if (expr->as.slice.start != NULL) {
                ExecResult start_result = eval_expr(expr->as.slice.start, env);
                if (start_result.is_throwing) return start_result;
                if (!IS_NUMBER(start_result.value)) return EVAL_RESULT(val_nil());
                start = (int)AS_NUMBER(start_result.value);
            }
            
            if (expr->as.slice.end != NULL) {
                ExecResult end_result = eval_expr(expr->as.slice.end, env);
                if (end_result.is_throwing) return end_result;
                if (!IS_NUMBER(end_result.value)) return EVAL_RESULT(val_nil());
                end = (int)AS_NUMBER(end_result.value);
            }
            
            return EVAL_RESULT(array_slice(&arr, start, end));
        }

        case EXPR_GET: {
            ExecResult obj_result = eval_expr(expr->as.get.object, env);
            if (obj_result.is_throwing) return obj_result;
            Value object = obj_result.value;
            
            if (!IS_INSTANCE(object)) {
                fprintf(stderr, "Runtime Error: Only instances have properties.\n");
                return EVAL_RESULT(val_nil());
            }
            
            Token prop = expr->as.get.property;
            char* prop_name = malloc(prop.length + 1);
            strncpy(prop_name, prop.start, prop.length);
            prop_name[prop.length] = '\0';
            
            Value result = instance_get_field(object.as.instance, prop_name);
            free(prop_name);
            return EVAL_RESULT(result);
        }

        case EXPR_SET: {
            ExecResult obj_result = eval_expr(expr->as.set.object, env);
            if (obj_result.is_throwing) return obj_result;
            Value object = obj_result.value;
            
            if (!IS_INSTANCE(object)) {
                fprintf(stderr, "Runtime Error: Only instances have properties.\n");
                return EVAL_RESULT(val_nil());
            }
            
            ExecResult val_result = eval_expr(expr->as.set.value, env);
            if (val_result.is_throwing) return val_result;
            Value value = val_result.value;
            
            Token prop = expr->as.set.property;
            char* prop_name = malloc(prop.length + 1);
            strncpy(prop_name, prop.start, prop.length);
            prop_name[prop.length] = '\0';
            
            instance_set_field(object.as.instance, prop_name, value);
            free(prop_name);
            return EVAL_RESULT(value);
        }

        case EXPR_BINARY:
            return eval_binary(&expr->as.binary, env);

        case EXPR_VARIABLE: {
            Value val;
            Token t = expr->as.variable.name;
            if (env_get(env, t.start, t.length, &val)) {
                return EVAL_RESULT(val);
            }
            fprintf(stderr, "Runtime Error: Undefined variable '%.*s'.\n", t.length, t.start);
            return EVAL_RESULT(val_nil());
        }

        case EXPR_CALL: {
            Token callee = expr->as.call.callee;
            
            // Check for method call pattern
            if (expr->as.call.arg_count > 0 && expr->as.call.args[0]->type == EXPR_GET) {
                Expr* get_expr = expr->as.call.args[0];
                ExecResult obj_result = eval_expr(get_expr->as.get.object, env);
                if (obj_result.is_throwing) return obj_result;
                Value object = obj_result.value;
                
                if (!IS_INSTANCE(object)) {
                    fprintf(stderr, "Runtime Error: Cannot call method on non-instance.\n");
                    return EVAL_RESULT(val_nil());
                }
                
                Token method_token = get_expr->as.get.property;
                char* method_name = malloc(method_token.length + 1);
                strncpy(method_name, method_token.start, method_token.length);
                method_name[method_token.length] = '\0';
                
                Method* method = class_find_method(object.as.instance->class_def, method_name, method_token.length);
                
                if (!method) {
                    fprintf(stderr, "Runtime Error: Undefined method '%s'.\n", method_name);
                    free(method_name);
                    return EVAL_RESULT(val_nil());
                }
                
                ProcStmt* method_stmt = (ProcStmt*)method->method_stmt;
                
                Env* method_env = env_create(env);
                env_define(method_env, "self", 4, object);
                
                int param_start = (method_stmt->param_count > 0 && 
                                  strncmp(method_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;
                
                for (int i = param_start; i < method_stmt->param_count; i++) {
                    if (i - param_start + 1 < expr->as.call.arg_count) {
                        ExecResult arg_result = eval_expr(expr->as.call.args[i - param_start + 1], env);
                        if (arg_result.is_throwing) {
                            free(method_name);
                            return arg_result;
                        }
                        env_define(method_env, method_stmt->params[i].start, 
                                 method_stmt->params[i].length, arg_result.value);
                    }
                }
                
                ExecResult res = interpret(method_stmt->body, method_env);
                free(method_name);
                if (res.is_throwing) return res;
                return EVAL_RESULT(res.value);
            }
            
            Value classVal;
            if (env_get(env, callee.start, callee.length, &classVal)) {
                if (classVal.type == VAL_NATIVE) {
                    Value args[255];
                    int count = expr->as.call.arg_count;
                    for (int i = 0; i < count; i++) {
                        ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
                        if (arg_result.is_throwing) return arg_result;
                        args[i] = arg_result.value;
                    }
                    return EVAL_RESULT(classVal.as.native(count, args));
                }
                
                if (classVal.type == VAL_CLASS) {
                    ClassValue* class_def = classVal.as.class_val;
                    InstanceValue* instance = instance_create(class_def);
                    Value inst_val = val_instance(instance);
                    
                    Method* init_method = class_find_method(class_def, "init", 4);
                    if (init_method) {
                        ProcStmt* init_stmt = (ProcStmt*)init_method->method_stmt;
                        
                        Env* method_env = env_create(env);
                        env_define(method_env, "self", 4, inst_val);
                        
                        int param_start = (init_stmt->param_count > 0 && 
                                          strncmp(init_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;
                        
                        for (int i = param_start; i < init_stmt->param_count; i++) {
                            if (i - param_start < expr->as.call.arg_count) {
                                ExecResult arg_result = eval_expr(expr->as.call.args[i - param_start], env);
                                if (arg_result.is_throwing) return arg_result;
                                env_define(method_env, init_stmt->params[i].start, 
                                         init_stmt->params[i].length, arg_result.value);
                            }
                        }
                        
                        ExecResult init_res = interpret(init_stmt->body, method_env);
                        if (init_res.is_throwing) return init_res;
                    }
                    
                    return EVAL_RESULT(inst_val);
                }
            }

            ProcStmt* func = find_function(callee.start, callee.length);
            if (func) {
                if (expr->as.call.arg_count != func->param_count) {
                     fprintf(stderr, "Runtime Error: Arity mismatch.\n");
                     return EVAL_RESULT(val_nil());
                }

                Env* scope = env_create(env); 
                for (int i = 0; i < func->param_count; i++) {
                    ExecResult arg_result = eval_expr(expr->as.call.args[i], env);
                    if (arg_result.is_throwing) return arg_result;
                    Token paramName = func->params[i];
                    env_define(scope, paramName.start, paramName.length, arg_result.value);
                }

                ExecResult res = interpret(func->body, scope);
                // CRITICAL: Propagate exceptions from function calls!
                if (res.is_throwing) return res;
                return EVAL_RESULT(res.value);
            }

            fprintf(stderr, "Runtime Error: Undefined procedure '%.*s'.\n", callee.length, callee.start);
            return EVAL_RESULT(val_nil());
        }

        default:
            return EVAL_RESULT(val_nil());
    }
}

ExecResult interpret(Stmt* stmt, Env* env) {
    if (!stmt) return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };

    switch (stmt->type) {
        case STMT_PRINT: {
            ExecResult result = eval_expr(stmt->as.print.expression, env);
            if (result.is_throwing) return result;
            print_value(result.value);
            printf("\n");
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_LET: {
            Value val = val_nil();
            if (stmt->as.let.initializer != NULL) {
                ExecResult result = eval_expr(stmt->as.let.initializer, env);
                if (result.is_throwing) return result;
                val = result.value;
            }
            Token t = stmt->as.let.name;
            env_define(env, t.start, t.length, val);
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_EXPRESSION: {
            ExecResult result = eval_expr(stmt->as.expression, env);
            if (result.is_throwing) return result;
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_BLOCK: {
            Stmt* current = stmt->as.block.statements;
            while (current != NULL) {
                ExecResult res = interpret(current, env);
                if (res.is_returning || res.is_breaking || res.is_continuing || res.is_throwing) {
                    return res;
                }
                current = current->next;
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_IF: {
            ExecResult cond_result = eval_expr(stmt->as.if_stmt.condition, env);
            if (cond_result.is_throwing) return cond_result;
            
            if (is_truthy(cond_result.value)) {
                return interpret(stmt->as.if_stmt.then_branch, env);
            } else if (stmt->as.if_stmt.else_branch != NULL) {
                return interpret(stmt->as.if_stmt.else_branch, env);
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_WHILE: {
            while (1) {
                ExecResult cond_result = eval_expr(stmt->as.while_stmt.condition, env);
                if (cond_result.is_throwing) return cond_result;
                if (!is_truthy(cond_result.value)) break;
                
                ExecResult res = interpret(stmt->as.while_stmt.body, env);
                if (res.is_returning || res.is_throwing) return res;
                if (res.is_breaking) break;
                if (res.is_continuing) continue;
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_FOR: {
            ExecResult iter_result = eval_expr(stmt->as.for_stmt.iterable, env);
            if (iter_result.is_throwing) return iter_result;
            Value iterable = iter_result.value;
            
            if (iterable.type != VAL_ARRAY) {
                fprintf(stderr, "Runtime Error: for loop iterable must be an array.\n");
                return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
            }

            Env* loop_env = env_create(env);
            Token var = stmt->as.for_stmt.variable;

            ArrayValue* arr = iterable.as.array;
            for (int i = 0; i < arr->count; i++) {
                env_define(loop_env, var.start, var.length, arr->elements[i]);

                ExecResult res = interpret(stmt->as.for_stmt.body, loop_env);
                if (res.is_returning || res.is_throwing) return res;
                if (res.is_breaking) break;
                if (res.is_continuing) continue;
            }

            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_BREAK:
            return (ExecResult){ val_nil(), 0, 1, 0, 0, val_nil(), 0, NULL };

        case STMT_CONTINUE:
            return (ExecResult){ val_nil(), 0, 0, 1, 0, val_nil(), 0, NULL };

        // PHASE 7: Modified STMT_PROC to detect generators
        case STMT_PROC: {
            Token name = stmt->as.proc.name;
            int is_generator = contains_yield(stmt->as.proc.body);
            
            Value func_val;
            if (is_generator) {
                func_val = val_generator(stmt->as.proc.body, stmt->as.proc.params, 
                                        stmt->as.proc.param_count, env);
            } else {
                define_function(&stmt->as.proc);
                return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
            }
            
            env_define(env, name.start, name.length, func_val);
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_CLASS: {
            ClassValue* parent = NULL;
            if (stmt->as.class_stmt.has_parent) {
                Value parent_val;
                Token parent_name = stmt->as.class_stmt.parent;
                if (env_get(env, parent_name.start, parent_name.length, &parent_val)) {
                    if (parent_val.type == VAL_CLASS) {
                        parent = parent_val.as.class_val;
                    } else {
                        fprintf(stderr, "Runtime Error: Parent must be a class.\n");
                        return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
                    }
                } else {
                    fprintf(stderr, "Runtime Error: Undefined parent class.\n");
                    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
                }
            }
            
            Token name = stmt->as.class_stmt.name;
            ClassValue* class_val = class_create(name.start, name.length, parent);
            
            Stmt* method = stmt->as.class_stmt.methods;
            while (method != NULL) {
                if (method->type == STMT_PROC) {
                    ProcStmt* proc = &method->as.proc;
                    class_add_method(class_val, proc->name.start, proc->name.length, (void*)proc);
                }
                method = method->next;
            }
            
            Value class_value = val_class(class_val);
            env_define(env, name.start, name.length, class_value);
            
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_RETURN: {
            Value val = val_nil();
            if (stmt->as.ret.value) {
                ExecResult result = eval_expr(stmt->as.ret.value, env);
                if (result.is_throwing) return result;
                val = result.value;
            }
            return (ExecResult){ val, 1, 0, 0, 0, val_nil(), 0, NULL };
        }

        case STMT_TRY: {
            ExecResult try_result = interpret(stmt->as.try_stmt.try_block, env);
            
            if (try_result.is_throwing) {
                for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                    CatchClause* catch_clause = stmt->as.try_stmt.catches[i];
                    Env* catch_env = env_create(env);
                    Token var = catch_clause->exception_var;
                    
                    Value exc_msg;
                    if (IS_EXCEPTION(try_result.exception_value)) {
                        exc_msg = val_string(try_result.exception_value.as.exception->message);
                    } else {
                        exc_msg = try_result.exception_value;
                    }
                    env_define(catch_env, var.start, var.length, exc_msg);
                    
                    ExecResult catch_result = interpret(catch_clause->body, catch_env);
                    if (!catch_result.is_throwing) {
                        try_result = catch_result;
                        break;
                    }
                    try_result = catch_result;
                }
            }
            
            if (stmt->as.try_stmt.finally_block != NULL) {
                interpret(stmt->as.try_stmt.finally_block, env);
            }
            
            return try_result;
        }

        case STMT_RAISE: {
            ExecResult exc_result = eval_expr(stmt->as.raise.exception, env);
            if (exc_result.is_throwing) return exc_result;
            
            Value exc_val = exc_result.value;
            if (IS_STRING(exc_val)) {
                exc_val = val_exception(AS_STRING(exc_val));
            } else if (!IS_EXCEPTION(exc_val)) {
                exc_val = val_exception("Unknown error");
            }
            return (ExecResult){ val_nil(), 0, 0, 0, 1, exc_val, 0, NULL };
        }

        // PHASE 7: Yield statement execution
        case STMT_YIELD: {
            Value yield_value = val_nil();
            if (stmt->as.yield_stmt.value != NULL) {
                ExecResult result = eval_expr(stmt->as.yield_stmt.value, env);
                if (result.is_throwing) return result;
                yield_value = result.value;
            }
            
            ExecResult result = {0};
            result.value = yield_value;
            result.is_yielding = 1;
            result.next_stmt = stmt->next;
            return result;
        }

        case STMT_MATCH:
        case STMT_DEFER:
            return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
    }
    return (ExecResult){ val_nil(), 0, 0, 0, 0, val_nil(), 0, NULL };
}