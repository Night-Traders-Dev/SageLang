#ifndef SAGE_VM_EXEC_H
#define SAGE_VM_EXEC_H

#include "bytecode.h"
#include "program.h"
#include "interpreter.h"

ExecResult vm_execute_chunk(BytecodeChunk* chunk, Env* env);
ExecResult vm_execute_program(BytecodeProgram* program, Env* env);
void vm_mark_roots(void);

#endif
