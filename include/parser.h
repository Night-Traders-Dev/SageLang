#ifndef SAGE_PARSER_H
#define SAGE_PARSER_H

#include "ast.h"
#include "token.h"

typedef struct {
    Token current_token;
    Token previous_token;
} ParserState;

void parser_init(void);
Stmt* parse(void);
ParserState parser_get_state(void);
void parser_set_state(ParserState state);

#endif
