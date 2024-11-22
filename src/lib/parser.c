#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"
#include "utils.h"


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

ASTNode *parse_expression(const TokenList *tokens, size_t *index) {
    ASTNode *node = NULL;

    if (tokens->tokens[*index].type == TOKEN_IDENTIFIER || tokens->tokens[*index].type == TOKEN_NUMBER) {
        node = create_node(NODE_LITERAL, tokens->tokens[*index].value);
        (*index)++;
    }

    while (*index < tokens->count && tokens->tokens[*index].type == TOKEN_OPERATOR) {
        ASTNode *op_node = create_node(NODE_BINARY_OP, tokens->tokens[*index].value);
        (*index)++;
        op_node->left = node;
        op_node->right = parse_expression(tokens, index);
        node = op_node;
    }

    return node;
}

ASTNode *parse_statement(const TokenList *tokens, size_t *index) {
    if (tokens->tokens[*index].type == TOKEN_PRINT) {
        (*index)++;
        ASTNode *node = create_node(NODE_PRINT, NULL);
        node->left = parse_expression(tokens, index);
        return node;
    } else if (tokens->tokens[*index].type == TOKEN_IDENTIFIER && strcmp(tokens->tokens[*index].value, "let") == 0) {
        (*index)++;
        if (*index >= tokens->count || tokens->tokens[*index].type != TOKEN_IDENTIFIER) {
            fprintf(stderr, "Error: Expected identifier after 'let'\n");
            exit(EXIT_FAILURE);
        }
        ASTNode *node = create_node(NODE_VAR_DECL, tokens->tokens[*index].value);
        (*index)++;
        if (*index >= tokens->count || strcmp(tokens->tokens[*index].value, "=") != 0) {
            fprintf(stderr, "Error: Expected '=' in variable declaration\n");
            exit(EXIT_FAILURE);
        }
        (*index)++;
        node->left = parse_expression(tokens, index);
        return node;
    } else {
        fprintf(stderr, "Error: Unexpected token '%s'\n", tokens->tokens[*index].value);
        exit(EXIT_FAILURE);
    }
}

ASTNode *parse(const TokenList *tokens) {
    size_t index = 0;
    ASTNode *root = NULL;

    while (index < tokens->count) {
        ASTNode *stmt = parse_statement(tokens, &index);
        if (!root) {
            root = stmt;
        } else {
            ASTNode *seq_node = create_node(NODE_SEQUENCE, NULL);
            seq_node->left = root;
            seq_node->right = stmt;
            root = seq_node;
        }
    }

    return root;
}

void free_ast(ASTNode *node) {
    if (!node) return;
    free_ast(node->left);
    free_ast(node->right);
    free(node->value);
    free(node);
}
