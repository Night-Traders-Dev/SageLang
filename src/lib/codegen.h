#ifndef CODEGEN_H
#define CODEGEN_H

#include "parser.h"

void generate_code(const ASTNode *node, FILE *output);

#endif
