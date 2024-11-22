#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"

// Create a new AST node
ASTNode *create_node(NodeType type, const char *value) {
    ASTNode *node = (ASTNode *)malloc(sizeof(ASTNode));
    if (!node) {
        perror("Error allocating AST node");
        exit(EXIT_FAILURE);
    }

    node->type = type;

    // Ensure safe string copy with null-termination
    if (value) {
        strncpy(node->value, value, MAX_TOKEN_LENGTH - 1);
        node->value[MAX_TOKEN_LENGTH - 1] = '\0';  // Null-terminate
    } else {
        node->value[0] = '\0';  // Empty value if null
    }

    node->left = node->right = NULL;
    return node;
}

// Parse a variable declaration (let x = value)
ASTNode *parse_variable(TokenList *token_list, int *index) {
    if (*index + 2 >= token_list->count || strcmp(token_list->tokens[*index + 1], "=") != 0) {
        fprintf(stderr, "Error: Invalid variable declaration syntax.\n");
        exit(EXIT_FAILURE);
    }

    ASTNode *node = create_node(NODE_TYPE_VAR_DECL, token_list->tokens[*index]);  // "let x"
    node->left = create_node(NODE_TYPE_LITERAL, token_list->tokens[*index + 2]);  // "value"
    *index += 3;  // Move past "let x = value"

    return node;
}

// Parse an arithmetic expression (x + y, etc.)
ASTNode *parse_expression(TokenList *token_list, int *index) {
    ASTNode *node = create_node(NODE_TYPE_LITERAL, token_list->tokens[*index]);  // First operand
    (*index)++;

    while (*index < token_list->count && strchr("+-*/", token_list->tokens[*index][0])) {
        ASTNode *op_node = create_node(NODE_TYPE_OPERATOR, token_list->tokens[*index]);  // Operator
        (*index)++;

        op_node->left = node;  // Left operand
        op_node->right = create_node(NODE_TYPE_LITERAL, token_list->tokens[*index]);  // Right operand
        (*index)++;

        node = op_node;  // Replace current node with the operator node
    }

    return node;
}

// Parse a print statement (print x or print literal)
ASTNode *parse_print(TokenList *token_list, int *index) {
    if (*index + 1 >= token_list->count) {
        fprintf(stderr, "Error: Missing argument in print statement.\n");
        exit(EXIT_FAILURE);
    }

    ASTNode *node = create_node(NODE_TYPE_PRINT, "print");

    // Ensure the argument is parsed correctly
    const char *arg = token_list->tokens[*index + 1];
    if (arg[0] == '"' && arg[strlen(arg) - 1] == '"') {
        // It's a string literal
        char content[MAX_TOKEN_LENGTH];
        size_t length = strlen(arg) - 2;  // Exclude quotes
        if (length >= MAX_TOKEN_LENGTH) {
            fprintf(stderr, "Error: String literal too long.\n");
            exit(EXIT_FAILURE);
        }
        strncpy(content, arg + 1, length);
        content[length] = '\0';  // Null-terminate
        node->left = create_node(NODE_TYPE_LITERAL, content);
    } else {
        // Assume it's an expression
        node->left = parse_expression(token_list, index + 1);
    }

    *index += 2;  // Move past "print <arg>"
    return node;
}

// Parse a statement based on the first token
ASTNode *parse_statement(TokenList *token_list, int *index) {
    fprintf(stderr, "Debug: Parsing statement starting with '%s'\n", token_list->tokens[*index]);

    if (strcmp(token_list->tokens[*index], "let") == 0) {
        return parse_variable(token_list, index);
    } else if (strcmp(token_list->tokens[*index], "print") == 0) {
        return parse_print(token_list, index);
    } else {
        fprintf(stderr, "Error: Unsupported syntax '%s'.\n", token_list->tokens[*index]);
        exit(EXIT_FAILURE);
    }
}

// Parse the entire token list into an AST
ASTNode *parse(TokenList *token_list) {
    int index = 0;
    return parse_statement(token_list, &index);
}

// Free the memory of an AST
void free_ast(ASTNode *node) {
    if (!node) return;
    free_ast(node->left);
    free_ast(node->right);
    free(node);
}
