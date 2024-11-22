#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"

ASTNode *parse(const TokenList *tokens) {
    if (tokens->count == 0) {
        fprintf(stderr, "Error: Empty input\n");
        exit(EXIT_FAILURE);
    }

    size_t index = 0;
    if (tokens->tokens[index].type == TOKEN_PRINT) {
        if (tokens->tokens[index + 1].type == TOKEN_STRING) {
            ASTNode *node = malloc(sizeof(ASTNode));
            node->type = NODE_PRINT;
            node->value = strdup(tokens->tokens[index + 1].value);
            node->left = node->right = NULL;
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
