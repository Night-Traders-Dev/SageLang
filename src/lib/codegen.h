// src/lib/codegen.h

#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdio.h>
#include "parser.h"

void generate_code(ASTNode *node, FILE *output);
void reset_codegen_state();

#endif // CODEGEN_H
