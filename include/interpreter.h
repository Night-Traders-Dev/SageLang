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
} ExecResult;

ExecResult interpret(Stmt* stmt, Env* env);
void init_stdlib(Env* env);

#endif