#ifndef SAGE_INTERPRETER_H
#define SAGE_INTERPRETER_H

#include "ast.h"
#include "env.h"

void interpret(Stmt* stmt, Env* env);
void init_stdlib(Env* env);

#endif
