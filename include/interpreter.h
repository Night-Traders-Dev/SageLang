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
    int is_throwing;        // PHASE 7: Exception throwing
    Value exception_value;  // PHASE 7: Exception being thrown
} ExecResult;

ExecResult interpret(Stmt* stmt, Env* env);
void init_stdlib(Env* env);

#endif