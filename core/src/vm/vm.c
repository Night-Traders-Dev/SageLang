#include "vm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "module.h"
#include "repl.h"
#include "sage_thread.h"
#include "gc.h"
#include "gpu_api.h"

extern __thread EnvRootNode* g_gc_root_stack;

#define VM_STACK_MAX 65536

typedef struct ActiveVm {
    BytecodeChunk* chunk;
    Env* current_env;
    Value stack[VM_STACK_MAX];
    int stack_count;
    struct ActiveVm* parent;
} ActiveVm;

static __thread ActiveVm* g_active_vm = NULL;

static ExecResult vm_normal(Value value) {
// ... (omitting intermediate code for brevity in replace tool, but will provide full context in actual call)
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

void vm_mark_roots(void* active_vm_head) {
    for (ActiveVm* active = (ActiveVm*)active_vm_head; active != NULL; active = active->parent) {
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

#define VM_CHECK_CONST(chunk, idx) \
    do { if ((int)(idx) >= (chunk)->constant_count) { \
        result = vm_error("VM constant pool index out of bounds."); goto done; \
    } } while(0)

#define VM_CHECK_AST(chunk, idx) \
    do { if ((int)(idx) >= (chunk)->ast_stmt_count) { \
        result = vm_error("VM AST statement index out of bounds."); goto done; \
    } } while(0)

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

        gc_pin();
        ProcStmt* func = (ProcStmt*)AS_FUNCTION(callee);
        if (arg_count != func->param_count) {
            gc_unpin();
            return vm_error("Arity mismatch.");
        }

        Env* scope = env_create(callee.as.function->closure);
        for (int i = 0; i < func->param_count; i++) {
            Token param = func->params[i];
            env_define(scope, param.start, param.length, args[i]);
        }

        ExecResult result = interpret(func->body, scope);
        gc_unpin();
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
        gc_pin();
        ClassValue* class_def = callee.as.class_val;
        InstanceValue* instance = instance_create(class_def);
        Value instance_value = val_instance(instance);

        Method* init_method = class_find_method(class_def, "init", 4);
        if (init_method != NULL) {
            Stmt* init_node = (Stmt*)init_method->method_stmt;
            if (init_node == NULL) { gc_unpin(); return vm_error("Invalid init method."); }
            ProcStmt* init_stmt = (init_node->type == STMT_ASYNC_PROC) ? &init_node->as.async_proc : &init_node->as.proc;

            Env* def_env = class_def->defining_env;
            Env* method_env = env_create(def_env ? def_env : env);
            env_define(method_env, "self", 4, instance_value);

            int param_start = (init_stmt->param_count > 0 &&
                              init_stmt->params != NULL &&
                              strncmp(init_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;

            for (int i = param_start; i < init_stmt->param_count; i++) {
                if (i - param_start < arg_count) {
                    env_define(method_env, init_stmt->params[i].start,
                               init_stmt->params[i].length, args[i - param_start]);
                }
            }

            ExecResult init_result = interpret(init_stmt->body, method_env);
            if (init_result.is_throwing) {
                gc_unpin();
                return init_result;
            }
        } else {
            // Auto-init for structs: look for __StructName_fields__ metadata
            char meta_key[256];
            snprintf(meta_key, sizeof(meta_key), "__%.*s_fields__",
                     class_def->name_len, class_def->name);
            Value fields_val;
            if (env_get(env, meta_key, (int)strlen(meta_key), &fields_val) &&
                fields_val.type == VAL_ARRAY) {
                ArrayValue* fields = fields_val.as.array;
                for (int i = 0; i < fields->count && i < arg_count; i++) {
                    if (fields->elements[i].type == VAL_STRING) {
                        char* field_name = AS_STRING(fields->elements[i]);
                        instance_set_field(instance, field_name, (int)strlen(field_name), args[i]);
                    }
                }
            }
        }

        gc_unpin();
        return vm_normal(instance_value);
    }

    return vm_error("Value is not callable.");
}

static ExecResult call_method_value(Value object, const char* method_name, int arg_count, Value* args, Env* env) {
    if (IS_INSTANCE(object)) {
        gc_pin();
        Method* method = class_find_method(object.as.instance->class_def, method_name, (int)strlen(method_name));
        if (method == NULL) {
            gc_unpin();
            return vm_error("Undefined method.");
        }

        Stmt* method_node = (Stmt*)method->method_stmt;
        ProcStmt* method_stmt = (method_node->type == STMT_ASYNC_PROC) ? &method_node->as.async_proc : &method_node->as.proc;
        Env* def_env = object.as.instance->class_def->defining_env;
        Env* method_env = env_create(def_env ? def_env : env);
        env_define(method_env, "self", 4, object);
        

        // Track class owning method for super resolution
        ClassValue* owner = class_find_method_owner(object.as.instance->class_def, method_name, (int)strlen(method_name));
        if (owner) env_define_const(method_env, "__class__", 9, val_class(owner));

        int param_start = (method_stmt->param_count > 0 &&
                          strncmp(method_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;
        for (int i = param_start; i < method_stmt->param_count; i++) {
            if (i - param_start < arg_count) {
                env_define(method_env, method_stmt->params[i].start,
                           method_stmt->params[i].length, args[i - param_start]);
            }
        }

        ExecResult result = interpret(method_stmt->body, method_env);
        gc_unpin();
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
    
    EnvRootNode root_node;
    root_node.env = env;
    
    ThreadState* ts = gc_get_thread_state();
    if (ts) {
        root_node.next = ts->gc_root_stack;
        ts->gc_root_stack = &root_node;
    } else {
        // Fallback for unregistered threads (less safe)
        root_node.next = g_gc_root_stack;
        g_gc_root_stack = &root_node;
    }

    ActiveVm* previous_vm = g_active_vm;
    
    memset(&vm, 0, sizeof(vm));
    vm.chunk = chunk;
    vm.current_env = env;
    vm.parent = previous_vm;

    g_active_vm = &vm;
    if (ts) ts->active_vm = g_active_vm;

    uint8_t* code = chunk->code;
    uint8_t* ip = code;
    uint8_t* ip_end = code + chunk->code_count;
    Value* constants = chunk->constants;
    Value* sp = vm.stack;

#ifdef __GNUC__
    static void* dispatch_table[] = {
        &&BC_OP_CONSTANT, &&BC_OP_NIL, &&BC_OP_TRUE, &&BC_OP_FALSE, &&BC_OP_POP,
        &&BC_OP_GET_GLOBAL, &&BC_OP_DEFINE_GLOBAL, &&BC_OP_SET_GLOBAL,
        &&BC_OP_DEFINE_FUNCTION, &&BC_OP_GET_PROPERTY, &&BC_OP_SET_PROPERTY,
        &&BC_OP_GET_INDEX, &&BC_OP_SET_INDEX, &&BC_OP_SLICE, &&BC_OP_ADD,
        &&BC_OP_SUB, &&BC_OP_MUL, &&BC_OP_DIV, &&BC_OP_MOD, &&BC_OP_NEGATE,
        &&BC_OP_EQUAL, &&BC_OP_NOT_EQUAL, &&BC_OP_GREATER, &&BC_OP_GREATER_EQUAL,
        &&BC_OP_LESS, &&BC_OP_LESS_EQUAL, &&BC_OP_BIT_AND, &&BC_OP_BIT_OR,
        &&BC_OP_BIT_XOR, &&BC_OP_BIT_NOT, &&BC_OP_SHIFT_LEFT, &&BC_OP_SHIFT_RIGHT,
        &&BC_OP_NOT, &&BC_OP_TRUTHY, &&BC_OP_JUMP, &&BC_OP_JUMP_IF_FALSE,
        &&BC_OP_CALL, &&BC_OP_CALL_METHOD, &&BC_OP_ARRAY, &&BC_OP_TUPLE,
        &&BC_OP_DICT, &&BC_OP_PRINT, &&BC_OP_EXEC_AST_STMT, &&BC_OP_RETURN,
        &&BC_OP_PUSH_ENV, &&BC_OP_POP_ENV, &&BC_OP_DUP, &&BC_OP_ARRAY_LEN,
        &&BC_OP_BREAK, &&BC_OP_CONTINUE, &&BC_OP_LOOP_BACK, &&BC_OP_IMPORT,
        &&BC_OP_CLASS, &&BC_OP_METHOD, &&BC_OP_INHERIT, &&BC_OP_SETUP_TRY,
        &&BC_OP_END_TRY, &&BC_OP_RAISE, &&BC_OP_GPU_POLL_EVENTS,
        &&BC_OP_GPU_WINDOW_SHOULD_CLOSE, &&BC_OP_GPU_GET_TIME,
        &&BC_OP_GPU_KEY_PRESSED, &&BC_OP_GPU_KEY_DOWN, &&BC_OP_GPU_MOUSE_POS,
        &&BC_OP_GPU_MOUSE_DELTA, &&BC_OP_GPU_UPDATE_INPUT,
        &&BC_OP_GPU_BEGIN_COMMANDS, &&BC_OP_GPU_END_COMMANDS,
        &&BC_OP_GPU_CMD_BEGIN_RP, &&BC_OP_GPU_CMD_END_RP, &&BC_OP_GPU_CMD_DRAW,
        &&BC_OP_GPU_CMD_BIND_GP, &&BC_OP_GPU_CMD_BIND_DS, &&BC_OP_GPU_CMD_SET_VP,
        &&BC_OP_GPU_CMD_SET_SC, &&BC_OP_GPU_CMD_BIND_VB, &&BC_OP_GPU_CMD_BIND_IB,
        &&BC_OP_GPU_CMD_DRAW_IDX, &&BC_OP_GPU_SUBMIT_SYNC, &&BC_OP_GPU_ACQUIRE_IMG,
        &&BC_OP_GPU_PRESENT, &&BC_OP_GPU_WAIT_FENCE, &&BC_OP_GPU_RESET_FENCE,
        &&BC_OP_GPU_UPDATE_UNIFORM, &&BC_OP_GPU_CMD_PUSH_CONST,
        &&BC_OP_GPU_CMD_DISPATCH
    };

    #define DISPATCH() \
        do { \
            if (ip >= ip_end) goto done; \
            goto *dispatch_table[*ip++]; \
        } while (0)
#else
    #define DISPATCH() continue
#endif

#define PUSH(val) \
    do { \
        Value _val = (val); \
        if (sp >= vm.stack + VM_STACK_MAX) { \
            SYNC_SP(); \
            result = vm_error("VM stack overflow."); \
            goto done; \
        } \
        *sp++ = _val; \
    } while (0)

#define POP() (*(--sp))
#define PEEK(dist) (*(sp - 1 - (dist)))
#define SYNC_SP() vm.stack_count = (int)(sp - vm.stack)
#define READ_U8() (*ip++)
#define READ_U16() (ip += 2, (uint16_t)((ip[-2] << 8) | ip[-1]))

#ifdef __GNUC__
    DISPATCH();
#endif

    while (ip < ip_end) {
#ifndef __GNUC__
        BytecodeOp op = (BytecodeOp)*ip++;
        switch (op) {
#endif
            BC_OP_CONSTANT: {
                uint16_t index = READ_U16();
                VM_CHECK_CONST(chunk, index);
                PUSH(constants[index]);
                DISPATCH();
            }
            BC_OP_NIL:
                PUSH(val_nil());
                DISPATCH();
            BC_OP_TRUE:
                PUSH(val_bool(1));
                DISPATCH();
            BC_OP_FALSE:
                PUSH(val_bool(0));
                DISPATCH();
            BC_OP_POP:
                (void)POP();
                DISPATCH();
            BC_OP_GET_GLOBAL: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);
                Value name = constants[name_index];
                Value resolved = val_nil();
                SYNC_SP();
                if (!env_get(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), &resolved)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                PUSH(resolved);
                DISPATCH();
            }
            BC_OP_DEFINE_GLOBAL: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);
                Value name = constants[name_index];
                Value value = POP();
                SYNC_SP();
                env_define(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), value);
                DISPATCH();
            }
            BC_OP_SET_GLOBAL: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);
                Value name = constants[name_index];
                Value value = PEEK(0);
                SYNC_SP();
                if (!env_assign(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), value)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                DISPATCH();
            }
            BC_OP_DEFINE_FUNCTION: {
                uint16_t name_index = READ_U16();
                uint16_t function_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);

                if (chunk->program == NULL || function_index >= chunk->program->function_count) {
                    result = vm_error("Invalid compiled VM function reference.");
                    goto done;
                }

                Value name = constants[name_index];
                SYNC_SP();
                Value function = val_bytecode_function(&chunk->program->functions[function_index], vm.current_env);
                env_define(vm.current_env, AS_STRING(name), (int)strlen(AS_STRING(name)), function);
                DISPATCH();
            }
            BC_OP_GET_PROPERTY: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);
                Value object = POP();
                const char* property = AS_STRING(constants[name_index]);

                SYNC_SP();
                if (IS_INSTANCE(object)) {
                    Value field = instance_get_field(object.as.instance, property, (int)strlen(property));
                    PUSH(field);
                } else if (IS_MODULE(object)) {
                    int found = 0;
                    Value attr = module_get_attr(AS_MODULE(object), property, (int)strlen(property), &found);
                    if (!found) {
                        result = vm_error("Module attribute is not defined.");
                        goto done;
                    }
                    PUSH(attr);
                } else {
                    result = vm_error("Only instances and modules have properties.");
                    goto done;
                }
                DISPATCH();
            }
            BC_OP_SET_PROPERTY: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);
                Value value = POP();
                Value object = POP();
                const char* property = AS_STRING(constants[name_index]);

                if (!IS_INSTANCE(object)) {
                    result = vm_error("Only instances have properties.");
                    goto done;
                }

                SYNC_SP();
                instance_set_field(object.as.instance, property, (int)strlen(property), value);
                PUSH(value);
                DISPATCH();
            }
            BC_OP_GET_INDEX: {
                Value index = POP();
                Value object = POP();

                SYNC_SP();
                if (object.type == VAL_ARRAY && IS_NUMBER(index)) {
                    PUSH(array_get(&object, (int)AS_NUMBER(index)));
                } else if (object.type == VAL_TUPLE && IS_NUMBER(index)) {
                    PUSH(tuple_get(&object, (int)AS_NUMBER(index)));
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
                    PUSH(val_string_take(character));
                } else if (object.type == VAL_DICT && IS_STRING(index)) {
                    PUSH(dict_get(&object, AS_STRING(index)));
                } else {
                    result = vm_error("Invalid indexing operation.");
                    goto done;
                }
                DISPATCH();
            }
            BC_OP_SET_INDEX: {
                Value value = POP();
                Value index = POP();
                Value object = POP();

                SYNC_SP();
                if (object.type == VAL_ARRAY && IS_NUMBER(index)) {
                    array_set(&object, (int)AS_NUMBER(index), value);
                } else if (object.type == VAL_DICT && IS_STRING(index)) {
                    dict_set(&object, AS_STRING(index), value);
                } else {
                    result = vm_error("Invalid index assignment.");
                    goto done;
                }

                PUSH(value);
                DISPATCH();
            }
            BC_OP_SLICE: {
                Value end = POP();
                Value start = POP();
                Value object = POP();

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

                SYNC_SP();
                if (IS_ARRAY(object)) {
                    PUSH(array_slice(&object, start_index, end_index));
                } else {
                    char* string = AS_STRING(object);
                    int string_length = (int)strlen(string);
                    if (start_index < 0) start_index += string_length;
                    if (end_index < 0) end_index += string_length;
                    if (start_index < 0) start_index = 0;
                    if (end_index > string_length) end_index = string_length;
                    if (start_index >= end_index) {
                        PUSH(val_string(""));
                    } else {
                        int length = end_index - start_index;
                        char* slice = SAGE_ALLOC((size_t)length + 1);
                        memcpy(slice, string + start_index, (size_t)length);
                        slice[length] = '\0';
                        PUSH(val_string_take(slice));
                    }
                }
                DISPATCH();
            }
            BC_OP_ADD:
            BC_OP_SUB:
            BC_OP_MUL:
            BC_OP_DIV:
            BC_OP_MOD:
            BC_OP_EQUAL:
            BC_OP_NOT_EQUAL:
            BC_OP_GREATER:
            BC_OP_GREATER_EQUAL:
            BC_OP_LESS:
            BC_OP_LESS_EQUAL:
            BC_OP_BIT_AND:
            BC_OP_BIT_OR:
            BC_OP_BIT_XOR:
            BC_OP_SHIFT_LEFT:
            BC_OP_SHIFT_RIGHT: {
                BytecodeOp local_op = (BytecodeOp)ip[-1];
                Value right = POP();
                Value left = POP();
                Value out = val_nil();

                if (local_op == BC_OP_EQUAL || local_op == BC_OP_NOT_EQUAL) {
                    int equal = values_equal(left, right);
                    out = val_bool(local_op == BC_OP_EQUAL ? equal : !equal);
                } else if (local_op == BC_OP_GREATER || local_op == BC_OP_GREATER_EQUAL ||
                           local_op == BC_OP_LESS || local_op == BC_OP_LESS_EQUAL) {
                    if (IS_NUMBER(left) && IS_NUMBER(right)) {
                        double l = AS_NUMBER(left), r = AS_NUMBER(right);
                        if (local_op == BC_OP_GREATER) out = val_bool(l > r);
                        else if (local_op == BC_OP_GREATER_EQUAL) out = val_bool(l >= r);
                        else if (local_op == BC_OP_LESS) out = val_bool(l < r);
                        else out = val_bool(l <= r);
                    } else if (IS_STRING(left) && IS_STRING(right)) {
                        int cmp = strcmp(AS_STRING(left), AS_STRING(right));
                        if (local_op == BC_OP_GREATER) out = val_bool(cmp > 0);
                        else if (local_op == BC_OP_GREATER_EQUAL) out = val_bool(cmp >= 0);
                        else if (local_op == BC_OP_LESS) out = val_bool(cmp < 0);
                        else out = val_bool(cmp <= 0);
                    } else {
                        result = vm_error("Operands must be numbers or strings.");
                        goto done;
                    }
                } else if (local_op == BC_OP_ADD && IS_STRING(left) && IS_STRING(right)) {
                    SYNC_SP();
                    size_t len1 = strlen(AS_STRING(left));
                    size_t len2 = strlen(AS_STRING(right));
                    char* joined = SAGE_ALLOC(len1 + len2 + 1);
                    memcpy(joined, AS_STRING(left), len1);
                    memcpy(joined + len1, AS_STRING(right), len2 + 1);
                    out = val_string_take(joined);
                } else if (IS_NUMBER(left) && IS_NUMBER(right)) {
                    long long l = (long long)AS_NUMBER(left);
                    long long r = (long long)AS_NUMBER(right);
                    switch (local_op) {
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

                PUSH(out);
                DISPATCH();
            }
            BC_OP_NEGATE: {
                Value value = POP();
                if (!IS_NUMBER(value)) {
                    result = vm_error("Unary '-' requires a number.");
                    goto done;
                }
                PUSH(val_number(-AS_NUMBER(value)));
                DISPATCH();
            }
            BC_OP_BIT_NOT: {
                Value value = POP();
                if (!IS_NUMBER(value)) {
                    result = vm_error("Bitwise NOT operand must be a number.");
                    goto done;
                }
                PUSH(val_number((double)(~(long long)AS_NUMBER(value))));
                DISPATCH();
            }
            BC_OP_NOT: {
                Value value = POP();
                PUSH(val_bool(!vm_is_truthy(value)));
                DISPATCH();
            }
            BC_OP_TRUTHY: {
                Value value = POP();
                PUSH(val_bool(vm_is_truthy(value)));
                DISPATCH();
            }
            BC_OP_JUMP:
                ip = code + READ_U16();
                DISPATCH();
            BC_OP_JUMP_IF_FALSE: {
                uint16_t target = READ_U16();
                if (!vm_is_truthy(PEEK(0))) {
                    ip = code + target;
                }
                DISPATCH();
            }
            BC_OP_CALL: {
                int arg_count = (int)READ_U8();
                if ((int)(sp - vm.stack) < arg_count + 1) {
                    result = vm_error("VM stack underflow on call.");
                    goto done;
                }
                
                Value callee = *(sp - 1 - arg_count);
                Value* args = sp - arg_count;

                SYNC_SP();
                ExecResult call_result = call_function_value(callee, arg_count, args, vm.current_env);
                
                sp -= (arg_count + 1);

                if (call_result.is_throwing) {
                    result = call_result;
                    goto done;
                }
                PUSH(call_result.value);
                DISPATCH();
            }
            BC_OP_CALL_METHOD: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(chunk, name_index);
                int arg_count = (int)READ_U8();
                if ((int)(sp - vm.stack) < arg_count + 1) {
                    result = vm_error("VM stack underflow on method call.");
                    goto done;
                }

                Value object = *(sp - 1 - arg_count);
                Value* args = sp - arg_count;

                SYNC_SP();
                ExecResult call_result = call_method_value(object, AS_STRING(constants[name_index]), arg_count, args, vm.current_env);
                
                sp -= (arg_count + 1);

                if (call_result.is_throwing) {
                    result = call_result;
                    goto done;
                }
                PUSH(call_result.value);
                DISPATCH();
            }
            BC_OP_ARRAY: {
                uint16_t count = READ_U16();
                SYNC_SP();
                Value array = val_array();
                
                for (int i = 0; i < (int)count; i++) {
                    array_push(&array, *(sp - (int)count + i));
                }
                
                sp -= (int)count;
                PUSH(array);
                DISPATCH();
            }
            BC_OP_TUPLE: {
                uint16_t count = READ_U16();
                SYNC_SP();
                Value tuple = val_tuple(sp - (int)count, (int)count);
                
                sp -= (int)count;
                PUSH(tuple);
                DISPATCH();
            }
            BC_OP_DICT: {
                uint16_t count = READ_U16();
                SYNC_SP();
                Value dictionary = val_dict();
                Value* dict_values = SAGE_ALLOC(sizeof(Value) * (size_t)count * 2);
                for (int i = ((int)count * 2) - 1; i >= 0; i--) {
                    dict_values[i] = POP();
                }
                for (int i = 0; i < (int)count; i++) {
                    Value key = dict_values[i * 2];
                    Value value = dict_values[i * 2 + 1];
                    if (!IS_STRING(key)) {
                        result = vm_error("Dictionary keys must be strings in bytecode mode.");
                        free(dict_values);
                        goto done;
                    }
                    dict_set(&dictionary, AS_STRING(key), value);
                }
                free(dict_values);
                PUSH(dictionary);
                DISPATCH();
            }
            BC_OP_PRINT: {
                Value value = POP();
                print_value(value);
                printf("\n");
                DISPATCH();
            }
            BC_OP_PUSH_ENV:
                SYNC_SP();
                vm.current_env = env_create(vm.current_env);
                DISPATCH();
            BC_OP_POP_ENV:
                if (vm.current_env == NULL || vm.current_env->parent == NULL) {
                    result = vm_error("Cannot pop the root VM scope.");
                    goto done;
                }
                vm.current_env = vm.current_env->parent;
                DISPATCH();
            BC_OP_DUP: {
                uint8_t distance = READ_U8();
                if ((int)distance >= (int)(sp - vm.stack)) {
                    result = vm_error("Invalid VM stack duplicate.");
                    goto done;
                }
                PUSH(PEEK((int)distance));
                DISPATCH();
            }
            BC_OP_ARRAY_LEN: {
                Value value = POP();
                if (!IS_ARRAY(value)) {
                    result = vm_error("for loop iterable must be an array.");
                    goto done;
                }
                PUSH(val_number((double)value.as.array->count));
                DISPATCH();
            }
            BC_OP_EXEC_AST_STMT: {
                uint16_t stmt_index = READ_U16();
                VM_CHECK_AST(chunk, stmt_index);
                SYNC_SP();
                ExecResult ast_result = interpret(chunk->ast_stmts[stmt_index], vm.current_env);
                if (ast_result.is_throwing) {
                    result = ast_result;
                    goto done;
                }
                PUSH(ast_result.value);
                DISPATCH();
            }
            BC_OP_GPU_POLL_EVENTS:
                sgpu_poll_events();
                DISPATCH();
            BC_OP_GPU_WINDOW_SHOULD_CLOSE:
                PUSH(val_bool(sgpu_window_should_close()));
                DISPATCH();
            BC_OP_GPU_GET_TIME:
                PUSH(val_number(sgpu_get_time()));
                DISPATCH();
            BC_OP_GPU_KEY_PRESSED: {
                Value key = POP();
                PUSH(val_bool(sgpu_key_pressed((int)AS_NUMBER(key))));
                DISPATCH();
            }
            BC_OP_GPU_KEY_DOWN: {
                Value key = POP();
                PUSH(val_bool(sgpu_key_down((int)AS_NUMBER(key))));
                DISPATCH();
            }
            BC_OP_GPU_MOUSE_POS: {
                double mx, my;
                sgpu_mouse_pos(&mx, &my);
                SYNC_SP();
                Value d = val_dict();
                dict_set(&d, "x", val_number(mx));
                dict_set(&d, "y", val_number(my));
                PUSH(d);
                DISPATCH();
            }
            BC_OP_GPU_MOUSE_DELTA: {
                double dx, dy;
                sgpu_mouse_delta(&dx, &dy);
                SYNC_SP();
                Value d = val_dict();
                dict_set(&d, "x", val_number(dx));
                dict_set(&d, "y", val_number(dy));
                PUSH(d);
                DISPATCH();
            }
            BC_OP_GPU_UPDATE_INPUT:
                sgpu_update_input();
                DISPATCH();
            BC_OP_GPU_BEGIN_COMMANDS: {
                Value cmd = POP();
                PUSH(val_bool(sgpu_begin_commands((int)AS_NUMBER(cmd))));
                DISPATCH();
            }
            BC_OP_GPU_END_COMMANDS: {
                Value cmd = POP();
                PUSH(val_bool(sgpu_end_commands((int)AS_NUMBER(cmd))));
                DISPATCH();
            }
            BC_OP_GPU_CMD_END_RP: {
                Value cmd = POP();
                sgpu_cmd_end_render_pass((int)AS_NUMBER(cmd));
                DISPATCH();
            }
            BC_OP_GPU_CMD_BIND_GP: {
                Value pipe = POP();
                Value cmd = POP();
                sgpu_cmd_bind_graphics_pipeline((int)AS_NUMBER(cmd), (int)AS_NUMBER(pipe));
                DISPATCH();
            }
            BC_OP_GPU_CMD_BIND_VB: {
                Value buf = POP();
                Value cmd = POP();
                sgpu_cmd_bind_vertex_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf));
                DISPATCH();
            }
            BC_OP_GPU_CMD_BIND_IB: {
                Value buf = POP();
                Value cmd = POP();
                sgpu_cmd_bind_index_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf));
                DISPATCH();
            }
            BC_OP_GPU_CMD_DRAW: {
                Value fi = POP();
                Value fv = POP();
                Value inst = POP();
                Value verts = POP();
                Value cmd = POP();
                sgpu_cmd_draw((int)AS_NUMBER(cmd), (int)AS_NUMBER(verts),
                              (int)AS_NUMBER(inst), (int)AS_NUMBER(fv), (int)AS_NUMBER(fi));
                DISPATCH();
            }
            BC_OP_GPU_CMD_DRAW_IDX: {
                Value fi = POP();
                Value vo = POP();
                Value fidx = POP();
                Value inst = POP();
                Value idx_count = POP();
                Value cmd = POP();
                sgpu_cmd_draw_indexed((int)AS_NUMBER(cmd), (int)AS_NUMBER(idx_count),
                    (int)AS_NUMBER(inst), (int)AS_NUMBER(fidx), (int)AS_NUMBER(vo), (int)AS_NUMBER(fi));
                DISPATCH();
            }
            BC_OP_GPU_CMD_BEGIN_RP: {
                Value clear = POP();
                Value h = POP();
                Value w = POP();
                Value fb = POP();
                Value rp = POP();
                Value cmd = POP();
                float cr = 0, cg = 0, cb = 0, ca = 1;
                if (IS_ARRAY(clear) && clear.as.array->count >= 4) {
                    cr = (float)AS_NUMBER(clear.as.array->elements[0]);
                    cg = (float)AS_NUMBER(clear.as.array->elements[1]);
                    cb = (float)AS_NUMBER(clear.as.array->elements[2]);
                    ca = (float)AS_NUMBER(clear.as.array->elements[3]);
                }
                sgpu_cmd_begin_render_pass((int)AS_NUMBER(cmd), (int)AS_NUMBER(rp),
                    (int)AS_NUMBER(fb), (int)AS_NUMBER(w), (int)AS_NUMBER(h), cr, cg, cb, ca);
                DISPATCH();
            }
            BC_OP_GPU_CMD_BIND_DS: {
                Value bp = POP();
                Value set = POP();
                Value layout = POP();
                Value cmd = POP();
                sgpu_cmd_bind_descriptor_set((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout),
                    (int)AS_NUMBER(set), (int)AS_NUMBER(bp));
                DISPATCH();
            }
            BC_OP_GPU_CMD_SET_VP: {
                Value maxd = POP();
                Value mind = POP();
                Value vh = POP();
                Value vw = POP();
                Value vy = POP();
                Value vx = POP();
                Value cmd = POP();
                sgpu_cmd_set_viewport((int)AS_NUMBER(cmd),
                    (float)AS_NUMBER(vx), (float)AS_NUMBER(vy),
                    (float)AS_NUMBER(vw), (float)AS_NUMBER(vh),
                    (float)AS_NUMBER(mind), (float)AS_NUMBER(maxd));
                DISPATCH();
            }
            BC_OP_GPU_CMD_SET_SC: {
                Value sh = POP();
                Value sw = POP();
                Value sy = POP();
                Value sx = POP();
                Value cmd = POP();
                sgpu_cmd_set_scissor((int)AS_NUMBER(cmd),
                    (int)AS_NUMBER(sx), (int)AS_NUMBER(sy),
                    (int)AS_NUMBER(sw), (int)AS_NUMBER(sh));
                DISPATCH();
            }
            BC_OP_GPU_SUBMIT_SYNC: {
                Value fence = POP();
                Value signal = POP();
                Value wait = POP();
                Value cmd = POP();
                PUSH(val_bool(sgpu_submit_with_sync(
                    (int)AS_NUMBER(cmd), (int)AS_NUMBER(wait),
                    (int)AS_NUMBER(signal), (int)AS_NUMBER(fence))));
                DISPATCH();
            }
            BC_OP_GPU_ACQUIRE_IMG: {
                Value sem = POP();
                int img_idx = 0;
                sgpu_acquire_next_image((int)AS_NUMBER(sem), &img_idx);
                PUSH(val_number(img_idx));
                DISPATCH();
            }
            BC_OP_GPU_PRESENT: {
                Value idx = POP();
                Value sem = POP();
                sgpu_present((int)AS_NUMBER(sem), (int)AS_NUMBER(idx));
                DISPATCH();
            }
            BC_OP_GPU_WAIT_FENCE: {
                Value timeout = POP();
                Value fence = POP();
                sgpu_wait_fence((int)AS_NUMBER(fence), AS_NUMBER(timeout));
                DISPATCH();
            }
            BC_OP_GPU_RESET_FENCE: {
                Value fence = POP();
                sgpu_reset_fence((int)AS_NUMBER(fence));
                DISPATCH();
            }
            BC_OP_GPU_UPDATE_UNIFORM: {
                Value data = POP();
                Value handle = POP();
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                    SYNC_SP();
                    float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                    for (int fi = 0; fi < data.as.array->count; fi++) {
                        floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    }
                    sgpu_update_uniform((int)AS_NUMBER(handle), floats, data.as.array->count);
                    free(floats);
                }
                DISPATCH();
            }
            BC_OP_GPU_CMD_PUSH_CONST: {
                Value data = POP();
                Value stages = POP();
                Value layout = POP();
                Value cmd = POP();
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                    SYNC_SP();
                    float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                    for (int fi = 0; fi < data.as.array->count; fi++) {
                        floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    }
                    sgpu_cmd_push_constants((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout),
                        (int)AS_NUMBER(stages), floats, data.as.array->count);
                    free(floats);
                }
                DISPATCH();
            }
            BC_OP_GPU_CMD_DISPATCH: {
                Value gz = POP();
                Value gy = POP();
                Value gx = POP();
                Value cmd = POP();
                sgpu_cmd_dispatch((int)AS_NUMBER(cmd),
                    (int)AS_NUMBER(gx), (int)AS_NUMBER(gy), (int)AS_NUMBER(gz));
                DISPATCH();
            }

            BC_OP_BREAK:
            BC_OP_CONTINUE:
            BC_OP_LOOP_BACK:
                result = vm_error("Unexpected break/continue/loop opcode at runtime.");
                goto done;

            BC_OP_IMPORT:
            BC_OP_CLASS:
            BC_OP_METHOD:
            BC_OP_INHERIT:
            BC_OP_SETUP_TRY:
            BC_OP_END_TRY:
            BC_OP_RAISE:
                result = vm_error("Unimplemented bytecode opcode.");
                goto done;

            BC_OP_RETURN:
                result = vm_normal(sp > vm.stack ? POP() : val_nil());
                goto done;
#ifndef __GNUC__
        }
#endif
    }

done:
    SYNC_SP();
    g_active_vm = previous_vm;
    if (ts) {
        ts->active_vm = g_active_vm;
        ts->gc_root_stack = root_node.next;
    } else {
        g_gc_root_stack = root_node.next;
    }
#undef PUSH
#undef POP
#undef PEEK
#undef SYNC_SP
#undef READ_U8
#undef READ_U16
#undef DISPATCH
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
