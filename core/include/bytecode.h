#ifndef SAGE_VM_BYTECODE_H
#define SAGE_VM_BYTECODE_H

#include <stddef.h>
#include <stdint.h>
#include "ast.h"
#include "value.h"

typedef enum {
    BC_OP_CONSTANT,
    BC_OP_NIL,
    BC_OP_TRUE,
    BC_OP_FALSE,
    BC_OP_POP,
    BC_OP_GET_GLOBAL,
    BC_OP_DEFINE_GLOBAL,
    BC_OP_SET_GLOBAL,
    BC_OP_DEFINE_FUNCTION,
    BC_OP_GET_PROPERTY,
    BC_OP_SET_PROPERTY,
    BC_OP_GET_INDEX,
    BC_OP_SET_INDEX,
    BC_OP_SLICE,
    BC_OP_ADD,
    BC_OP_SUB,
    BC_OP_MUL,
    BC_OP_DIV,
    BC_OP_MOD,
    BC_OP_NEGATE,
    BC_OP_EQUAL,
    BC_OP_NOT_EQUAL,
    BC_OP_GREATER,
    BC_OP_GREATER_EQUAL,
    BC_OP_LESS,
    BC_OP_LESS_EQUAL,
    BC_OP_BIT_AND,
    BC_OP_BIT_OR,
    BC_OP_BIT_XOR,
    BC_OP_BIT_NOT,
    BC_OP_SHIFT_LEFT,
    BC_OP_SHIFT_RIGHT,
    BC_OP_NOT,
    BC_OP_TRUTHY,
    BC_OP_JUMP,
    BC_OP_JUMP_IF_FALSE,
    BC_OP_CALL,
    BC_OP_CALL_METHOD,
    BC_OP_ARRAY,
    BC_OP_TUPLE,
    BC_OP_DICT,
    BC_OP_PRINT,
    BC_OP_EXEC_AST_STMT,
    BC_OP_RETURN,
    BC_OP_PUSH_ENV,
    BC_OP_POP_ENV,
    BC_OP_DUP,
    BC_OP_ARRAY_LEN,
    BC_OP_BREAK,             // Jump to loop exit (patched after loop)
    BC_OP_CONTINUE,          // Jump to loop continue target
    BC_OP_LOOP_BACK,         // Unconditional backward jump (loop iteration)
    BC_OP_IMPORT,            // import module (name on constant pool)
    BC_OP_CLASS,             // define class (name, method_count, parent_name)
    BC_OP_METHOD,            // define method on class (name on constant pool)
    BC_OP_INHERIT,           // inherit from parent class
    BC_OP_SETUP_TRY,         // push exception handler (catch_target, finally_target)
    BC_OP_END_TRY,           // pop exception handler
    BC_OP_RAISE,             // raise exception (value on stack)
    // GPU hot-path opcodes (Phase 16: game engine optimization)
    BC_OP_GPU_POLL_EVENTS,         // gpu.poll_events() — no args, no result
    BC_OP_GPU_WINDOW_SHOULD_CLOSE, // gpu.window_should_close() -> bool
    BC_OP_GPU_GET_TIME,            // gpu.get_time() -> number
    BC_OP_GPU_KEY_PRESSED,         // gpu.key_pressed(key) -> bool (key on stack)
    BC_OP_GPU_KEY_DOWN,            // gpu.key_down(key) -> bool
    BC_OP_GPU_MOUSE_POS,           // gpu.mouse_pos() -> dict{x,y}
    BC_OP_GPU_MOUSE_DELTA,         // gpu.mouse_delta() -> dict{x,y}
    BC_OP_GPU_UPDATE_INPUT,        // gpu.update_input()
    BC_OP_GPU_BEGIN_COMMANDS,      // gpu.begin_commands(cmd)
    BC_OP_GPU_END_COMMANDS,        // gpu.end_commands(cmd)
    BC_OP_GPU_CMD_BEGIN_RP,        // gpu.cmd_begin_render_pass(cmd, rp, fb, w, h, clear)
    BC_OP_GPU_CMD_END_RP,          // gpu.cmd_end_render_pass(cmd)
    BC_OP_GPU_CMD_DRAW,            // gpu.cmd_draw(cmd, verts, inst, first_v, first_i)
    BC_OP_GPU_CMD_BIND_GP,         // gpu.cmd_bind_graphics_pipeline(cmd, pipe)
    BC_OP_GPU_CMD_BIND_DS,         // gpu.cmd_bind_descriptor_set(cmd, layout, set, bp)
    BC_OP_GPU_CMD_SET_VP,          // gpu.cmd_set_viewport(cmd, x, y, w, h, mind, maxd)
    BC_OP_GPU_CMD_SET_SC,          // gpu.cmd_set_scissor(cmd, x, y, w, h)
    BC_OP_GPU_CMD_BIND_VB,         // gpu.cmd_bind_vertex_buffer(cmd, buf)
    BC_OP_GPU_CMD_BIND_IB,         // gpu.cmd_bind_index_buffer(cmd, buf)
    BC_OP_GPU_CMD_DRAW_IDX,        // gpu.cmd_draw_indexed(cmd, idx_count, ...)
    BC_OP_GPU_SUBMIT_SYNC,         // gpu.submit_with_sync(cmd, wait, signal, fence)
    BC_OP_GPU_ACQUIRE_IMG,         // gpu.acquire_next_image(sem) -> number
    BC_OP_GPU_PRESENT,             // gpu.present(sem, img_idx)
    BC_OP_GPU_WAIT_FENCE,          // gpu.wait_fence(fence, timeout)
    BC_OP_GPU_RESET_FENCE,         // gpu.reset_fence(fence)
    BC_OP_GPU_UPDATE_UNIFORM,      // gpu.update_uniform(handle, data)
    BC_OP_GPU_CMD_PUSH_CONST,      // gpu.cmd_push_constants(cmd, layout, stages, data)
    BC_OP_GPU_CMD_DISPATCH         // gpu.cmd_dispatch(cmd, gx, gy, gz)
} BytecodeOp;

typedef enum {
    BYTECODE_COMPILE_HYBRID,
    BYTECODE_COMPILE_STRICT
} BytecodeCompileMode;

typedef int (*BytecodeBuildFunctionFn)(void* data, ProcStmt* proc,
                                       char* error, size_t error_size,
                                       int* function_index_out);

struct BytecodeProgram;

typedef struct {
    uint8_t* code;
    int code_count;
    int code_capacity;

    int* lines;
    int* columns;

    Value* constants;
    int constant_count;
    int constant_capacity;

    Stmt** ast_stmts;
    int ast_stmt_count;
    int ast_stmt_capacity;

    struct BytecodeProgram* program;
} BytecodeChunk;

void bytecode_chunk_init(BytecodeChunk* chunk);
void bytecode_chunk_free(BytecodeChunk* chunk);
int bytecode_compile_statement(BytecodeChunk* chunk, Stmt* stmt, char* error, size_t error_size);
int bytecode_compile_statement_mode(BytecodeChunk* chunk, Stmt* stmt, BytecodeCompileMode mode,
                                    char* error, size_t error_size);
int bytecode_compile_statement_with_functions(BytecodeChunk* chunk, Stmt* stmt, BytecodeCompileMode mode,
                                              BytecodeBuildFunctionFn build_function,
                                              void* build_function_data,
                                              char* error, size_t error_size);
int bytecode_compile_function_body(BytecodeChunk* chunk, Stmt* body,
                                   BytecodeBuildFunctionFn build_function,
                                   void* build_function_data,
                                   char* error, size_t error_size);

#endif
