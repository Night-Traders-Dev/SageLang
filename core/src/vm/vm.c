#include "vm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>

#include "module.h"
#include "repl.h"
#include "sage_thread.h"
#include "gc.h"
#include "gpu_api.h"
#include "interpreter.h"

extern __thread EnvRootNode* g_gc_root_stack;

typedef struct {
    int handler_ip_offset;
    int stack_depth;
    int frame_depth;
    Env* env;
} ExceptionHandler;

#define VM_STACK_MAX 65536
#define VM_MAX_LOCALS 256
#define VM_HANDLER_MAX 256

typedef struct ActiveVm {
    BytecodeChunk* chunk;
    Env* current_env;
    Value stack[VM_STACK_MAX];
    int stack_count;
    struct ActiveVm* parent;

    ExceptionHandler handlers[VM_HANDLER_MAX];
    int handler_count;
    
    // Generator support: set when executing a generator chunk
    GeneratorValue* current_generator;
    int is_generator_exec;
    int resume_ip_offset;  // For generator resume: start from this offset
    int resume_stack_count; // Stack depth to restore on resume
} ActiveVm;

static int vm_pop_handler_for_frame(ActiveVm* vm, int frame_depth, int* index_out) {
    if (vm == NULL || frame_depth < 0) return 0;
    for (int i = vm->handler_count - 1; i >= 0; i--) {
        if (vm->handlers[i].frame_depth == frame_depth) {
            if (index_out != NULL) *index_out = i;
            vm->handler_count = i;
            return 1;
        }
    }
    return 0;
}

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

    if (chunk->constant_count < 0 || chunk->constant_count > chunk->constant_capacity ||
        chunk->constant_count > 65536 || (chunk->constant_count > 0 && chunk->constants == NULL)) return;
    for (int i = 0; i < chunk->constant_count; i++) {
        gc_mark_value(chunk->constants[i]);
    }
}

static void vm_mark_program_constants(BytecodeProgram* program) {
    if (program == NULL) return;
    if (program->function_count < 0 || program->function_count > program->function_capacity ||
        program->chunk_count < 0 || program->chunk_count > program->chunk_capacity ||
        (program->function_count > 0 && program->functions == NULL) ||
        (program->chunk_count > 0 && program->chunks == NULL)) return;

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

        if (active->stack_count < 0 || active->stack_count > VM_STACK_MAX) return;
        for (int i = 0; i < active->stack_count; i++) {
            gc_mark_value(active->stack[i]);
        }

        if (active->handler_count < 0 || active->handler_count > VM_HANDLER_MAX) return;
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

static int vm_initial_stack_for_chunk(const BytecodeChunk* chunk) {
    if (chunk == NULL || chunk->program == NULL) return 0;
    const BytecodeProgram* program = chunk->program;
    if (program->function_count < 0 || program->function_count > program->function_capacity ||
        (program->function_count > 0 && program->functions == NULL)) return 0;
    for (int i = 0; i < program->function_count; i++) {
        if (&program->functions[i].chunk == chunk) return program->functions[i].param_count;
    }
    return 0;
}

static int vm_validate_chunk(const BytecodeChunk* chunk) {
    char error[256];
    return bytecode_chunk_validate(chunk, vm_initial_stack_for_chunk(chunk), chunk != NULL ? chunk->program : NULL,
                                   error, sizeof(error));
}

#define VM_CHECK_CONST(c, idx) \
    do { if ((c) == NULL || (c)->constants == NULL || \
        (uint64_t)(idx) >= (uint64_t)(c)->constant_count) { \
        result = vm_error("VM constant pool index out of bounds."); goto done; \
    } } while(0)

#define VM_CHECK_NAME_CONST(c, idx) \
    do { if ((c) == NULL || (c)->constants == NULL || \
        (uint64_t)(idx) >= (uint64_t)(c)->constant_count || \
        !IS_STRING((c)->constants[(uint16_t)(idx)])) { \
        result = vm_error("VM name constant is invalid."); goto done; \
    } } while(0)

#define VM_CHECK_AST(c, idx) \
    do { if ((c) == NULL || (c)->ast_stmts == NULL || \
        (uint64_t)(idx) >= (uint64_t)(c)->ast_stmt_count) { \
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
        if (callee.as.function == NULL) {
            return vm_error("Invalid function value.");
        }
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
#define VM_MAX_LOOP_ITERATIONS 1000000ULL

static int vm_consume_gas(long amount) {
    ThreadState* ts = gc_get_thread_state();
    if (ts == NULL || ts->gas_limit < 0) return 1;
    if (amount < 0 || ts->gas_used > LONG_MAX - amount) return 0;
    ts->gas_used += amount;
    return ts->gas_used <= ts->gas_limit;
}

// Forward declarations
static ExecResult vm_execute_generator(GeneratorValue* gen, Env* caller_env);

ExecResult vm_execute_chunk(BytecodeChunk* chunk, Env* env) {
    if (chunk == NULL) return vm_error("VM chunk is null.");
    if (env == NULL) return vm_error("VM environment is null.");
    if (!vm_validate_chunk(chunk)) return vm_error("Invalid VM bytecode artifact.");
    if (chunk->code_count == 0) return vm_normal(val_nil());
    if (sage_stack_danger()) return vm_error("VM call stack depth limit exceeded.");

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
    if (previous_vm != NULL &&
        (previous_vm->resume_ip_offset < 0 || previous_vm->resume_ip_offset > chunk->code_count ||
         previous_vm->resume_stack_count < 0 || previous_vm->resume_stack_count > VM_STACK_MAX)) {
        return vm_error("Invalid VM generator resume state.");
    }
    
    memset(&vm, 0, sizeof(vm));
    vm.chunk = chunk;
    vm.parent = previous_vm;

    g_active_vm = &vm;
    if (ts) ts->active_vm = g_active_vm;

    // Inherit generator state from parent VM (set by vm_execute_generator)
    if (previous_vm != NULL) {
        vm.current_generator = previous_vm->current_generator;
        vm.is_generator_exec = previous_vm->is_generator_exec;
        vm.resume_ip_offset = previous_vm->resume_ip_offset;
        vm.resume_stack_count = previous_vm->resume_stack_count;
    }

    CallFrame frames[MAX_FRAMES];
    int frame_count = 0;
    unsigned long long loop_iterations = 0;

    // Support generator resume: start from saved IP offset
    uint8_t* resume_start = chunk->code;
    int initial_stack_count = 0;
    if (vm.resume_ip_offset > 0) {
        resume_start = chunk->code + vm.resume_ip_offset;
        initial_stack_count = vm.resume_stack_count;
        vm.resume_ip_offset = 0;
        vm.resume_stack_count = 0;
    }

    CallFrame* frame = &frames[frame_count++];
    frame->chunk = chunk;
    frame->ip = resume_start;
    frame->ip_end = chunk->code + chunk->code_count;
    frame->slots = vm.stack;
    frame->closure = env;

    register Value* sp = vm.stack + initial_stack_count;
    register Value* constants = frame->chunk->constants;
    register uint8_t* ip = frame->ip;
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
        &&BC_OP_YIELD, &&BC_OP_CREATE_GENERATOR, &&BC_OP_GENERATOR_NEXT,
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
            if (ip >= ip_end) goto done; \
            if (*ip > BC_OP_GPU_CMD_DISPATCH) { \
                result = vm_error("VM opcode is out of bounds."); \
                goto done; \
            } \
            goto *dispatch_table[*ip++]; \
        } while (0)
#else
    #define DISPATCH() continue
#endif

#define VM_CHECK_IP(amount) \
    do { \
        if ((amount) < 0 || ip > ip_end || (size_t)(ip_end - ip) < (size_t)(amount)) { \
            result = vm_error("VM bytecode operand is truncated."); \
            goto done; \
        } \
    } while (0)

#define VM_CHECK_STACK(amount) \
    do { \
        long _vm_amount = (long)(amount); \
        if (_vm_amount < 0 || _vm_amount > VM_STACK_MAX || sp < vm.stack || \
            sp > vm.stack + VM_STACK_MAX || (size_t)(sp - vm.stack) < (size_t)_vm_amount) { \
            SYNC_SP(); \
            result = vm_error("VM stack underflow."); \
            goto done; \
        } \
    } while (0)

#define PUSH(val) \
    do { \
        Value _val = (val); \
        if (sp < vm.stack || sp >= vm.stack + VM_STACK_MAX) { \
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
#define READ_U16() (ip += 2, (uint16_t)(((unsigned int)ip[-2] << 8) | ip[-1]))

#ifdef __GNUC__
    DISPATCH();
#endif

    while (ip < ip_end) {
#ifndef __GNUC__
        BytecodeOp op = (BytecodeOp)*ip++;
        switch (op) {
#endif
            BC_OP_CONSTANT: {
                VM_CHECK_IP(2);
;
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
                 VM_CHECK_STACK(1);
                 (void)POP();
                DISPATCH();
             BC_OP_GET_LOCAL: {
                 VM_CHECK_IP(2);
;
                 uint16_t index = READ_U16();
                 if (index >= VM_MAX_LOCALS || frame->slots == NULL ||
                     frame->slots < vm.stack || frame->slots > vm.stack + VM_STACK_MAX ||
                     frame->slots > sp || (size_t)(sp - frame->slots) <= index) {
                     result = vm_error("VM local index is out of bounds.");
                     goto done;
                 }
                 PUSH(frame->slots[index]);
                 DISPATCH();
             }
              BC_OP_SET_LOCAL: {
                 VM_CHECK_STACK(1);
                 VM_CHECK_IP(2);
                  uint16_t index = READ_U16();
                 if (index >= VM_MAX_LOCALS || frame->slots == NULL ||
                     frame->slots < vm.stack || frame->slots > vm.stack + VM_STACK_MAX ||
                     frame->slots > sp || (size_t)(sp - frame->slots) <= index) {
                     result = vm_error("VM local index is out of bounds.");
                     goto done;
                 }
                 frame->slots[index] = PEEK(0);
                 DISPATCH();
             }
            BC_OP_GET_GLOBAL: {
                VM_CHECK_IP(2);
;
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
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
                 VM_CHECK_STACK(1);
                 VM_CHECK_IP(2);
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                Value value = POP();
                SYNC_SP();
                env_define(frame->closure, AS_STRING(name), (int)strlen(AS_STRING(name)), value);
                DISPATCH();
            }
             BC_OP_SET_GLOBAL: {
                 VM_CHECK_STACK(1);
                 VM_CHECK_IP(2);
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
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
                VM_CHECK_IP(2);
;
                 uint16_t name_index = READ_U16();
                VM_CHECK_IP(2);
;
                 uint16_t function_index = READ_U16();
                 VM_CHECK_NAME_CONST(frame->chunk, name_index);
                 if (frame->chunk->program == NULL ||
                     function_index >= frame->chunk->program->function_count) {
                     result = vm_error("Invalid compiled VM function reference.");
                     goto done;
                 }
                 Value name = constants[name_index];
                 SYNC_SP();
                 Value function = val_bytecode_function(&frame->chunk->program->functions[function_index], frame->closure);
                env_define(frame->closure, AS_STRING(name), (int)strlen(AS_STRING(name)), function);
                DISPATCH();
            }
             BC_OP_GET_PROPERTY: {
                 VM_CHECK_STACK(1);
                 VM_CHECK_IP(2);
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
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
                 VM_CHECK_STACK(2);
                 VM_CHECK_IP(2);
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
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
                 VM_CHECK_STACK(2);
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
                 VM_CHECK_STACK(3);
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
                 VM_CHECK_IP(2);
;
                 uint16_t function_index = READ_U16();
                 if (frame->chunk->program == NULL ||
                     function_index >= frame->chunk->program->function_count) {
                     result = vm_error("Invalid compiled VM function reference.");
                     goto done;
                 }
                 SYNC_SP();
                 Value function = val_bytecode_function(&frame->chunk->program->functions[function_index], frame->closure);
                PUSH(function);
                DISPATCH();
            }
             BC_OP_SLICE: {
                 VM_CHECK_STACK(3);
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
                 VM_CHECK_STACK(2);
                 BytecodeOp local_op = (BytecodeOp)ip[-1];
                Value right = POP();
                Value left = POP();
                Value out = val_nil();
                if (local_op == BC_OP_EQUAL || local_op == BC_OP_NOT_EQUAL) {
                    int equal = (left.type == right.type && left.type == VAL_NUMBER) ? (AS_NUMBER(left) == AS_NUMBER(right)) : values_equal(left, right);
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
                 VM_CHECK_STACK(1);
                 Value value = POP();
                if (!IS_NUMBER(value)) { result = vm_error("Unary '-' requires a number."); goto done; }
                PUSH(val_number(-AS_NUMBER(value)));
                DISPATCH();
            }
             BC_OP_BIT_NOT: {
                 VM_CHECK_STACK(1);
                 Value value = POP();
                if (!IS_NUMBER(value)) { result = vm_error("Bitwise NOT requires a number."); goto done; }
                PUSH(val_number((double)(~(long long)AS_NUMBER(value))));
                DISPATCH();
            }
             BC_OP_NOT: {
                 VM_CHECK_STACK(1);
                 Value value = POP();
                PUSH(val_bool(!vm_is_truthy(value)));
                DISPATCH();
            }
             BC_OP_TRUTHY: {
                 VM_CHECK_STACK(1);
                 Value value = POP();
                PUSH(val_bool(vm_is_truthy(value)));
                DISPATCH();
            }
             BC_OP_JUMP: {
                 VM_CHECK_IP(2);
;
                 uint16_t target = READ_U16();
                  if (target >= frame->chunk->code_count) {
                      result = vm_error("VM branch target is out of bounds.");
                      goto done;
                  }
                  if (target < (uint16_t)(ip - frame->chunk->code)) {
                      if (++loop_iterations > VM_MAX_LOOP_ITERATIONS) {
                          result = vm_error("VM loop iteration limit exceeded.");
                          goto done;
                      }
                      if (!vm_consume_gas(10)) {
                          result = vm_error("Out of gas");
                          goto done;
                      }
                  }
                  ip = frame->chunk->code + target;

                 DISPATCH();
             }
             BC_OP_JUMP_IF_FALSE: {
                 VM_CHECK_STACK(1);
                 VM_CHECK_IP(2);
                 uint16_t target = READ_U16();
                  if (target >= frame->chunk->code_count) {
                     result = vm_error("VM branch target is out of bounds.");
                     goto done;
                 }
                 if (!vm_is_truthy(PEEK(0))) ip = frame->chunk->code + target;
                 DISPATCH();
             }
            BC_OP_CALL: {
                 VM_CHECK_IP(1);
;
                 int arg_count = (int)READ_U8();
                 VM_CHECK_STACK(arg_count + 1);
                 Value callee = *(sp - 1 - arg_count);
                 if (callee.type == VAL_FUNCTION && callee.as.function != NULL && callee.as.function->is_vm) {
                     if (frame_count >= MAX_FRAMES) { result = vm_error("Stack overflow (max frames reached)."); goto done; }
                     BytecodeFunction* bcf = callee.as.function->vm_function;
                     if (bcf == NULL || bcf->chunk.code_count <= 0 || bcf->chunk.code == NULL) {
                         result = vm_error("Invalid compiled VM function.");
                         goto done;
                     }
                     if (arg_count != bcf->param_count) { result = vm_error("Arity mismatch."); goto done; }
                     if (!vm_validate_chunk(&bcf->chunk)) {
                         result = vm_error("Invalid compiled VM function bytecode.");
                         goto done;
                      }
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
                         int handler_index;
                         if (vm_pop_handler_for_frame(&vm, frame_count - 1, &handler_index)) {
                             int handler_offset = vm.handlers[handler_index].handler_ip_offset;
                             int handler_depth = vm.handlers[handler_index].stack_depth;
                             if (handler_offset < 0 || handler_offset >= frame->chunk->code_count ||
                                 handler_depth < 0 || handler_depth > VM_STACK_MAX) {
                                 result = vm_error("VM exception handler state is invalid.");
                                 goto done;
                             }
                             ip = frame->chunk->code + handler_offset;
                             sp = vm.stack + handler_depth;
                             frame->closure = vm.handlers[handler_index].env;
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
                VM_CHECK_IP(2);
;
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
                 VM_CHECK_IP(1);
;
                 int arg_count = (int)READ_U8();
                 VM_CHECK_STACK(arg_count + 1);
                Value object = *(sp - 1 - arg_count);
                Value* args = sp - arg_count;
                SYNC_SP();
                ExecResult call_result = call_method_value(object, AS_STRING(constants[name_index]), arg_count, args, frame->closure);
                sp -= (arg_count + 1);
                 if (call_result.is_throwing) {
                     int handler_index;
                     if (vm_pop_handler_for_frame(&vm, frame_count - 1, &handler_index)) {
                         int handler_offset = vm.handlers[handler_index].handler_ip_offset;
                         int handler_depth = vm.handlers[handler_index].stack_depth;
                         if (handler_offset < 0 || handler_offset >= frame->chunk->code_count ||
                             handler_depth < 0 || handler_depth > VM_STACK_MAX) {
                             result = vm_error("VM exception handler state is invalid.");
                             goto done;
                         }
                         ip = frame->chunk->code + handler_offset;
                         sp = vm.stack + handler_depth;
                         frame->closure = vm.handlers[handler_index].env;
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
                 VM_CHECK_IP(2);
;
                 uint16_t count = READ_U16();
                 VM_CHECK_STACK(count);
                 SYNC_SP();
                 Value array = val_array();
                for (int i = 0; i < (int)count; i++) array_push(&array, *(sp - (int)count + i));
                sp -= (int)count;
                PUSH(array);
                DISPATCH();
            }
             BC_OP_TUPLE: {
                 VM_CHECK_IP(2);
;
                 uint16_t count = READ_U16();
                 VM_CHECK_STACK(count);
                 SYNC_SP();
                 Value tuple = val_tuple(sp - (int)count, (int)count);
                sp -= (int)count;
                PUSH(tuple);
                DISPATCH();
            }
             BC_OP_DICT: {
                 VM_CHECK_IP(2);
;
                 uint16_t count = READ_U16();
                 VM_CHECK_STACK(count * 2);
                 SYNC_SP();
                 Value dictionary = val_dict();
                 Value* d_values = count == 0 ? NULL : SAGE_ALLOC(sizeof(Value) * (size_t)count * 2);
                 if (count > 0 && d_values == NULL) { result = vm_error("VM dictionary allocation failed."); goto done; }
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
                 VM_CHECK_STACK(1);
                 Value value = POP();
                print_value(value);
                printf("\n");
                DISPATCH();
            }
            BC_OP_EXEC_AST_STMT: {
                VM_CHECK_IP(2);
;
                 uint16_t stmt_index = READ_U16();
                VM_CHECK_AST(frame->chunk, stmt_index);
                SYNC_SP();
                 ExecResult ast_result = interpret(frame->chunk->ast_stmts[stmt_index], frame->closure);
                if (ast_result.is_throwing) { result = ast_result; goto done; }
                PUSH(ast_result.value);
                DISPATCH();
            }
            BC_OP_RETURN: {
                Value res = sp > vm.stack ? POP() : val_nil();
                 if (frame_count > 1) {
                     int returning_frame_depth = frame_count - 1;
                     while (vm.handler_count > 0 &&
                            vm.handlers[vm.handler_count - 1].frame_depth >= returning_frame_depth)
                         vm.handler_count--;
                     // Restore caller state
                     frame->ip = ip; // Save current IP before popping


                    // Drop the frame's args AND the callee slot that sits just
                    // below them (the CALL handler keeps it in place), matching
                    // the native-call path which pops (arg_count + 1) values.
                    sp = frame->slots - 1;
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
                VM_CHECK_IP(1);
;
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
                 result = vm_error("Unexpected loop control opcode.");
                 goto done;
             BC_OP_LOOP_BACK: {
                 if (++loop_iterations > VM_MAX_LOOP_ITERATIONS) {
                     result = vm_error("VM loop iteration limit exceeded.");
                     goto done;
                 }
                 if (!vm_consume_gas(10)) {
                     result = vm_error("Out of gas");
                     goto done;
                 }
                 VM_CHECK_IP(2);
;
                 uint16_t offset = READ_U16();
                 long target = (long)(ip - frame->chunk->code) - offset;
                 if (target < 0 || target >= frame->chunk->code_count) {
                     result = vm_error("VM loop target is out of bounds.");
                     goto done;
                 }
                 ip = frame->chunk->code + target;
                 DISPATCH();
             }
            BC_OP_IMPORT: {
                VM_CHECK_IP(2);
;
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
                SYNC_SP();
                char* module_name = AS_STRING(constants[name_index]);
                import_all(frame->closure, module_name);
                Value module_val = val_nil();
                env_get(frame->closure, module_name, (int)strlen(module_name), &module_val);
                PUSH(module_val);
                DISPATCH();
            }
            BC_OP_CLASS: {
                VM_CHECK_IP(2);
;
                 uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                SYNC_SP();
                ClassValue* class_val = class_create(AS_STRING(name), (int)strlen(AS_STRING(name)), NULL);
                class_val->defining_env = frame->closure;
                PUSH(val_class(class_val));
                DISPATCH();
            }
              BC_OP_METHOD: {
                 VM_CHECK_STACK(1);
                 VM_CHECK_IP(2);
                  uint16_t name_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
                Value name = constants[name_index];
                SYNC_SP();
                 Value method_val = POP();
                 Value class_val = PEEK(0);
                 if (class_val.type != VAL_CLASS || !IS_FUNCTION(method_val)) {
                     result = vm_error("BC_OP_METHOD expects a class and function.");
                     goto done;
                 }
                 class_add_method(class_val.as.class_val, AS_STRING(name), (int)strlen(AS_STRING(name)), (void*)AS_FUNCTION(method_val));
                DISPATCH();
            }
             BC_OP_INHERIT: {
                 VM_CHECK_STACK(2);
                 Value child = POP();
                Value parent = POP();
                if (parent.type != VAL_CLASS || child.type != VAL_CLASS) { result = vm_error("Inheritance mismatch."); goto done; }
                child.as.class_val->parent = parent.as.class_val;
                PUSH(child);
                DISPATCH();
            }
             BC_OP_SETUP_TRY: {
                 VM_CHECK_IP(2);
;
                 uint16_t handler_offset = READ_U16();
                 if (handler_offset >= frame->chunk->code_count) {
                     result = vm_error("VM exception handler target is out of bounds.");
                     goto done;
                 }
                 if (vm.handler_count >= VM_HANDLER_MAX) { result = vm_error("Too many try blocks."); goto done; }
                 vm.handlers[vm.handler_count].handler_ip_offset = (int)handler_offset;
                vm.handlers[vm.handler_count].stack_depth = (int)(sp - vm.stack);
                vm.handlers[vm.handler_count].frame_depth = frame_count - 1;
                vm.handlers[vm.handler_count].env = frame->closure;
                vm.handler_count++;
                DISPATCH();
            }
             BC_OP_END_TRY:
                 if (vm.handler_count > 0 &&
                     vm.handlers[vm.handler_count - 1].frame_depth == frame_count - 1)
                     vm.handler_count--;
                 DISPATCH();
              BC_OP_RAISE: {

                 VM_CHECK_STACK(1);
                 Value exc_val = POP();
                if (IS_STRING(exc_val)) exc_val = val_exception(AS_STRING(exc_val));
                else if (IS_NUMBER(exc_val)) { char buf[64]; snprintf(buf, sizeof(buf), "%.14g", AS_NUMBER(exc_val)); exc_val = val_exception(buf); }
                  int handler_index;
                  if (vm_pop_handler_for_frame(&vm, frame_count - 1, &handler_index)) {
                      int handler_offset = vm.handlers[handler_index].handler_ip_offset;
                      int handler_depth = vm.handlers[handler_index].stack_depth;
                      if (handler_offset < 0 || handler_offset >= frame->chunk->code_count ||
                          handler_depth < 0 || handler_depth > VM_STACK_MAX) {
                          result = vm_error("VM exception handler state is invalid.");
                          goto done;
                      }
                      ip = frame->chunk->code + handler_offset;
                      sp = vm.stack + handler_depth;
                      frame->closure = vm.handlers[handler_index].env;
                      PUSH(exc_val);
                     DISPATCH();
                 } else { result.value = val_nil(); result.is_throwing = 1; result.exception_value = exc_val; goto done; }

            }
            // GPU opcodes
            BC_OP_GPU_POLL_EVENTS: sgpu_poll_events(); DISPATCH();
            BC_OP_GPU_WINDOW_SHOULD_CLOSE: PUSH(val_bool(sgpu_window_should_close())); DISPATCH();
            BC_OP_GPU_GET_TIME: PUSH(val_number(sgpu_get_time())); DISPATCH();
                         BC_OP_GPU_KEY_PRESSED: { VM_CHECK_STACK(1); Value key = POP(); PUSH(val_bool(sgpu_key_pressed((int)AS_NUMBER(key)))); DISPATCH(); }
                         BC_OP_GPU_KEY_DOWN: { VM_CHECK_STACK(1); Value key = POP(); PUSH(val_bool(sgpu_key_down((int)AS_NUMBER(key)))); DISPATCH(); }
            BC_OP_GPU_MOUSE_POS: { double mx, my; sgpu_mouse_pos(&mx, &my); SYNC_SP(); Value d = val_dict(); dict_set(&d, "x", val_number(mx)); dict_set(&d, "y", val_number(my)); PUSH(d); DISPATCH(); }
            BC_OP_GPU_MOUSE_DELTA: { double dx, dy; sgpu_mouse_delta(&dx, &dy); SYNC_SP(); Value d = val_dict(); dict_set(&d, "x", val_number(dx)); dict_set(&d, "y", val_number(dy)); PUSH(d); DISPATCH(); }
            BC_OP_GPU_UPDATE_INPUT: sgpu_update_input(); DISPATCH();
                         BC_OP_GPU_BEGIN_COMMANDS: { VM_CHECK_STACK(1); Value cmd = POP(); PUSH(val_bool(sgpu_begin_commands((int)AS_NUMBER(cmd)))); DISPATCH(); }
                         BC_OP_GPU_END_COMMANDS: { VM_CHECK_STACK(1); Value cmd = POP(); PUSH(val_bool(sgpu_end_commands((int)AS_NUMBER(cmd)))); DISPATCH(); }
            BC_OP_GPU_CMD_BEGIN_RP: {
                 VM_CHECK_STACK(6);
                Value clear = POP(), h = POP(), w = POP(), fb = POP(), rp = POP(), cmd = POP();
                float cr = 0, cg = 0, cb = 0, ca = 1;
                if (IS_ARRAY(clear) && clear.as.array->count >= 4) {
                    cr = (float)AS_NUMBER(clear.as.array->elements[0]); cg = (float)AS_NUMBER(clear.as.array->elements[1]);
                    cb = (float)AS_NUMBER(clear.as.array->elements[2]); ca = (float)AS_NUMBER(clear.as.array->elements[3]);
                }
                sgpu_cmd_begin_render_pass((int)AS_NUMBER(cmd), (int)AS_NUMBER(rp), (int)AS_NUMBER(fb), (int)AS_NUMBER(w), (int)AS_NUMBER(h), cr, cg, cb, ca);
                DISPATCH();
            }
            BC_OP_GPU_CMD_END_RP: { VM_CHECK_STACK(1); Value cmd = POP(); sgpu_cmd_end_render_pass((int)AS_NUMBER(cmd)); DISPATCH(); }
            BC_OP_GPU_CMD_DRAW: { VM_CHECK_STACK(5); Value fi = POP(), fv = POP(), inst = POP(), verts = POP(), cmd = POP(); sgpu_cmd_draw((int)AS_NUMBER(cmd), (int)AS_NUMBER(verts), (int)AS_NUMBER(inst), (int)AS_NUMBER(fv), (int)AS_NUMBER(fi)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_GP: { VM_CHECK_STACK(2); Value pipe = POP(), cmd = POP(); sgpu_cmd_bind_graphics_pipeline((int)AS_NUMBER(cmd), (int)AS_NUMBER(pipe)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_DS: { VM_CHECK_STACK(4); Value bp = POP(), set = POP(), layout = POP(), cmd = POP(); sgpu_cmd_bind_descriptor_set((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout), (int)AS_NUMBER(set), (int)AS_NUMBER(bp)); DISPATCH(); }
            BC_OP_GPU_CMD_SET_VP: { VM_CHECK_STACK(7); Value maxd = POP(), mind = POP(), vh = POP(), vw = POP(), vy = POP(), vx = POP(), cmd = POP(); sgpu_cmd_set_viewport((int)AS_NUMBER(cmd), (float)AS_NUMBER(vx), (float)AS_NUMBER(vy), (float)AS_NUMBER(vw), (float)AS_NUMBER(vh), (float)AS_NUMBER(mind), (float)AS_NUMBER(maxd)); DISPATCH(); }
            BC_OP_GPU_CMD_SET_SC: { VM_CHECK_STACK(5); Value sh = POP(), sw = POP(), sy = POP(), sx = POP(), cmd = POP(); sgpu_cmd_set_scissor((int)AS_NUMBER(cmd), (int)AS_NUMBER(sx), (int)AS_NUMBER(sy), (int)AS_NUMBER(sw), (int)AS_NUMBER(sh)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_VB: { VM_CHECK_STACK(2); Value buf = POP(), cmd = POP(); sgpu_cmd_bind_vertex_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf)); DISPATCH(); }
            BC_OP_GPU_CMD_BIND_IB: { VM_CHECK_STACK(2); Value buf = POP(), cmd = POP(); sgpu_cmd_bind_index_buffer((int)AS_NUMBER(cmd), (int)AS_NUMBER(buf)); DISPATCH(); }
            BC_OP_GPU_CMD_DRAW_IDX: { VM_CHECK_STACK(6); Value fi = POP(), vo = POP(), fidx = POP(), inst = POP(), idx_count = POP(), cmd = POP(); sgpu_cmd_draw_indexed((int)AS_NUMBER(cmd), (int)AS_NUMBER(idx_count), (int)AS_NUMBER(inst), (int)AS_NUMBER(fidx), (int)AS_NUMBER(vo), (int)AS_NUMBER(fi)); DISPATCH(); }
            BC_OP_GPU_SUBMIT_SYNC: { VM_CHECK_STACK(4); Value fence = POP(), signal = POP(), wait = POP(), cmd = POP(); PUSH(val_bool(sgpu_submit_with_sync((int)AS_NUMBER(cmd), (int)AS_NUMBER(wait), (int)AS_NUMBER(signal), (int)AS_NUMBER(fence)))); DISPATCH(); }
            BC_OP_GPU_ACQUIRE_IMG: { VM_CHECK_STACK(1); Value sem = POP(); int img_idx = 0; sgpu_acquire_next_image((int)AS_NUMBER(sem), &img_idx); PUSH(val_number(img_idx)); DISPATCH(); }
            BC_OP_GPU_PRESENT: { VM_CHECK_STACK(2); Value idx = POP(), sem = POP(); sgpu_present((int)AS_NUMBER(sem), (int)AS_NUMBER(idx)); DISPATCH(); }
            BC_OP_GPU_WAIT_FENCE: { VM_CHECK_STACK(2); Value timeout = POP(), fence = POP(); sgpu_wait_fence((int)AS_NUMBER(fence), AS_NUMBER(timeout)); DISPATCH(); }
            BC_OP_GPU_RESET_FENCE: { VM_CHECK_STACK(1); Value fence = POP(); sgpu_reset_fence((int)AS_NUMBER(fence)); DISPATCH(); }
            BC_OP_GPU_UPDATE_UNIFORM: { VM_CHECK_STACK(2);
                Value data = POP(), handle = POP();
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                     SYNC_SP(); float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                     if (floats == NULL) { result = vm_error("VM uniform allocation failed."); goto done; }
                     for (int fi = 0; fi < data.as.array->count; fi++) floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    sgpu_update_uniform((int)AS_NUMBER(handle), floats, data.as.array->count); free(floats);
                }
                DISPATCH();
            }
            BC_OP_GPU_CMD_PUSH_CONST: { VM_CHECK_STACK(4);
                Value data = POP(), stages = POP(), layout = POP(), cmd = POP();
                if (IS_ARRAY(data) && data.as.array->count > 0) {
                     SYNC_SP(); float* floats = SAGE_ALLOC(sizeof(float) * (size_t)data.as.array->count);
                     if (floats == NULL) { result = vm_error("VM uniform allocation failed."); goto done; }
                     for (int fi = 0; fi < data.as.array->count; fi++) floats[fi] = (float)AS_NUMBER(data.as.array->elements[fi]);
                    sgpu_cmd_push_constants((int)AS_NUMBER(cmd), (int)AS_NUMBER(layout), (int)AS_NUMBER(stages), floats, data.as.array->count); free(floats);
                }
                DISPATCH();
            }
            BC_OP_GPU_CMD_DISPATCH: { VM_CHECK_STACK(4); Value gz = POP(), gy = POP(), gx = POP(), cmd = POP(); sgpu_cmd_dispatch((int)AS_NUMBER(cmd), (int)AS_NUMBER(gx), (int)AS_NUMBER(gy), (int)AS_NUMBER(gz)); DISPATCH(); }

            // --- Generator opcodes ---
             BC_OP_YIELD: {
                 VM_CHECK_STACK(1);
                 Value yielded = POP();
                SYNC_SP();
                // Save state for generator resumption (if in generator context)
                if (vm.current_generator != NULL) {
                    vm.current_generator->saved_ip_offset = (int)(ip - frame->chunk->code);
                    vm.current_generator->saved_stack_count = vm.stack_count;
                    vm.current_generator->gen_env = frame->closure;
                    vm.current_generator->has_resume_target = 1;
                }
                PUSH(yielded);
                result = vm_normal(yielded);
                goto done;
            }
            BC_OP_CREATE_GENERATOR: {
                VM_CHECK_IP(2);
;
                 uint16_t name_index = READ_U16();
                VM_CHECK_IP(2);
;
                 uint16_t function_index = READ_U16();
                VM_CHECK_NAME_CONST(frame->chunk, name_index);
                (void)name_index;
                BytecodeProgram* program = frame->chunk->program;
                if (program == NULL || function_index >= program->function_count) {
                    result = vm_error("Invalid generator function index.");
                    goto done;
                }
                Value gen_val = val_generator(NULL, NULL, 0, frame->closure);
                GeneratorValue* gen = gen_val.as.generator;
                gen->is_started = 0;
                gen->is_exhausted = 0;
                gen->has_resume_target = 0;
                gen->saved_ip_offset = 0;
                gen->saved_stack_count = 0;
                gen->vm_function_index = function_index;
                PUSH(gen_val);
                DISPATCH();
            }
             BC_OP_GENERATOR_NEXT: {
                 VM_CHECK_STACK(1);
                 Value gen_val = POP();
                 if (gen_val.type != VAL_GENERATOR) {
                     result = vm_error("GENERATOR_NEXT called on non-generator value.");
                     goto done;
                 }
                 GeneratorValue* gen = gen_val.as.generator;
                 if (gen == NULL) {
                     result = vm_error("Invalid generator value.");
                     goto done;
                 }
                 if (gen->is_exhausted) {
                     PUSH(val_nil());
                     DISPATCH();
                 }
                 // Execute/resume generator
                 ExecResult gen_result = vm_execute_generator(gen, frame->closure);
                 if (gen_result.is_throwing) { result = gen_result; goto done; }
                 PUSH(gen_result.value);
                 DISPATCH();
             }
#ifndef __GNUC__
             default:
                 result = vm_error("VM opcode is out of bounds.");
                 goto done;
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

static ExecResult vm_execute_generator(GeneratorValue* gen, Env* caller_env) {
    if (gen == NULL) return vm_error("Invalid generator value.");
    BytecodeChunk* gen_chunk = NULL;
    int fn_idx = gen->vm_function_index;
    if (fn_idx >= 0 && g_active_vm && g_active_vm->chunk && g_active_vm->chunk->program) {
        BytecodeProgram* program = g_active_vm->chunk->program;
        if (fn_idx < program->function_count) {
            gen_chunk = &program->functions[fn_idx].chunk;
        }
    }
    if (gen_chunk == NULL && gen->body != NULL) {
        if (!gen->is_started) {
            gen->gen_env = env_create(gen->closure ? gen->closure : caller_env);
            gen->is_started = 1;
        }
        ExecResult ast_result = interpret((Stmt*)gen->body, gen->gen_env);
        if (ast_result.is_yielding) {
            gen->current_stmt = ast_result.next_stmt;
            gen->has_resume_target = 1;
            return vm_normal(ast_result.value);
        }
        gen->is_exhausted = 1;
        gen->has_resume_target = 0;
        if (ast_result.is_throwing) return ast_result;
        return vm_normal(val_nil());
    }
    if (gen_chunk == NULL) return vm_normal(val_nil());
    Env* gen_env = gen->gen_env ? gen->gen_env : env_create(gen->closure ? gen->closure : caller_env);
    gen->is_started = 1;
    ActiveVm gen_vm;
    memset(&gen_vm, 0, sizeof(gen_vm));
    gen_vm.chunk = gen_chunk;
    gen_vm.parent = g_active_vm;
    gen_vm.current_generator = gen;
    gen_vm.is_generator_exec = 1;
    if (gen->has_resume_target && gen->saved_ip_offset > 0) {
        gen_vm.resume_ip_offset = gen->saved_ip_offset;
        gen_vm.resume_stack_count = gen->saved_stack_count;
    }
    ActiveVm* previous_vm = g_active_vm;
    g_active_vm = &gen_vm;
    ExecResult result = vm_execute_chunk(gen_chunk, gen_env);
    g_active_vm = previous_vm;
    // YIELD handler saved state directly to gen via vm.current_generator.
    // Detect yield: gen->has_resume_target is set by YIELD handler.
    if (gen->has_resume_target && !result.is_throwing) {
        return result;
    }
    gen->is_exhausted = 1;
    gen->has_resume_target = 0;
    return result;
}

ExecResult vm_execute_program(BytecodeProgram* program, Env* env) {
    ExecResult result = vm_normal(val_nil());
    if (program == NULL) return vm_error("VM program is null.");
    if (!bytecode_program_validate(program, NULL, 0)) {
        return vm_error("Invalid VM bytecode artifact.");
    }
    for (int i = 0; i < program->chunk_count; i++) {
        result = vm_execute_chunk(&program->chunks[i], env);
        if (result.is_throwing) return result;
    }
    return result;
}
