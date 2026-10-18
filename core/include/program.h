#ifndef SAGE_VM_PROGRAM_H
#define SAGE_VM_PROGRAM_H

#include <stddef.h>

#include "ast.h"
#include "bytecode.h"

typedef struct BytecodeFunction {
    char** params;
    int param_count;
    /* Default arguments, borrowed from the AST the module retains -- the same
     * lifetime convention as chunk->ast_stmts, so these are never freed here.
     *
     * A function carries its own defaults rather than relying on the bytecode
     * compiler's signature table. The table is keyed by bare name and is reset
     * per compilation unit, while each module is compiled separately and the
     * importer is compiled before its imports run -- so a call that crossed a
     * module boundary never found the callee's signature, had no defaults
     * substituted, and was rejected with "Arity mismatch". The same source
     * worked or failed depending only on whether the file had an import.
     *
     * NULL defaults mean "no defaults known", which is what a function read back
     * from a SAGEBC1 artifact gets: the format cannot carry AST, so such a
     * function demands exact arity rather than inventing one. */
    int required_count;
    Expr** defaults;
    BytecodeChunk chunk;
} BytecodeFunction;

typedef struct BytecodeProgram {
    BytecodeChunk* chunks;
    int chunk_count;
    int chunk_capacity;

    BytecodeFunction* functions;
    int function_count;
    int function_capacity;
} BytecodeProgram;

void bytecode_program_init(BytecodeProgram* program);
void bytecode_program_free(BytecodeProgram* program);
int bytecode_compile_program(BytecodeProgram* program, Stmt* statements, BytecodeCompileMode mode,
                             char* error, size_t error_size);
int bytecode_program_write_file(const BytecodeProgram* program, const char* output_path,
                                char* error, size_t error_size);
int bytecode_program_read_file(BytecodeProgram* program, const char* input_path,
                               char* error, size_t error_size);
int bytecode_program_validate(const BytecodeProgram* program, char* error, size_t error_size);
int bytecode_chunk_validate(const BytecodeChunk* chunk, int initial_stack,
                            const BytecodeProgram* program, char* error, size_t error_size);
int compile_source_to_vm_artifact(const char* source, const char* input_path, const char* output_path,
                                  int opt_level, int debug_info);

#endif
