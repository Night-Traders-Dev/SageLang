#ifndef SAGE_VM_PROGRAM_H
#define SAGE_VM_PROGRAM_H

#include <stddef.h>

#include "bytecode.h"

typedef struct BytecodeFunction {
    char** params;
    int param_count;
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
int compile_source_to_vm_artifact(const char* source, const char* input_path, const char* output_path,
                                  int opt_level, int debug_info);

#endif
