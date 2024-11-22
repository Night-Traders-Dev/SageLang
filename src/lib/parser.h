#ifndef PARSER_H
#define PARSER_H

#include "tokenizer.h"

// Define node types for AST
typedef enum {
    NODE_TYPE_VAR_DECL,   // Variable declaration (let x = ...)
    NODE_TYPE_PRINT,      // Print statement (print ...)
    NODE_TYPE_OPERATOR,   // Operator (+, -, *, /)
    NODE_TYPE_LITERAL,    // Literal value (e.g., numbers, strings)
    NODE_TYPE_EXPR        // General expression (x + y, etc.)
} NodeType;

// AST Node Structure
typedef struct ASTNode {
    NodeType type;                   // Type of the node
    char value[MAX_TOKEN_LENGTH];    // Value (e.g., "10", "+")
    struct ASTNode *left;            // Left child
    struct ASTNode *right;           // Right child
} ASTNode;

// Function prototypes
ASTNode *parse(TokenList *token_list);
void free_ast(ASTNode *node);
ASTNode *create_node(NodeType type, const char *value);

#endif // PARSER_H
