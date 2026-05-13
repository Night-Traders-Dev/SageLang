// include/lexer.h
#ifndef SAGE_LEXER_H
#define SAGE_LEXER_H

#include "token.h"

#define MAX_INDENT_LEVELS 100

typedef struct {
    const char* start;
    const char* current;
    int line;
    int token_line;
    int at_beginning_of_line;
    const char* line_start;
    const char* token_line_start;
    const char* filename;
    int indent_stack[MAX_INDENT_LEVELS];
    int indent_stack_top;
    int pending_dedents;
    int bracket_depth;   // Tracks nesting of (), [], {} — suppresses INDENT/DEDENT/NEWLINE
} LexerState;

void init_lexer(const char* source, const char* filename);
Token scan_token(void);
LexerState lexer_get_state(void);
void lexer_set_state(LexerState state);

#endif
