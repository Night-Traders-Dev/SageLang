#ifndef SAGE_VM_EXEC_H
#define SAGE_VM_EXEC_H

#include "bytecode.h"
#include "program.h"
#include "interpreter.h"

ExecResult vm_execute_chunk(BytecodeChunk* chunk, Env* env);
ExecResult vm_execute_program(BytecodeProgram* program, Env* env);
void vm_mark_roots(void* active_vm_head);

/* Call a bytecode-backed function or method from the AST evaluator. */
ExecResult sage_vm_call_function(Value callee, int arg_count, Value* args, Env* env);
ExecResult sage_vm_call_method(Value object, Method* method, int arg_count, Value* args, Env* env);

#endif
