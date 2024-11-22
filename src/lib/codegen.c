#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"

void generate_code(const ASTNode *node, FILE *output) {
    if (!node) return;

    static int initialized = 0;
    if (!initialized) {
        fprintf(output, "#include <stdio.h>\n");
        fprintf(output, "#include <stdlib.h>\n");
        initialized = 1;
    }

    switch (node->type) {
        case NODE_PRINT:
            fprintf(output, "printf(\"%%d\\n\", ");
            generate_code(node->left, output);  // Generate code for the value to print
            fprintf(output, ");\n");
            break;

        case NODE_VAR_DECL:
            fprintf(output, "int %s = ", node->value);  // Declare variable
            generate_code(node->left, output);         // Generate code for the assigned value
            fprintf(output, ";\n");
            break;

        case NODE_BINARY_OP:
            fprintf(output, "(");
            generate_code(node->left, output);   // Left operand
            fprintf(output, " %s ", node->value);  // Operator
            generate_code(node->right, output);  // Right operand
            fprintf(output, ")");
            break;

        case NODE_LITERAL:
            fprintf(output, "%s", node->value);  // Output literals as-is
            break;

        case NODE_SEQUENCE:
            generate_code(node->left, output);  // Generate the first statement
            generate_code(node->right, output); // Generate the next statement
            break;

        default:
            fprintf(stderr, "Error: Unknown node type %d\n", node->type);
            exit(EXIT_FAILURE);
    }
}
