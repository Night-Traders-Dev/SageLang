#ifndef SAGE_VM_RUNTIME_H
#define SAGE_VM_RUNTIME_H

#include "interpreter.h"

typedef enum {
    SAGE_RUNTIME_AST,
    SAGE_RUNTIME_BYTECODE,
    SAGE_RUNTIME_AUTO
} SageRuntimeMode;

const char* sage_runtime_mode_name(SageRuntimeMode mode);
int sage_runtime_parse_mode(const char* text, SageRuntimeMode* mode_out);
ExecResult sage_execute_stmt(Stmt* stmt, Env* env, SageRuntimeMode mode);

#endif
