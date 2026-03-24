#include "vm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "module.h"
#include "repl.h"
#include "sage_thread.h"
#include "gc.h"
#include "gpu_api.h"

extern Environment* g_gc_root_env;

#define VM_STACK_MAX 1024

typedef struct ActiveVm {
    BytecodeChunk* chunk;
    Env* current_env;
    Value stack[VM_STACK_MAX];
    int stack_count;
    struct ActiveVm* parent;
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

static void vm_mark_chunk_constants(BytecodeChunk* chunk) {
    if (chunk == NULL) return;

    for (int i = 0; i < chunk->constant_count; i++) {
        gc_mark_value(chunk->constants[i]);
    }
}

static void vm_mark_program_constants(BytecodeProgram* program) {
    if (program == NULL) return;

    for (int i = 0; i < program->function_count; i++) {
        vm_mark_chunk_constants(&program->functions[i].chunk);
    }

    for (int i = 0; i < program->chunk_count; i++) {
        vm_mark_chunk_constants(&program->chunks[i]);
    }
}

void vm_mark_roots(void) {
    for (ActiveVm* active = g_active_vm; active != NULL; active = active->parent) {
        vm_mark_chunk_constants(active->chunk);
        vm_mark_program_constants(active->chunk != NULL ? active->chunk->program : NULL);
        gc_mark_env(active->current_env);

        for (int i = 0; i < active->stack_count; i++) {
            gc_mark_value(active->stack[i]);
        }
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

#define VM_CHECK_CONST(chunk, idx) \
    do { if ((int)(idx) < 0 || (int)(idx) >= (chunk)->constant_count) { \
        result = vm_error("VM constant pool index out of bounds."); goto done; \
    } } while(0)

#define VM_CHECK_AST(chunk, idx) \
    do { if ((int)(idx) < 0 || (int)(idx) >= (chunk)->ast_stmt_count) { \
        result = vm_error("VM AST statement index out of bounds."); goto done; \
    } } while(0)

static uint16_t read_u16(BytecodeChunk* chunk, int* ip) {
    if (*ip + 2 > chunk->code_count) {
        fprintf(stderr, "VM Error: bytecode read_u16 out of bounds (ip=%d, size=%d)\n", *ip, chunk->code_count);
        *ip = chunk->code_count;  // halt
        return 0;
    }
    uint16_t high = chunk->code[(*ip)++];
    uint16_t low = chunk->code[(*ip)++];
    return (uint16_t)((high << 8) | low);
}

static uint8_t read_u8(BytecodeChunk* chunk, int* ip) {
    if (*ip >= chunk->code_count) {
        fprintf(stderr, "VM Error: bytecode read_u8 out of bounds (ip=%d, size=%d)\n", *ip, chunk->code_count);
        return 0;
    }
    return chunk->code[(*ip)++];
}

static ExecResult call_function_value(Value callee, int arg_count, Value* args, Env* env) {
    if (callee.type == VAL_NATIVE) {
        return vm_normal(callee.as.native(arg_count, args));
    }

    if (callee.type == VAL_FUNCTION) {
        if (callee.as.function->is_async) {
#if SAGE_PLATFORM_PICO
            return vm_error("async/await not supported on RP2040.");
#else
            return vm_error("async Sage functions are not executed by the bytecode VM yet.");
#endif
        }

        if (callee.as.function->is_vm) {
            BytecodeFunction* function = callee.as.function->vm_function;
            if (function == NULL) {
                return vm_error("Invalid VM function.");
            }
            if (arg_count != function->param_count) {
                return vm_error("Arity mismatch.");
            }

            Env* scope = env_create(callee.as.function->closure);
            for (int i = 0; i < function->param_count; i++) {
                env_define(scope, function->params[i], (int)strlen(function->params[i]), args[i]);
            }

            return vm_execute_chunk(&function->chunk, scope);
        }

        ProcStmt* func = (ProcStmt*)AS_FUNCTION(callee);
        if (arg_count != func->param_count) {
            return vm_error("Arity mismatch.");
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
    vm.current_env = env;
    vm.parent = previous_vm;

    g_gc_root_env = env;
    g_active_vm = &vm;

    while (ip < chunk->code_count) {
        BytecodeOp op = (BytecodeOp)chunk->code[ip++];

        switch (op) {
            case BC_OP_CONSTANT: {
                uint16_t index = read_u16(chunk, &ip);
                VM_CHECK_CONST(chunk, index);
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
                VM_CHECK_CONST(chunk, name_index);
                Value name = chunk->constants[name_index];
                Value resolved = val_nil();
                if (!env_get(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), &resolved)) {
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
                VM_CHECK_CONST(chunk, name_index);
                Value name = chunk->constants[name_index];
                Value value = vm_pop(&vm);
                env_define(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), value);
                break;
            }
            case BC_OP_SET_GLOBAL: {
                uint16_t name_index = read_u16(chunk, &ip);
                VM_CHECK_CONST(chunk, name_index);
                Value name = chunk->constants[name_index];
                Value value = vm_peek(&vm, 0);
                if (!env_assign(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), value)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                break;
            }
            case BC_OP_DEFINE_FUNCTION: {
                uint16_t name_index = read_u16(chunk, &ip);
                uint16_t function_index = read_u16(chunk, &ip);
                VM_CHECK_CONST(chunk, name_index);

                if (chunk->program == NULL || function_index >= chunk->program->function_count) {
                    result = vm_error("Invalid compiled VM function reference.");
                    goto done;
                }

                Value name = chunk->constants[name_index];
                Value function = val_bytecode_function(&chunk->program->functions[function_index], vm.current_env);
                env_define(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), function);
                break;
            }
            case BC_OP_GET_PROPERTY: {
                uint16_t name_index = read_u16(chunk, &ip);
                VM_CHECK_CONST(chunk, name_index);
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
                VM_CHECK_CONST(chunk, name_index);
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
                            if (AS_NUMBER(right) == 0) {
                                out = val_nil();
                            } else {
                                out = val_number(AS_NUMBER(left) / AS_NUMBER(right));
                            }
                            break;
                        case BC_OP_MOD:
                            if ((int)AS_NUMBER(right) == 0) {
                                out = val_nil();
                            } else {
                                out = val_number((double)((int)AS_NUMBER(left) % (int)AS_NUMBER(right)));
                            }
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
                ExecResult call_result = call_function_value(callee, arg_count, args, vm.current_env);
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
                VM_CHECK_CONST(chunk, name_index);
                int arg_count = (int)read_u8(chunk, &ip);
                Value args[255];
                for (int i = arg_count - 1; i >= 0; i--) {
                    args[i] = vm_pop(&vm);
                }
                Value object = vm_pop(&vm);
                ExecResult call_result = call_method_value(object, AS_STRING(chunk->constants[name_index]), arg_count, args, vm.current_env);
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
            case BC_OP_PUSH_ENV:
                vm.current_env = env_create(vm.current_env);
                break;
            case BC_OP_POP_ENV:
                if (vm.current_env == NULL || vm.current_env->parent == NULL) {
                    result = vm_error("Cannot pop the root VM scope.");
                    goto done;
                }
                vm.current_env = vm.current_env->parent;
                break;
            case BC_OP_DUP: {
                uint8_t distance = read_u8(chunk, &ip);
                if ((int)distance >= vm.stack_count) {
                    result = vm_error("Invalid VM stack duplicate.");
                    goto done;
                }
                if (!vm_push(&vm, vm_peek(&vm, (int)distance))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_ARRAY_LEN: {
                Value value = vm_pop(&vm);
                if (!IS_ARRAY(value)) {
                    result = vm_error("for loop iterable must be an array.");
                    goto done;
                }
                if (!vm_push(&vm, val_number((double)value.as.array->count))) {
                    result = vm_error("VM stack overflow.");
                    goto done;
                }
                break;
            }
            case BC_OP_EXEC_AST_STMT: {
                uint16_t stmt_index = read_u16(chunk, &ip);
                VM_CHECK_AST(chunk, stmt_index);
                ExecResult ast_result = interpret(chunk->ast_stmts[stmt_index], vm.current_env);
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
            // ================================================================
            // GPU hot-path opcodes — bypass interpreter for frame-loop perf
            // ================================================================
            case BC_OP_GPU_POLL_EVENTS:
                sgpu_poll_events();
                break;
            case BC_OP_GPU_WINDOW_SHOULD_CLOSE:
                if (!vm_push(&vm, val_bool(sgpu_window_should_close()))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            case BC_OP_GPU_GET_TIME:
                if (!vm_push(&vm, val_number(sgpu_get_time()))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            case BC_OP_GPU_KEY_PRESSED: {
                Value key = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(sgpu_key_pressed((int)AS_NUMBER(key))))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_KEY_DOWN: {
                Value key = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(sgpu_key_down((int)AS_NUMBER(key))))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_MOUSE_POS: {
                double mx, my;
                sgpu_mouse_pos(&mx, &my);
                Value d = val_dict();
                dict_set(&d, "x", val_number(mx));
                dict_set(&d, "y", val_number(my));
                if (!vm_push(&vm, d)) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_MOUSE_DELTA: {
                double dx, dy;
                sgpu_mouse_delta(&dx, &dy);
                Value d = val_dict();
                dict_set(&d, "x", val_number(dx));
                dict_set(&d, "y", val_number(dy));
                if (!vm_push(&vm, d)) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_UPDATE_INPUT:
                sgpu_update_input();
                break;
            case BC_OP_GPU_BEGIN_COMMANDS: {
                Value cmd = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(sgpu_begin_commands((int)AS_NUMBER(cmd))))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_END_COMMANDS: {
                Value cmd = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(sgpu_end_commands((int)AS_NUMBER(cmd))))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_CMD_END_RP: {
                Value cmd = vm_pop(&vm);
                sgpu_cmd_end_render_pass((int)AS_NUMBER(cmd));
                break;
            }
            case BC_OP_GPU_CMD_BIND_GP: {
                Value pipe = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_bind_graphics_pipeline((int)AS_NUMBER(cmd), (int)AS_NUMBER(pipe));
                break;
            }
            case BC_OP_GPU_CMD_BIND_VB: {
                Value buf = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_bind_vertex_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf));
                break;
            }
            case BC_OP_GPU_CMD_BIND_IB: {
                Value buf = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_bind_index_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf));
                break;
            }
            case BC_OP_GPU_CMD_DRAW: {
                Value fi = vm_pop(&vm);
                Value fv = vm_pop(&vm);
                Value inst = vm_pop(&vm);
                Value verts = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_draw((int)AS_NUMBER(cmd), (int)AS_NUMBER(verts),
                              (int)AS_NUMBER(inst), (int)AS_NUMBER(fv), (int)AS_NUMBER(fi));
                break;
            }
            case BC_OP_GPU_CMD_DRAW_IDX: {
                Value fi = vm_pop(&vm);
                Value vo = vm_pop(&vm);
                Value fidx = vm_pop(&vm);
                Value inst = vm_pop(&vm);
                Value idx_count = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_draw_indexed((int)AS_NUMBER(cmd), (int)AS_NUMBER(idx_count),
                    (int)AS_NUMBER(inst), (int)AS_NUMBER(fidx), (int)AS_NUMBER(vo), (int)AS_NUMBER(fi));
                break;
            }
            case BC_OP_GPU_CMD_BEGIN_RP: {
                Value clear = vm_pop(&vm);
                Value h = vm_pop(&vm);
                Value w = vm_pop(&vm);
                Value fb = vm_pop(&vm);
                Value rp = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                float cr = 0, cg = 0, cb = 0, ca = 1;
                if (IS_ARRAY(clear) && clear.as.array->count >= 4) {
                    cr = (float)AS_NUMBER(clear.as.array->elements[0]);
                    cg = (float)AS_NUMBER(clear.as.array->elements[1]);
                    cb = (float)AS_NUMBER(clear.as.array->elements[2]);
                    ca = (float)AS_NUMBER(clear.as.array->elements[3]);
                }
                sgpu_cmd_begin_render_pass((int)AS_NUMBER(cmd), (int)AS_NUMBER(rp),
                    (int)AS_NUMBER(fb), (int)AS_NUMBER(w), (int)AS_NUMBER(h), cr, cg, cb, ca);
                break;
            }
            case BC_OP_GPU_CMD_BIND_DS: {
                Value bp = vm_pop(&vm);
                Value set = vm_pop(&vm);
                Value layout = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_bind_descriptor_set((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout),
                    (int)AS_NUMBER(set), (int)AS_NUMBER(bp));
                break;
            }
            case BC_OP_GPU_CMD_SET_VP: {
                Value maxd = vm_pop(&vm);
                Value mind = vm_pop(&vm);
                Value vh = vm_pop(&vm);
                Value vw = vm_pop(&vm);
                Value vy = vm_pop(&vm);
                Value vx = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_set_viewport((int)AS_NUMBER(cmd),
                    (float)AS_NUMBER(vx), (float)AS_NUMBER(vy),
                    (float)AS_NUMBER(vw), (float)AS_NUMBER(vh),
                    (float)AS_NUMBER(mind), (float)AS_NUMBER(maxd));
                break;
            }
            case BC_OP_GPU_CMD_SET_SC: {
                Value sh = vm_pop(&vm);
                Value sw = vm_pop(&vm);
                Value sy = vm_pop(&vm);
                Value sx = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_set_scissor((int)AS_NUMBER(cmd),
                    (int)AS_NUMBER(sx), (int)AS_NUMBER(sy),
                    (int)AS_NUMBER(sw), (int)AS_NUMBER(sh));
                break;
            }
            case BC_OP_GPU_SUBMIT_SYNC: {
                Value fence = vm_pop(&vm);
                Value signal = vm_pop(&vm);
                Value wait = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                if (!vm_push(&vm, val_bool(sgpu_submit_with_sync(
                    (int)AS_NUMBER(cmd), (int)AS_NUMBER(wait),
                    (int)AS_NUMBER(signal), (int)AS_NUMBER(fence))))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_ACQUIRE_IMG: {
                Value sem = vm_pop(&vm);
                int img_idx = 0;
                sgpu_acquire_next_image((int)AS_NUMBER(sem), &img_idx);
                if (!vm_push(&vm, val_number(img_idx))) {
                    result = vm_error("VM stack overflow."); goto done;
                }
                break;
            }
            case BC_OP_GPU_PRESENT: {
                Value idx = vm_pop(&vm);
                Value sem = vm_pop(&vm);
                sgpu_present((int)AS_NUMBER(sem), (int)AS_NUMBER(idx));
                break;
            }
            case BC_OP_GPU_WAIT_FENCE: {
                Value timeout = vm_pop(&vm);
                Value fence = vm_pop(&vm);
                sgpu_wait_fence((int)AS_NUMBER(fence), AS_NUMBER(timeout));
                break;
            }
            case BC_OP_GPU_RESET_FENCE: {
                Value fence = vm_pop(&vm);
                sgpu_reset_fence((int)AS_NUMBER(fence));
                break;
            }
            case BC_OP_GPU_UPDATE_UNIFORM: {
                Value data = vm_pop(&vm);
                Value handle = vm_pop(&vm);
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                    float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                    for (int fi = 0; fi < data.as.array->count; fi++) {
                        floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    }
                    sgpu_update_uniform((int)AS_NUMBER(handle), floats, data.as.array->count);
                    free(floats);
                }
                break;
            }
            case BC_OP_GPU_CMD_PUSH_CONST: {
                Value data = vm_pop(&vm);
                Value stages = vm_pop(&vm);
                Value layout = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                    float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                    for (int fi = 0; fi < data.as.array->count; fi++) {
                        floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    }
                    sgpu_cmd_push_constants((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout),
                        (int)AS_NUMBER(stages), floats, data.as.array->count);
                    free(floats);
                }
                break;
            }
            case BC_OP_GPU_CMD_DISPATCH: {
                Value gz = vm_pop(&vm);
                Value gy = vm_pop(&vm);
                Value gx = vm_pop(&vm);
                Value cmd = vm_pop(&vm);
                sgpu_cmd_dispatch((int)AS_NUMBER(cmd),
                    (int)AS_NUMBER(gx), (int)AS_NUMBER(gy), (int)AS_NUMBER(gz));
                break;
            }

            // Break/continue/loop_back are resolved by the bytecode compiler
            // into JUMP instructions. These should never appear at runtime.
            case BC_OP_BREAK:
            case BC_OP_CONTINUE:
            case BC_OP_LOOP_BACK:
                result = vm_error("Unexpected break/continue/loop opcode at runtime.");
                goto done;

            // Import, class, try/raise — these are handled via AST fallback
            // in hybrid mode. If they appear as raw opcodes, it's an error.
            case BC_OP_IMPORT:
            case BC_OP_CLASS:
            case BC_OP_METHOD:
            case BC_OP_INHERIT:
            case BC_OP_SETUP_TRY:
            case BC_OP_END_TRY:
            case BC_OP_RAISE:
                result = vm_error("Unimplemented bytecode opcode.");
                goto done;

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

ExecResult vm_execute_program(BytecodeProgram* program, Env* env) {
    ExecResult result = vm_normal(val_nil());
    if (program == NULL) {
        return result;
    }

    for (int i = 0; i < program->chunk_count; i++) {
        result = vm_execute_chunk(&program->chunks[i], env);
        if (result.is_throwing) {
            return result;
        }
    }

    return result;
}
