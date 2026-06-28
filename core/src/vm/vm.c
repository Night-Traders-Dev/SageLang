#include "vm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "module.h"
#include "repl.h"
#include "sage_thread.h"
#include "gc.h"
#include "gpu_api.h"

extern __thread EnvRootNode* g_gc_root_stack;

typedef struct {
    int handler_ip_offset;
    int stack_depth;
    Env* env;
} ExceptionHandler;

#define VM_STACK_MAX 65536
#define VM_HANDLER_MAX 256

typedef struct ActiveVm {
    BytecodeChunk* chunk;
    Env* current_env;
    Value stack[VM_STACK_MAX];
    int stack_count;
    struct ActiveVm* parent;

    ExceptionHandler handlers[VM_HANDLER_MAX];
    int handler_count;
} ActiveVm;

static __thread ActiveVm* g_active_vm = NULL;

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

void vm_mark_roots(void* active_vm_head) {
    for (ActiveVm* active = (ActiveVm*)active_vm_head; active != NULL; active = active->parent) {
        vm_mark_chunk_constants(active->chunk);
        vm_mark_program_constants(active->chunk != NULL ? active->chunk->program : NULL);
        gc_mark_env(active->current_env);

        for (int i = 0; i < active->stack_count; i++) {
            gc_mark_value(active->stack[i]);
        }

        for (int i = 0; i < active->handler_count; i++) {
            gc_mark_env(active->handlers[i].env);
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

#define VM_CHECK_CONST(c, idx) \
    do { if ((int)(idx) >= (c)->constant_count) { \
        result = vm_error("VM constant pool index out of bounds."); goto done; \
    } } while(0)

#define VM_CHECK_AST(c, idx) \
    do { if ((int)(idx) >= (c)->ast_stmt_count) { \
        result = vm_error("VM AST statement index out of bounds."); goto done; \
    } } while(0)

// Forward declarations
static ExecResult call_function_value(Value callee, int arg_count, Value* args, Env* env);
static ExecResult call_method_value(Value object, const char* method_name, int arg_count, Value* args, Env* env);

static ExecResult call_any_method(Value object, Method* method, int arg_count, Value* args, Env* env) {
    void* method_ptr = method->method_stmt;
    if (method_ptr == NULL) return vm_error("Invalid method implementation.");

    // Distinguish Stmt* (AST) from FunctionValue* (VM)
    Stmt* method_node = (Stmt*)method_ptr;
    if ((uintptr_t)method_ptr > 100 && ((int)method_node->type < 0 || (int)method_node->type > 100)) {
        // Likely a FunctionValue*
        FunctionValue* func = (FunctionValue*)method_ptr;
        Value func_val;
        func_val.type = VAL_FUNCTION;
        func_val.as.function = func;

        Value* method_args = SAGE_ALLOC(sizeof(Value) * (size_t)(arg_count + 1));
        method_args[0] = object;
        for (int i = 0; i < arg_count; i++) method_args[i + 1] = args[i];

        ExecResult res = call_function_value(func_val, arg_count + 1, method_args, env);
        free(method_args);
        return res;
    }

    ProcStmt* method_stmt = (method_node->type == STMT_ASYNC_PROC) ? &method_node->as.async_proc : &method_node->as.proc;
    ClassValue* class_def = IS_INSTANCE(object) ? object.as.instance->class_def : object.as.class_val;
    Env* def_env = class_def->defining_env;
    Env* method_env = env_create(def_env ? def_env : env);
    env_define(method_env, "self", 4, object);

    // Track class owning method for super resolution
    ClassValue* owner = class_find_method_owner(class_def, method->name, method->name_len);
    if (owner) env_define_const(method_env, "__class__", 9, val_class(owner));

    int param_start = (method_stmt->param_count > 0 &&
                      method_stmt->params != NULL &&
                      strncmp(method_stmt->params[0].start, "self", 4) == 0) ? 1 : 0;
    for (int i = param_start; i < method_stmt->param_count; i++) {
        if (i - param_start < arg_count) {
            env_define(method_env, method_stmt->params[i].start,
                       method_stmt->params[i].length, args[i - param_start]);
        }
    }

    return interpret(method_stmt->body, method_env);
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
            ExecResult init_result = call_any_method(instance_value, init_method, arg_count, args, env);
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

        ExecResult res = call_any_method(object, method, arg_count, args, env);
        gc_unpin();
        return res;
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

#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
#endif
typedef struct {
    uint8_t* ip;
    uint8_t* ip_end;
    BytecodeChunk* chunk;
    Value* slots;
    Env* closure;
} CallFrame;

#define MAX_FRAMES 1024

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
        root_node.next = g_gc_root_stack;
        g_gc_root_stack = &root_node;
    }

    ActiveVm* previous_vm = g_active_vm;
    
    memset(&vm, 0, sizeof(vm));
    vm.chunk = chunk;
    vm.parent = previous_vm;

    g_active_vm = &vm;
    if (ts) ts->active_vm = g_active_vm;

    CallFrame frames[MAX_FRAMES];
    int frame_count = 0;

    CallFrame* frame = &frames[frame_count++];
    frame->chunk = chunk;
    frame->ip = chunk->code;
    frame->ip_end = chunk->code + chunk->code_count;
    frame->slots = vm.stack;
    frame->closure = env;

    Value* sp = vm.stack;
    Value* constants = frame->chunk->constants;
    uint8_t* ip = frame->ip;
    uint8_t* ip_end = frame->ip_end;

#ifdef __GNUC__
    static void* dispatch_table[] = {
        &&BC_OP_CONSTANT, &&BC_OP_NIL, &&BC_OP_TRUE, &&BC_OP_FALSE, &&BC_OP_POP,
        &&BC_OP_GET_GLOBAL, &&BC_OP_DEFINE_GLOBAL, &&BC_OP_SET_GLOBAL,
        &&BC_OP_DEFINE_FUNCTION, &&BC_OP_GET_PROPERTY, &&BC_OP_SET_PROPERTY,
        &&BC_OP_GET_INDEX, &&BC_OP_SET_INDEX, &&BC_OP_LOAD_FUNCTION, &&BC_OP_SLICE, &&BC_OP_ADD,
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
        &&BC_OP_END_TRY, &&BC_OP_RAISE, &&BC_OP_GET_LOCAL, &&BC_OP_SET_LOCAL,
        &&BC_OP_GPU_POLL_EVENTS,
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
            if (ip >= ip_end) { \
                if (frame_count > 1) goto BC_OP_RETURN; \
                else goto done; \
            } \
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
                VM_CHECK_CONST(frame->chunk, index);
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
            BC_OP_GET_LOCAL: {
                uint16_t index = READ_U16();
                PUSH(frame->slots[index]);
                DISPATCH();
            }
            BC_OP_SET_LOCAL: {
                uint16_t index = READ_U16();
                frame->slots[index] = PEEK(0);
                DISPATCH();
            }
            BC_OP_GET_GLOBAL: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                Value resolved = val_nil();
                SYNC_SP();
                if (!env_get(frame->closure, AS_STRING(name), (int)strlen(AS_STRING(name)), &resolved)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                PUSH(resolved);
                DISPATCH();
            }
            BC_OP_DEFINE_GLOBAL: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                Value value = POP();
                SYNC_SP();
                env_define(frame->closure, AS_STRING(name), (int)strlen(AS_STRING(name)), value);
                DISPATCH();
            }
            BC_OP_SET_GLOBAL: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                Value value = PEEK(0);
                SYNC_SP();
                if (!env_assign(frame->closure, AS_STRING(name), (int)strlen(AS_STRING(name)), value)) {
                    result = vm_error("Undefined variable.");
                    goto done;
                }
                DISPATCH();
            }
            BC_OP_DEFINE_FUNCTION: {
                uint16_t name_index = READ_U16();
                uint16_t function_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                if (chunk->program == NULL || function_index >= chunk->program->function_count) {
                    result = vm_error("Invalid compiled VM function reference.");
                    goto done;
                }
                Value name = constants[name_index];
                SYNC_SP();
                Value function = val_bytecode_function(&chunk->program->functions[function_index], frame->closure);
                env_define(frame->closure, AS_STRING(name), (int)strlen(AS_STRING(name)), function);
                DISPATCH();
            }
            BC_OP_GET_PROPERTY: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                Value object = POP();
                const char* property = AS_STRING(constants[name_index]);
                SYNC_SP();
                if (IS_INSTANCE(object)) {
                    Value field = instance_get_field(object.as.instance, property, (int)strlen(property));
                    PUSH(field);
                } else if (IS_MODULE(object)) {
                    int found = 0;
                    Value attr = module_get_attr(AS_MODULE(object), property, (int)strlen(property), &found);
                    if (!found) { result = vm_error("Module attribute not found."); goto done; }
                    PUSH(attr);
                } else {
                    result = vm_error("Only instances and modules have properties.");
                    goto done;
                }
                DISPATCH();
            }
            BC_OP_SET_PROPERTY: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
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
                } else if (object.type == VAL_BYTES && IS_NUMBER(index)) {
                    int b_index = (int)AS_NUMBER(index);
                    BytesValue* b = object.as.bytes;
                    if (b_index < 0) b_index += b->length;
                    if (b_index >= 0 && b_index < b->length) {
                        PUSH(val_number(b->data[b_index]));
                    } else {
                        result = vm_error("Bytes index out of bounds.");
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
                } else if (object.type == VAL_BYTES && IS_NUMBER(index)) {
                    int b_index = (int)AS_NUMBER(index);
                    BytesValue* b = object.as.bytes;
                    if (b_index >= 0 && b_index < b->length) {
                        b->data[b_index] = (unsigned char)(int)AS_NUMBER(value);
                    }
                } else if (object.type == VAL_DICT && IS_STRING(index)) {
                    dict_set(&object, AS_STRING(index), value);
                } else {
                    result = vm_error("VM: Invalid index assignment.");
                    goto done;
                }
                PUSH(value);
                DISPATCH();
            }
            BC_OP_LOAD_FUNCTION: {
                uint16_t function_index = READ_U16();
                if (chunk->program == NULL || function_index >= chunk->program->function_count) {
                    result = vm_error("Invalid compiled VM function reference.");
                    goto done;
                }
                SYNC_SP();
                Value function = val_bytecode_function(&chunk->program->functions[function_index], frame->closure);
                PUSH(function);
                DISPATCH();
            }
            BC_OP_SLICE: {
                Value end = POP();
                Value start = POP();
                Value object = POP();
                int start_index = 0, end_index = 0;
                if (IS_ARRAY(object)) end_index = object.as.array->count;
                else if (IS_STRING(object)) end_index = (int)strlen(AS_STRING(object));
                else { result = vm_error("Can only slice arrays or strings."); goto done; }
                if (!IS_NIL(start)) {
                    if (!IS_NUMBER(start)) { result = vm_error("Slice start must be a number."); goto done; }
                    start_index = (int)AS_NUMBER(start);
                }
                if (!IS_NIL(end)) {
                    if (!IS_NUMBER(end)) { result = vm_error("Slice end must be a number."); goto done; }
                    end_index = (int)AS_NUMBER(end);
                }
                SYNC_SP();
                if (IS_ARRAY(object)) PUSH(array_slice(&object, start_index, end_index));
                else {
                    char* string = AS_STRING(object);
                    int string_length = (int)strlen(string);
                    if (start_index < 0) start_index += string_length;
                    if (end_index < 0) end_index += string_length;
                    if (start_index < 0) start_index = 0;
                    if (end_index > string_length) end_index = string_length;
                    if (start_index >= end_index) PUSH(val_string(""));
                    else {
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
                    } else { result = vm_error("Operands must be numbers or strings."); goto done; }
                } else if (local_op == BC_OP_ADD && IS_STRING(left) && IS_STRING(right)) {
                    SYNC_SP();
                    size_t len1 = strlen(AS_STRING(left));
                    size_t len2 = strlen(AS_STRING(right));
                    char* joined = SAGE_ALLOC(len1 + len2 + 1);
                    memcpy(joined, AS_STRING(left), len1);
                    memcpy(joined + len1, AS_STRING(right), len2 + 1);
                    out = val_string_take(joined);
                } else if (local_op == BC_OP_ADD && IS_ARRAY(left) && IS_ARRAY(right)) {
                    SYNC_SP();
                    ArrayValue* la = left.as.array;
                    ArrayValue* ra = right.as.array;
                    int total = la->count + ra->count;
                    out = val_array();
                    ArrayValue* out_arr = out.as.array;
                    out_arr->count = total;
                    out_arr->capacity = total;
                    out_arr->elements = SAGE_ALLOC(sizeof(Value) * (size_t)total);
                    gc_track_external_allocation(sizeof(Value) * (size_t)total);
                    memcpy(out_arr->elements, la->elements, sizeof(Value) * la->count);
                    memcpy(out_arr->elements + la->count, ra->elements, sizeof(Value) * ra->count);
                } else if (IS_NUMBER(left) && IS_NUMBER(right)) {
                    long long l = (long long)AS_NUMBER(left);
                    long long r = (long long)AS_NUMBER(right);
                    switch (local_op) {
                        case BC_OP_ADD: out = val_number(AS_NUMBER(left) + AS_NUMBER(right)); break;
                        case BC_OP_SUB: out = val_number(AS_NUMBER(left) - AS_NUMBER(right)); break;
                        case BC_OP_MUL: out = val_number(AS_NUMBER(left) * AS_NUMBER(right)); break;
                        case BC_OP_DIV: out = (AS_NUMBER(right) == 0) ? val_nil() : val_number(AS_NUMBER(left) / AS_NUMBER(right)); break;
                        case BC_OP_MOD: out = (AS_NUMBER(right) == 0) ? val_nil() : val_number(fmod(AS_NUMBER(left), AS_NUMBER(right))); break;
                        case BC_OP_BIT_AND: out = val_number((double)(l & r)); break;
                        case BC_OP_BIT_OR: out = val_number((double)(l | r)); break;
                        case BC_OP_BIT_XOR: out = val_number((double)(l ^ r)); break;
                        case BC_OP_SHIFT_LEFT: out = val_number((double)((unsigned long long)l << r)); break;
                        case BC_OP_SHIFT_RIGHT: out = val_number((double)((unsigned long long)l >> r)); break;
                        default: break;
                    }
                } else { result = vm_error("Operands mismatch."); goto done; }
                PUSH(out);
                DISPATCH();
            }
            BC_OP_NEGATE: {
                Value value = POP();
                if (!IS_NUMBER(value)) { result = vm_error("Unary '-' requires a number."); goto done; }
                PUSH(val_number(-AS_NUMBER(value)));
                DISPATCH();
            }
            BC_OP_BIT_NOT: {
                Value value = POP();
                if (!IS_NUMBER(value)) { result = vm_error("Bitwise NOT requires a number."); goto done; }
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
                ip = frame->chunk->code + READ_U16();
                DISPATCH();
            BC_OP_JUMP_IF_FALSE: {
                uint16_t target = READ_U16();
                if (!vm_is_truthy(PEEK(0))) ip = frame->chunk->code + target;
                DISPATCH();
            }
            BC_OP_CALL: {
                int arg_count = (int)READ_U8();
                if ((int)(sp - vm.stack) < arg_count + 1) { result = vm_error("VM stack underflow on call."); goto done; }
                Value callee = *(sp - 1 - arg_count);
                if (callee.type == VAL_FUNCTION && callee.as.function->is_vm) {
                    if (frame_count >= MAX_FRAMES) { result = vm_error("Stack overflow (max frames reached)."); goto done; }
                    BytecodeFunction* bcf = callee.as.function->vm_function;
                    if (arg_count != bcf->param_count) { result = vm_error("Arity mismatch."); goto done; }
                    
                    frame->ip = ip;
                    frame = &frames[frame_count++];
                    frame->chunk = &bcf->chunk;
                    frame->ip = bcf->chunk.code;
                    frame->ip_end = bcf->chunk.code + bcf->chunk.code_count;
                    frame->slots = sp - arg_count;
                    frame->closure = callee.as.function->closure;
                    
                    ip = frame->ip;
                    ip_end = frame->ip_end;
                    constants = frame->chunk->constants;
                    DISPATCH();
                } else {
                    Value* args = sp - arg_count;
                    SYNC_SP();
                    ExecResult call_result = call_function_value(callee, arg_count, args, frame->closure);
                    sp -= (arg_count + 1);
                    if (call_result.is_throwing) {
                        if (vm.handler_count > 0) {
                            vm.handler_count--;
                            ip = frame->chunk->code + vm.handlers[vm.handler_count].handler_ip_offset;
                            sp = vm.stack + vm.handlers[vm.handler_count].stack_depth;
                            frame->closure = vm.handlers[vm.handler_count].env;
                            PUSH(call_result.exception_value);
                            DISPATCH();
                        } else {
                            result = call_result;
                            goto done;
                        }
                    }
                    PUSH(call_result.value);
                    DISPATCH();
                }
            }
            BC_OP_CALL_METHOD: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                int arg_count = (int)READ_U8();
                if ((int)(sp - vm.stack) < arg_count + 1) { result = vm_error("VM stack underflow on method call."); goto done; }
                Value object = *(sp - 1 - arg_count);
                Value* args = sp - arg_count;
                SYNC_SP();
                ExecResult call_result = call_method_value(object, AS_STRING(constants[name_index]), arg_count, args, frame->closure);
                sp -= (arg_count + 1);
                if (call_result.is_throwing) {
                    if (vm.handler_count > 0) {
                        vm.handler_count--;
                        ip = frame->chunk->code + vm.handlers[vm.handler_count].handler_ip_offset;
                        sp = vm.stack + vm.handlers[vm.handler_count].stack_depth;
                        frame->closure = vm.handlers[vm.handler_count].env;
                        PUSH(call_result.exception_value);
                        DISPATCH();
                    } else {
                        result = call_result;
                        goto done;
                    }
                }
                PUSH(call_result.value);
                DISPATCH();
            }
            BC_OP_ARRAY: {
                uint16_t count = READ_U16();
                SYNC_SP();
                Value array = val_array();
                for (int i = 0; i < (int)count; i++) array_push(&array, *(sp - (int)count + i));
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
                Value* d_values = SAGE_ALLOC(sizeof(Value) * (size_t)count * 2);
                for (int i = ((int)count * 2) - 1; i >= 0; i--) d_values[i] = POP();
                for (int i = 0; i < (int)count; i++) {
                    if (!IS_STRING(d_values[i * 2])) { result = vm_error("Dict keys must be strings."); free(d_values); goto done; }
                    dict_set(&dictionary, AS_STRING(d_values[i * 2]), d_values[i * 2 + 1]);
                }
                free(d_values);
                PUSH(dictionary);
                DISPATCH();
            }
            BC_OP_PRINT: {
                Value value = POP();
                print_value(value);
                printf("\n");
                DISPATCH();
            }
            BC_OP_EXEC_AST_STMT: {
                uint16_t stmt_index = READ_U16();
                VM_CHECK_AST(frame->chunk, stmt_index);
                SYNC_SP();
                ExecResult ast_result = interpret(chunk->ast_stmts[stmt_index], frame->closure);
                if (ast_result.is_throwing) { result = ast_result; goto done; }
                PUSH(ast_result.value);
                DISPATCH();
            }
            BC_OP_RETURN: {
                Value res = sp > vm.stack ? POP() : val_nil();
                if (frame_count > 1) {
                    // Restore caller state
                    frame->ip = ip; // Save current IP before popping
                    
                    sp = frame->slots; // Reset stack to start of current frame
                    frame_count--;
                    frame = &frames[frame_count - 1];
                    
                    ip = frame->ip;
                    ip_end = frame->ip_end;
                    constants = frame->chunk->constants;
                    
                    PUSH(res);
                    DISPATCH();
                } else {
                    result = vm_normal(res);
                    goto done;
                }
            }
            BC_OP_PUSH_ENV:
                SYNC_SP();
                frame->closure = env_create(frame->closure);
                DISPATCH();
            BC_OP_POP_ENV:
                if (frame->closure == NULL || frame->closure->parent == NULL) { result = vm_error("Cannot pop root scope."); goto done; }
                frame->closure = frame->closure->parent;
                DISPATCH();
            BC_OP_DUP: {
                uint8_t distance = READ_U8();
                if ((int)distance >= (int)(sp - vm.stack)) { result = vm_error("Invalid stack duplicate."); goto done; }
                PUSH(PEEK((int)distance));
                DISPATCH();
            }
            BC_OP_ARRAY_LEN: {
                Value value = POP();
                if (!IS_ARRAY(value)) { result = vm_error("len() requires an array."); goto done; }
                PUSH(val_number((double)value.as.array->count));
                DISPATCH();
            }
            BC_OP_BREAK:
            BC_OP_CONTINUE:
            BC_OP_LOOP_BACK:
                result = vm_error("Unexpected loop control opcode.");
                goto done;
            BC_OP_IMPORT: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                SYNC_SP();
                char* module_name = AS_STRING(constants[name_index]);
                import_all(frame->closure, module_name);
                Value module_val = val_nil();
                env_get(frame->closure, module_name, (int)strlen(module_name), &module_val);
                PUSH(module_val);
                DISPATCH();
            }
            BC_OP_CLASS: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                SYNC_SP();
                ClassValue* class_val = class_create(AS_STRING(name), (int)strlen(AS_STRING(name)), NULL);
                class_val->defining_env = frame->closure;
                PUSH(val_class(class_val));
                DISPATCH();
            }
            BC_OP_METHOD: {
                uint16_t name_index = READ_U16();
                VM_CHECK_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                SYNC_SP();
                Value method_val = POP();
                Value class_val = PEEK(0);
                if (class_val.type != VAL_CLASS) {
                    result = vm_error("BC_OP_METHOD expects a class.");
                    goto done;
                }
                class_add_method(class_val.as.class_val, AS_STRING(name), (int)strlen(AS_STRING(name)), (void*)AS_FUNCTION(method_val));
                DISPATCH();
            }
            BC_OP_INHERIT: {
                Value child = POP();
                Value parent = POP();
                if (parent.type != VAL_CLASS || child.type != VAL_CLASS) { result = vm_error("Inheritance mismatch."); goto done; }
                child.as.class_val->parent = parent.as.class_val;
                PUSH(child);
                DISPATCH();
            }
            BC_OP_SETUP_TRY: {
                uint16_t handler_offset = READ_U16();
                if (vm.handler_count >= VM_HANDLER_MAX) { result = vm_error("Too many try blocks."); goto done; }
                vm.handlers[vm.handler_count].handler_ip_offset = (int)handler_offset;
                vm.handlers[vm.handler_count].stack_depth = (int)(sp - vm.stack);
                vm.handlers[vm.handler_count].env = frame->closure;
                vm.handler_count++;
                DISPATCH();
            }
            BC_OP_END_TRY:
                if (vm.handler_count > 0) vm.handler_count--;
                DISPATCH();
            BC_OP_RAISE: {
                Value exc_val = POP();
                if (IS_STRING(exc_val)) exc_val = val_exception(AS_STRING(exc_val));
                else if (IS_NUMBER(exc_val)) { char buf[64]; snprintf(buf, sizeof(buf), "%.14g", AS_NUMBER(exc_val)); exc_val = val_exception(buf); }
                if (vm.handler_count > 0) {
                    vm.handler_count--;
                    ip = frame->chunk->code + vm.handlers[vm.handler_count].handler_ip_offset;
                    sp = vm.stack + vm.handlers[vm.handler_count].stack_depth;
                    frame->closure = vm.handlers[vm.handler_count].env;
                    PUSH(exc_val);
                    DISPATCH();
                } else { result.value = val_nil(); result.is_throwing = 1; result.exception_value = exc_val; goto done; }
            }
            // GPU opcodes
            BC_OP_GPU_POLL_EVENTS: sgpu_poll_events(); DISPATCH();
            BC_OP_GPU_WINDOW_SHOULD_CLOSE: PUSH(val_bool(sgpu_window_should_close())); DISPATCH();
            BC_OP_GPU_GET_TIME: PUSH(val_number(sgpu_get_time())); DISPATCH();
            BC_OP_GPU_KEY_PRESSED: { Value key = POP(); PUSH(val_bool(sgpu_key_pressed((int)AS_NUMBER(key)))); DISPATCH(); }
            BC_OP_GPU_KEY_DOWN: { Value key = POP(); PUSH(val_bool(sgpu_key_down((int)AS_NUMBER(key)))); DISPATCH(); }
            BC_OP_GPU_MOUSE_POS: { double mx, my; sgpu_mouse_pos(&mx, &my); SYNC_SP(); Value d = val_dict(); dict_set(&d, "x", val_number(mx)); dict_set(&d, "y", val_number(my)); PUSH(d); DISPATCH(); }
            BC_OP_GPU_MOUSE_DELTA: { double dx, dy; sgpu_mouse_delta(&dx, &dy); SYNC_SP(); Value d = val_dict(); dict_set(&d, "x", val_number(dx)); dict_set(&d, "y", val_number(dy)); PUSH(d); DISPATCH(); }
            BC_OP_GPU_UPDATE_INPUT: sgpu_update_input(); DISPATCH();
            BC_OP_GPU_BEGIN_COMMANDS: { Value cmd = POP(); PUSH(val_bool(sgpu_begin_commands((int)AS_NUMBER(cmd)))); DISPATCH(); }
            BC_OP_GPU_END_COMMANDS: { Value cmd = POP(); PUSH(val_bool(sgpu_end_commands((int)AS_NUMBER(cmd)))); DISPATCH(); }
            BC_OP_GPU_CMD_BEGIN_RP: {
                Value clear = POP(), h = POP(), w = POP(), fb = POP(), rp = POP(), cmd = POP();
                float cr = 0, cg = 0, cb = 0, ca = 1;
                if (IS_ARRAY(clear) && clear.as.array->count >= 4) {
                    cr = (float)AS_NUMBER(clear.as.array->elements[0]); cg = (float)AS_NUMBER(clear.as.array->elements[1]);
                    cb = (float)AS_NUMBER(clear.as.array->elements[2]); ca = (float)AS_NUMBER(clear.as.array->elements[3]);
                }
                sgpu_cmd_begin_render_pass((int)AS_NUMBER(cmd), (int)AS_NUMBER(rp), (int)AS_NUMBER(fb), (int)AS_NUMBER(w), (int)AS_NUMBER(h), cr, cg, cb, ca);
                DISPATCH();
            }
            BC_OP_GPU_CMD_END_RP: { Value cmd = POP(); sgpu_cmd_end_render_pass((int)AS_NUMBER(cmd)); DISPATCH(); }
            BC_OP_GPU_CMD_DRAW: { Value fi = POP(), fv = POP(), inst = POP(), verts = POP(), cmd = POP(); sgpu_cmd_draw((int)AS_NUMBER(cmd), (int)AS_NUMBER(verts), (int)AS_NUMBER(inst), (int)AS_NUMBER(fv), (int)AS_NUMBER(fi)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_GP: { Value pipe = POP(), cmd = POP(); sgpu_cmd_bind_graphics_pipeline((int)AS_NUMBER(cmd), (int)AS_NUMBER(pipe)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_DS: { Value bp = POP(), set = POP(), layout = POP(), cmd = POP(); sgpu_cmd_bind_descriptor_set((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout), (int)AS_NUMBER(set), (int)AS_NUMBER(bp)); DISPATCH(); }
            BC_OP_GPU_CMD_SET_VP: { Value maxd = POP(), mind = POP(), vh = POP(), vw = POP(), vy = POP(), vx = POP(), cmd = POP(); sgpu_cmd_set_viewport((int)AS_NUMBER(cmd), (float)AS_NUMBER(vx), (float)AS_NUMBER(vy), (float)AS_NUMBER(vw), (float)AS_NUMBER(vh), (float)AS_NUMBER(mind), (float)AS_NUMBER(maxd)); DISPATCH(); }
            BC_OP_GPU_CMD_SET_SC: { Value sh = POP(), sw = POP(), sy = POP(), sx = POP(), cmd = POP(); sgpu_cmd_set_scissor((int)AS_NUMBER(cmd), (int)AS_NUMBER(sx), (int)AS_NUMBER(sy), (int)AS_NUMBER(sw), (int)AS_NUMBER(sh)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_VB: { Value buf = POP(), cmd = POP(); sgpu_cmd_bind_vertex_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_IB: { Value buf = POP(), cmd = POP(); sgpu_cmd_bind_index_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf)); DISPATCH(); }
            BC_OP_GPU_CMD_DRAW_IDX: { Value fi = POP(), vo = POP(), fidx = POP(), inst = POP(), idx_count = POP(), cmd = POP(); sgpu_cmd_draw_indexed((int)AS_NUMBER(cmd), (int)AS_NUMBER(idx_count), (int)AS_NUMBER(inst), (int)AS_NUMBER(fidx), (int)AS_NUMBER(vo), (int)AS_NUMBER(fi)); DISPATCH(); }
            BC_OP_GPU_SUBMIT_SYNC: { Value fence = POP(), signal = POP(), wait = POP(), cmd = POP(); PUSH(val_bool(sgpu_submit_with_sync((int)AS_NUMBER(cmd), (int)AS_NUMBER(wait), (int)AS_NUMBER(signal), (int)AS_NUMBER(fence)))); DISPATCH(); }
            BC_OP_GPU_ACQUIRE_IMG: { Value sem = POP(); int img_idx = 0; sgpu_acquire_next_image((int)AS_NUMBER(sem), &img_idx); PUSH(val_number(img_idx)); DISPATCH(); }
            BC_OP_GPU_PRESENT: { Value idx = POP(), sem = POP(); sgpu_present((int)AS_NUMBER(sem), (int)AS_NUMBER(idx)); DISPATCH(); }
            BC_OP_GPU_WAIT_FENCE: { Value timeout = POP(), fence = POP(); sgpu_wait_fence((int)AS_NUMBER(fence), AS_NUMBER(timeout)); DISPATCH(); }
            BC_OP_GPU_RESET_FENCE: { Value fence = POP(); sgpu_reset_fence((int)AS_NUMBER(fence)); DISPATCH(); }
            BC_OP_GPU_UPDATE_UNIFORM: {
                Value data = POP(), handle = POP();
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                    SYNC_SP(); float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                    for (int fi = 0; fi < data.as.array->count; fi++) floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    sgpu_update_uniform((int)AS_NUMBER(handle), floats, data.as.array->count); free(floats);
                }
                DISPATCH();
            }
            BC_OP_GPU_CMD_PUSH_CONST: {
                Value data = POP(), stages = POP(), layout = POP(), cmd = POP();
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                    SYNC_SP(); float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                    for (int fi = 0; fi < data.as.array->count; fi++) floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    sgpu_cmd_push_constants((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout), (int)AS_NUMBER(stages), floats, data.as.array->count); free(floats);
                }
                DISPATCH();
            }
            BC_OP_GPU_CMD_DISPATCH: { Value gz = POP(), gy = POP(), gx = POP(), cmd = POP(); sgpu_cmd_dispatch((int)AS_NUMBER(cmd), (int)AS_NUMBER(gx), (int)AS_NUMBER(gy), (int)AS_NUMBER(gz)); DISPATCH(); }

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
#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

ExecResult vm_execute_program(BytecodeProgram* program, Env* env) {
    ExecResult result = vm_normal(val_nil());
    if (program == NULL) return result;
    for (int i = 0; i < program->chunk_count; i++) {
        result = vm_execute_chunk(&program->chunks[i], env);
        if (result.is_throwing) return result;
    }
    return result;
}
