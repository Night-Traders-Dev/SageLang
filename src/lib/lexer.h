#ifndef LEXER_H
#define LEXER_H

#include <stddef.h>

#define MAX_TOKENS 1024
#define MAX_TOKEN_LENGTH 256

typedef enum {
    TOKEN_PRINT,
    TOKEN_STRING,
    TOKEN_EOF
} TokenType;

typedef struct {
    TokenType type;
    char *value;
} Token;

typedef struct {
    Token tokens[MAX_TOKENS];
    size_t count;
} TokenList;

TokenList lex(const char *source_code);
void free_tokens(TokenList *tokens);

#endif
