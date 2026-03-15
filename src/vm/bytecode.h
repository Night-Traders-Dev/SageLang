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
    BC_OP_ARRAY_LEN
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
