#include "vm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "module.h"
#include "repl.h"
#include "sage_thread.h"
#include "gc.h"

extern Environment* g_gc_root_env;

#define VM_STACK_MAX 1024

typedef struct {
    BytecodeChunk* chunk;
    Env* env;
    Value stack[VM_STACK_MAX];
    int stack_count;
} ActiveVm;

static ActiveVm* g_active_vm = NULL;

static ExecResult vm_normal(Value value) {
    ExecResult result = {0};
    result.value = value;
    return result;
}

static int vm_is_truthy(Value value) {
    if (IS_NIL(value)) return 0;
    if (IS_BOOL(value)) return AS_BOOL(value);
    return 1;
}

void vm_mark_roots(void) {
    if (g_active_vm == NULL) return;

    for (int i = 0; i < g_active_vm->chunk->constant_count; i++) {
        gc_mark_value(g_active_vm->chunk->constants[i]);
    }

    for (int i = 0; i < g_active_vm->stack_count; i++) {
        gc_mark_value(g_active_vm->stack[i]);
    }
}

static ExecResult vm_error(const char* message) {
    fprintf(stderr, "Runtime Error: %s\n", message);
    ExecResult result = {0};
    result.value = val_nil();
    result.is_throwing = 1;
    result.exception_value = val_exception(message);
    return result;
}

static int vm_push(ActiveVm* vm, Value value) {
    if (vm->stack_count >= VM_STACK_MAX) {
        return 0;
    }
    vm->stack[vm->stack_count++] = value;
    return 1;
}

static Value vm_pop(ActiveVm* vm) {
    if (vm->stack_count <= 0) {
        return val_nil();
    }
    return vm->stack[--vm->stack_count];
}

static Value vm_peek(ActiveVm* vm, int distance) {
    if (distance < 0 || vm->stack_count - 1 - distance < 0) {
        return val_nil();
    }
    return vm->stack[vm->stack_count - 1 - distance];
}

static uint16_t read_u16(BytecodeChunk* chunk, int* ip) {
    uint16_t high = chunk->code[(*ip)++];
    uint16_t low = chunk->code[(*ip)++];
    return (uint16_t)((high << 8) | low);
}

static uint8_t read_u8(BytecodeChunk* chunk, int* ip) {
    return chunk->code[(*ip)++];
}

static ExecResult call_function_value(Value callee, int arg_count, Value* args, Env* env) {
    if (callee.type == VAL_NATIVE) {
        return vm_normal(callee.as.native(arg_count, args));
    }

    if (callee.type == VAL_FUNCTION) {
        ProcStmt* func = (ProcStmt*)AS_FUNCTION(callee);
        if (arg_count != func->param_count) {
            return vm_error("Arity mismatch.");
        }

        if (callee.as.function->is_async) {
#if SAGE_PLATFORM_PICO
            return vm_error("async/await not supported on RP2040.");
#else
            return vm_error("async Sage functions are not executed by the bytecode VM yet.");
#endif
        }

        Env* scope = env_create(callee.as.function->closure);
        for (int i = 0; i < func->param_count; i++) {
            Token param = func->params[i];
            env_define(scope, param.start, param.length, args[i]);
        }

        ExecResult result = interpret(func->body, scope);
        if (result.is_throwing) return result;
        return vm_normal(result.value);
    }

    if (callee.type == VAL_GENERATOR) {
        GeneratorValue* template = callee.as.generator;
        if (arg_count != template->param_count) {
            return vm_error("Arity mismatch.");
        }

        Env* closure = env_create(template->closure);
        if (template->param_count > 0 && template->params != NULL) {
            Token* params = (Token*)template->params;
            for (int i = 0; i < template->param_count; i++) {
                env_define(closure, params[i].start, params[i].length, args[i]);
            }
        }

        return vm_normal(val_generator(template->body, template->params,
                                       template->param_count, closure));
    }

    if (callee.type == VAL_CLASS) {
        ClassValue* class_def = callee.as.class_val;
        InstanceValue* instance = instance_create(class_def);
        Value instance_value = val_instance(instance);

        Method* init_method = class_find_method(class_def, "init", 4);
        if (init_method != NULL) {
            ProcStmt* init_stmt = (ProcStmt*)init_method->method_stmt;
            Env* method_env = env_create(env);
            env_define(method_env, "self", 4, instance_value);

            int param_start = (init_stmt->param_count > 0 &&
                              strncmp(init_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;

            for (int i = param_start; i < init_stmt->param_count; i++) {
                if (i - param_start < arg_count) {
                    env_define(method_env, init_stmt->params[i].start,
                               init_stmt->params[i].length, args[i - param_start]);
                }
            }

            ExecResult init_result = interpret(init_stmt->body, method_env);
            if (init_result.is_throwing) return init_result;
        }

        return vm_normal(instance_value);
    }

    return vm_error("Value is not callable.");
}

static ExecResult call_method_value(Value object, const char* method_name, int arg_count, Value* args, Env* env) {
    if (IS_INSTANCE(object)) {
        Method* method = class_find_method(object.as.instance->class_def, method_name, (int)strlen(method_name));
        if (method == NULL) {
            return vm_error("Undefined method.");
        }

        ProcStmt* method_stmt = (ProcStmt*)method->method_stmt;
        Env* method_env = env_create(env);
        env_define(method_env, "self", 4, object);

        int param_start = (method_stmt->param_count > 0 &&
                          strncmp(method_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;
        for (int i = param_start; i < method_stmt->param_count; i++) {
            if (i - param_start < arg_count) {
                env_define(method_env, method_stmt->params[i].start,
                           method_stmt->params[i].length, args[i - param_start]);
            }
        }

        ExecResult result = interpret(method_stmt->body, method_env);
        if (result.is_throwing) return result;
        return vm_normal(result.value);
    }

    if (IS_MODULE(object)) {
        int found = 0;
        Value attr = module_get_attr(AS_MODULE(object), method_name, (int)strlen(method_name), &found);
        if (!found) {
            return vm_error("Module attribute is not defined.");
        }
        return call_function_value(attr, arg_count, args, env);
    }

    return vm_error("Only instances and modules have methods.");
}

ExecResult vm_execute_chunk(BytecodeChunk* chunk, Env* env) {
    ActiveVm vm;
    ExecResult result = vm_normal(val_nil());
    int ip = 0;
    Env* previous_gc_root = g_gc_root_env;
    ActiveVm* previous_vm = g_active_vm;

    memset(&vm, 0, sizeof(vm));
    vm.chunk = chunk;
    vm.env = env;

    g_gc_root_env = env;
    g_active_vm = &vm;

    while (ip < chunk->code_count) {
        BytecodeOp op = (BytecodeOp)chunk->code[ip++];

        switch (op) {
            case BC_OP_CONSTANT: {
                uint16_t index = read_u16(chunk, &ip);
                if (!vm_push(&vm, chunk->constants[index])) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_NIL:
                if (!vm_push(&vm, val_nil())) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            case BC_OP_TRUE:
                if (!vm_push(&vm, val_bool(1))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            case BC_OP_FALSE:
                if (!vm_push(&vm, val_bool(0))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            case BC_OP_POP:
                (void)vm_pop(&vm);
                break;
            case BC_OP_GET_GLOBAL: {
                uint16_t name_index = read_u16(chunk, &ip);
                Value name = chunk->constants[name_index];
                Value resolved = val_nil();
                if (!env_get(env, AS_STRING(name), (int)strlen(AS_STRING(name)), &resolved)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                if (!vm_push(&vm, resolved)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_DEFINE_GLOBAL: {
                uint16_t name_index = read_u16(chunk, &ip);
                Value name = chunk->constants[name_index];
                Value value = vm_pop(&vm);
                env_define(env, AS_STRING(name), (int)strlen(AS_STRING(name)), value);
                break;
            }
            case BC_OP_SET_GLOBAL: {
                uint16_t name_index = read_u16(chunk, &ip);
                Value name = chunk->constants[name_index];
                Value value = vm_peek(&vm, 0);
                if (!env_assign(env, AS_STRING(name), (int)strlen(AS_STRING(name)), value)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                break;
            }
            case BC_OP_GET_PROPERTY: {
                uint16_t name_index = read_u16(chunk, &ip);
                Value object = vm_pop(&vm);
                const char* property = AS_STRING(chunk->constants[name_index]);

                if (IS_INSTANCE(object)) {
                    Value field = instance_get_field(object.as.instance, property);
                    if (!vm_push(&vm, field)) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else if (IS_MODULE(object)) {
                    int found = 0;
                    Value attr = module_get_attr(AS_MODULE(object), property, (int)strlen(property), &found);
                    if (!found) {
                        result = vm_error("Module attribute is not defined.");
                        goto done;
                    }
                    if (!vm_push(&vm, attr)) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else {
                    result = vm_error("Only instances and modules have properties.");
                    goto done;
                }
                break;
            }
            case BC_OP_SET_PROPERTY: {
                uint16_t name_index = read_u16(chunk, &ip);
                Value value = vm_pop(&vm);
                Value object = vm_pop(&vm);
                const char* property = AS_STRING(chunk->constants[name_index]);

                if (!IS_INSTANCE(object)) {
                    result = vm_error("Only instances have properties.");
                    goto done;
                }

                instance_set_field(object.as.instance, property, value);
                if (!vm_push(&vm, value)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_GET_INDEX: {
                Value index = vm_pop(&vm);
                Value object = vm_pop(&vm);

                if (object.type == VAL_ARRAY && IS_NUMBER(index)) {
                    if (!vm_push(&vm, array_get(&object, (int)AS_NUMBER(index)))) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else if (object.type == VAL_TUPLE && IS_NUMBER(index)) {
                    if (!vm_push(&vm, tuple_get(&object, (int)AS_NUMBER(index)))) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else if (object.type == VAL_STRING && IS_NUMBER(index)) {
                    int string_index = (int)AS_NUMBER(index);
                    char* string = AS_STRING(object);
                    int string_length = (int)strlen(string);
                    if (string_index < 0) string_index += string_length;
                    if (string_index < 0 || string_index >= string_length) {
                        result = vm_error("String index out of bounds.");
                        goto done;
                    }
                    char* character = SAGE_ALLOC(2);
                    character[0] = string[string_index];
                    character[1] = '\0';
                    if (!vm_push(&vm, val_string_take(character))) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else if (object.type == VAL_DICT && IS_STRING(index)) {
                    if (!vm_push(&vm, dict_get(&object, AS_STRING(index)))) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else {
                    result = vm_error("Invalid indexing operation.");
                    goto done;
                }
                break;
            }
            case BC_OP_SET_INDEX: {
                Value value = vm_pop(&vm);
                Value index = vm_pop(&vm);
                Value object = vm_pop(&vm);

                if (object.type == VAL_ARRAY && IS_NUMBER(index)) {
                    array_set(&object, (int)AS_NUMBER(index), value);
                } else if (object.type == VAL_DICT && IS_STRING(index)) {
                    dict_set(&object, AS_STRING(index), value);
                } else {
                    result = vm_error("Invalid index assignment.");
                    goto done;
                }

                if (!vm_push(&vm, value)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_SLICE: {
                Value end = vm_pop(&vm);
                Value start = vm_pop(&vm);
                Value object = vm_pop(&vm);

                int start_index = 0;
                int end_index = 0;

                if (IS_ARRAY(object)) {
                    end_index = object.as.array->count;
                } else if (IS_STRING(object)) {
                    end_index = (int)strlen(AS_STRING(object));
                } else {
                    result = vm_error("Can only slice arrays or strings.");
                    goto done;
                }

                if (!IS_NIL(start)) {
                    if (!IS_NUMBER(start)) {
                        result = vm_error("Slice start must be a number.");
                        goto done;
                    }
                    start_index = (int)AS_NUMBER(start);
                }
                if (!IS_NIL(end)) {
                    if (!IS_NUMBER(end)) {
                        result = vm_error("Slice end must be a number.");
                        goto done;
                    }
                    end_index = (int)AS_NUMBER(end);
                }

                if (IS_ARRAY(object)) {
                    if (!vm_push(&vm, array_slice(&object, start_index, end_index))) {
                        result = vm_error("VM stack overflow.");
                        goto done;
                    }
                } else {
                    char* string = AS_STRING(object);
                    int string_length = (int)strlen(string);
                    if (start_index < 0) start_index += string_length;
                    if (end_index < 0) end_index += string_length;
                    if (start_index < 0) start_index = 0;
                    if (end_index > string_length) end_index = string_length;
                    if (start_index >= end_index) {
                        if (!vm_push(&vm, val_string(""))) {
                            result = vm_error("VM stack overflow.");
                            goto done;
                        }
                    } else {
                        int length = end_index - start_index;
                        char* slice = SAGE_ALLOC((size_t)length + 1);
                        memcpy(slice, string + start_index, (size_t)length);
                        slice[length] = '\0';
                        if (!vm_push(&vm, val_string_take(slice))) {
                            result = vm_error("VM stack overflow.");
                            goto done;
                        }
                    }
                }
                break;
            }
            case BC_OP_ADD:
            case BC_OP_SUB:
            case BC_OP_MUL:
            case BC_OP_DIV:
            case BC_OP_MOD:
            case BC_OP_EQUAL:
            case BC_OP_NOT_EQUAL:
            case BC_OP_GREATER:
            case BC_OP_GREATER_EQUAL:
            case BC_OP_LESS:
            case BC_OP_LESS_EQUAL:
            case BC_OP_BIT_AND:
            case BC_OP_BIT_OR:
            case BC_OP_BIT_XOR:
            case BC_OP_SHIFT_LEFT:
            case BC_OP_SHIFT_RIGHT: {
                Value right = vm_pop(&vm);
                Value left = vm_pop(&vm);
                Value out = val_nil();

                if (op == BC_OP_EQUAL || op == BC_OP_NOT_EQUAL) {
                    int equal = values_equal(left, right);
                    out = val_bool(op == BC_OP_EQUAL ? equal : !equal);
                } else if (op == BC_OP_GREATER || op == BC_OP_GREATER_EQUAL ||
                           op == BC_OP_LESS || op == BC_OP_LESS_EQUAL) {
                    if (IS_NUMBER(left) && IS_NUMBER(right)) {
                        double l = AS_NUMBER(left), r = AS_NUMBER(right);
                        if (op == BC_OP_GREATER) out = val_bool(l > r);
                        else if (op == BC_OP_GREATER_EQUAL) out = val_bool(l >= r);
                        else if (op == BC_OP_LESS) out = val_bool(l < r);
                        else out = val_bool(l <= r);
                    } else if (IS_STRING(left) && IS_STRING(right)) {
                        int cmp = strcmp(AS_STRING(left), AS_STRING(right));
                        if (op == BC_OP_GREATER) out = val_bool(cmp > 0);
                        else if (op == BC_OP_GREATER_EQUAL) out = val_bool(cmp >= 0);
                        else if (op == BC_OP_LESS) out = val_bool(cmp < 0);
                        else out = val_bool(cmp <= 0);
                    } else {
                        result = vm_error("Operands must be numbers or strings.");
                        goto done;
                    }
                } else if (op == BC_OP_ADD && IS_STRING(left) && IS_STRING(right)) {
                    size_t len1 = strlen(AS_STRING(left));
                    size_t len2 = strlen(AS_STRING(right));
                    char* joined = SAGE_ALLOC(len1 + len2 + 1);
                    memcpy(joined, AS_STRING(left), len1);
                    memcpy(joined + len1, AS_STRING(right), len2 + 1);
                    out = val_string_take(joined);
                } else if (IS_NUMBER(left) && IS_NUMBER(right)) {
                    long long l = (long long)AS_NUMBER(left);
                    long long r = (long long)AS_NUMBER(right);
                    switch (op) {
                        case BC_OP_ADD: out = val_number(AS_NUMBER(left) + AS_NUMBER(right)); break;
                        case BC_OP_SUB: out = val_number(AS_NUMBER(left) - AS_NUMBER(right)); break;
                        case BC_OP_MUL: out = val_number(AS_NUMBER(left) * AS_NUMBER(right)); break;
                        case BC_OP_DIV:
                            if (AS_NUMBER(right) == 0) { result = vm_error("Division by zero."); goto done; }
                            out = val_number(AS_NUMBER(left) / AS_NUMBER(right));
                            break;
                        case BC_OP_MOD:
                            if (r == 0) { result = vm_error("Modulo by zero."); goto done; }
                            out = val_number((double)(l % r));
                            break;
                        case BC_OP_BIT_AND: out = val_number((double)(l & r)); break;
                        case BC_OP_BIT_OR: out = val_number((double)(l | r)); break;
                        case BC_OP_BIT_XOR: out = val_number((double)(l ^ r)); break;
                        case BC_OP_SHIFT_LEFT: out = val_number((double)(l << r)); break;
                        case BC_OP_SHIFT_RIGHT: out = val_number((double)(l >> r)); break;
                        default: break;
                    }
                } else {
                    result = vm_error("Operands must be numbers or strings.");
                    goto done;
                }

                if (!vm_push(&vm, out)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_NEGATE: {
                Value value = vm_pop(&vm);
                if (!IS_NUMBER(value)) {
                    result = vm_error("Unary '-' requires a number.");
                    goto done;
                }
                if (!vm_push(&vm, val_number(-AS_NUMBER(value)))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_BIT_NOT: {
                Value value = vm_pop(&vm);
                if (!IS_NUMBER(value)) {
                    result = vm_error("Bitwise NOT operand must be a number.");
                    goto done;
                }
                if (!vm_push(&vm, val_number((double)(~(long long)AS_NUMBER(value))))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_NOT: {
                Value value = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(!vm_is_truthy(value)))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_TRUTHY: {
                Value value = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(vm_is_truthy(value)))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_JUMP:
                ip = (int)read_u16(chunk, &ip);
                break;
            case BC_OP_JUMP_IF_FALSE: {
                uint16_t target = read_u16(chunk, &ip);
                if (!vm_is_truthy(vm_peek(&vm, 0))) {
                    ip = (int)target;
                }
                break;
            }
            case BC_OP_CALL: {
                int arg_count = (int)read_u8(chunk, &ip);
                Value args[255];
                for (int i = arg_count - 1; i >= 0; i--) {
                    args[i] = vm_pop(&vm);
                }
                Value callee = vm_pop(&vm);
                ExecResult call_result = call_function_value(callee, arg_count, args, env);
                if (call_result.is_throwing) {
                    result = call_result;
                    goto done;
                }
                if (!vm_push(&vm, call_result.value)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_CALL_METHOD: {
                uint16_t name_index = read_u16(chunk, &ip);
                int arg_count = (int)read_u8(chunk, &ip);
                Value args[255];
                for (int i = arg_count - 1; i >= 0; i--) {
                    args[i] = vm_pop(&vm);
                }
                Value object = vm_pop(&vm);
                ExecResult call_result = call_method_value(object, AS_STRING(chunk->constants[name_index]), arg_count, args, env);
                if (call_result.is_throwing) {
                    result = call_result;
                    goto done;
                }
                if (!vm_push(&vm, call_result.value)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_ARRAY: {
                uint16_t count = read_u16(chunk, &ip);
                Value array = val_array();
                Value* values = SAGE_ALLOC(sizeof(Value) * (size_t)count);
                for (int i = (int)count - 1; i >= 0; i--) {
                    values[i] = vm_pop(&vm);
                }
                for (int i = 0; i < (int)count; i++) {
                    array_push(&array, values[i]);
                }
                free(values);
                if (!vm_push(&vm, array)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_TUPLE: {
                uint16_t count = read_u16(chunk, &ip);
                Value* values = SAGE_ALLOC(sizeof(Value) * (size_t)count);
                for (int i = (int)count - 1; i >= 0; i--) {
                    values[i] = vm_pop(&vm);
                }
                Value tuple = val_tuple(values, (int)count);
                free(values);
                if (!vm_push(&vm, tuple)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_DICT: {
                uint16_t count = read_u16(chunk, &ip);
                Value dictionary = val_dict();
                Value* values = SAGE_ALLOC(sizeof(Value) * (size_t)count * 2);
                for (int i = ((int)count * 2) - 1; i >= 0; i--) {
                    values[i] = vm_pop(&vm);
                }
                for (int i = 0; i < (int)count; i++) {
                    Value key = values[i * 2];
                    Value value = values[i * 2 + 1];
                    if (!IS_STRING(key)) {
                        result = vm_error("Dictionary keys must be strings in bytecode mode.");
                        free(values);
                        goto done;
                    }
                    dict_set(&dictionary, AS_STRING(key), value);
                }
                free(values);
                if (!vm_push(&vm, dictionary)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_PRINT: {
                Value value = vm_pop(&vm);
                print_value(value);
                printf("\n");
                break;
            }
            case BC_OP_EXEC_AST_STMT: {
                uint16_t stmt_index = read_u16(chunk, &ip);
                ExecResult ast_result = interpret(chunk->ast_stmts[stmt_index], env);
                if (ast_result.is_throwing) {
                    result = ast_result;
                    goto done;
                }
                if (!vm_push(&vm, ast_result.value)) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_RETURN:
                result = vm_normal(vm.stack_count > 0 ? vm_pop(&vm) : val_nil());
                goto done;
        }
    }

done:
    g_active_vm = previous_vm;
    g_gc_root_env = previous_gc_root;
    return result;
}
