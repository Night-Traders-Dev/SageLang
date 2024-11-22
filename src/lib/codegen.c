// src/lib/codegen.c

#include "codegen.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void generate_code(const ASTNode *node, FILE *file) {
    if (!node) return;

    static int has_included_headers = 0;
    static int has_main_started = 0;

    // Include headers only once
    if (!has_included_headers) {
        fprintf(file, "#include <stdio.h>\n");
        fprintf(file, "#include <stdlib.h>\n\n");
        has_included_headers = 1;
    }

    // Start main function only once
    if (!has_main_started) {
        fprintf(file, "int main() {\n");
        has_main_started = 1;
    }

    switch (node->type) {
        case NODE_VAR_DECL:
            fprintf(file, "    int %s = ", node->value);
            generate_code(node->left, file); // Emit the expression assigned to the variable
            fprintf(file, ";\n");
            break;

        case NODE_PRINT:
            fprintf(file, "    printf(\"%%d\\n\", ");
            generate_code(node->left, file); // Emit the expression to print
            fprintf(file, ");\n");
            break;

        case NODE_BINARY_OP:
            fprintf(file, "(");
            generate_code(node->left, file); // Emit the left operand
            fprintf(file, " %s ", node->value); // Emit the operator
            generate_code(node->right, file); // Emit the right operand
            fprintf(file, ")");
            break;

        case NODE_LITERAL:
            fprintf(file, "%s", node->value); // Emit the literal value
            break;

        case NODE_SEQUENCE:
            generate_code(node->left, file); // Emit the left (first) statement
            generate_code(node->right, file); // Emit the right (next) statement
            break;

        default:
            fprintf(stderr, "Error: Unsupported node type %d\n", node->type);
            exit(EXIT_FAILURE);
    }

    // Close main function if this is the last node
    if (node->type == NODE_SEQUENCE && !node->right && has_main_started) {
        fprintf(file, "    return 0;\n");
        fprintf(file, "}\n");
        has_main_started = 0; // Reset for potential future calls
    }

}
