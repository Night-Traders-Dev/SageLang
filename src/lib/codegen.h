// src/lib/codegen.h

#ifndef CODEGEN_H
#define CODEGEN_H

#include "parser.h"
#include <stdio.h>

// Generates C code from the AST
void generate_code(const ASTNode *node, FILE *file);

#endif // CODEGEN_H
