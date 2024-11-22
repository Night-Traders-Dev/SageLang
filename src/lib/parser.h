// src/lib/parser.h

#ifndef PARSER_H
#define PARSER_H

#include "lexer.h"

typedef enum {
    NODE_PRINT,
    NODE_VAR_DECL,
    NODE_BINARY_OP,
    NODE_LITERAL,
    NODE_SEQUENCE,
    NODE_END
} NodeType;

typedef struct ASTNode {
    NodeType type;
    char *value;
    struct ASTNode *left;
    struct ASTNode *right;
} ASTNode;

ASTNode *parse(const TokenList *tokens);
ASTNode *parse_statement(const TokenList *tokens, size_t *index); // Declare the function
void free_ast(ASTNode *node);

#endif
