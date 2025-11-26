// include/lexer.h
#ifndef SAGE_LEXER_H
#define SAGE_LEXER_H

#include "token.h"

void init_lexer(const char* source);
Token scan_token();

#endif
