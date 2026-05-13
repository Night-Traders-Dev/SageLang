#ifndef SAGE_INTERPRETER_H
#define SAGE_INTERPRETER_H

#include "ast.h"
#include "env.h"
#include "value.h"

typedef struct {
    Value value;
    int is_returning;
    int is_breaking;
    int is_continuing;
    int is_throwing;
    Value exception_value;
    int is_yielding;  // NEW: For generator yield support
    void* next_stmt;  // NEW: For generator resumption point
    
    // Phase 2: Gas metering
    long gas_used;
    long gas_limit;
} ExecResult;

ExecResult interpret(Stmt* stmt, Env* env);
void init_stdlib(Env* env);

#endif