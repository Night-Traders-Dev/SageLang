#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"

#ifndef strdup
char *strdup(const char *s) {
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy) {
        memcpy(copy, s, len);
    }
    return copy;
}
#endif

ASTNode *create_node(NodeType type, const char *value) {
    ASTNode *node = malloc(sizeof(ASTNode));
    if (!node) {
        perror("Error allocating AST node");
        exit(EXIT_FAILURE);
    }

    node->type = type;
    node->value = value ? strdup(value) : NULL;
    node->left = NULL;
    node->right = NULL;

    return node;
}

ASTNode *parse(const TokenList *tokens) {
    if (tokens->count == 0) {
        fprintf(stderr, "Error: Empty input\n");
        exit(EXIT_FAILURE);
    }

    size_t index = 0;

    if (tokens->tokens[index].type == TOKEN_PRINT) {
        if (tokens->tokens[index + 1].type == TOKEN_STRING) {
            ASTNode *node = create_node(NODE_PRINT, tokens->tokens[index + 1].value);
            return node;
        } else {
            fprintf(stderr, "Error: Expected string after 'print'\n");
            exit(EXIT_FAILURE);
        }
    }

    fprintf(stderr, "Error: Unsupported syntax\n");
    exit(EXIT_FAILURE);
}

void free_ast(ASTNode *node) {
    if (!node) return;
    free(node->value);
    free(node);
}
