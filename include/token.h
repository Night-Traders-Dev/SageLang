// include/token.h
#ifndef SAGE_TOKEN_H
#define SAGE_TOKEN_H

typedef enum {
    // Keywords
    TOKEN_LET, TOKEN_VAR, TOKEN_PROC, TOKEN_IF, TOKEN_ELSE,
    TOKEN_WHILE, TOKEN_FOR, TOKEN_RETURN, TOKEN_PRINT,
    TOKEN_AND, TOKEN_OR, TOKEN_IN,

    // Symbols & Operators
    TOKEN_LPAREN, TOKEN_RPAREN, TOKEN_PLUS, TOKEN_MINUS,
    TOKEN_STAR, TOKEN_SLASH, TOKEN_ASSIGN, TOKEN_EQ, TOKEN_NEQ,
    TOKEN_LT, TOKEN_GT, TOKEN_LTE, TOKEN_GTE, TOKEN_COLON,
    TOKEN_COMMA, TOKEN_LBRACKET, TOKEN_RBRACKET,


    // Literals & Identifiers
    TOKEN_IDENTIFIER, TOKEN_NUMBER, TOKEN_STRING, TOKEN_TRUE,
    TOKEN_FALSE, TOKEN_NIL,

    // Structural
    TOKEN_INDENT, TOKEN_DEDENT, TOKEN_NEWLINE,
    TOKEN_EOF, TOKEN_ERROR
} TokenType;

typedef struct {
    TokenType type;
    const char* start;
    int length;
    int line;
} Token;

#endif
