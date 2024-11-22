// src/lib/codegen.c

#include "codegen.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "utils.h"

static int has_printed_imports = 0; // Track if the imports are already printed

void generate_code(ASTNode *node, FILE *output) {
    if (!node) return;

    // Print standard imports if not already printed
    if (!has_printed_imports) {
        fprintf(output, "#include <stdio.h>\n");
        fprintf(output, "#include <stdlib.h>\n");
        fprintf(output, "\n");
        fprintf(output, "int main() {\n");
        has_printed_imports = 1;
    }

    switch (node->type) {
        case NODE_VAR_DECL:
            fprintf(output, "    int %s = ", node->value);
            generate_code(node->left, output);
            fprintf(output, ";\n");
            break;

        case NODE_BINARY_OP:
            generate_code(node->left, output);
            fprintf(output, " %s ", node->value);
            generate_code(node->right, output);
            break;

        case NODE_LITERAL:
            if (node->value[0] == '"') {
                // If it's a string literal, print as is
                fprintf(output, "%s", node->value);
            } else {
                // Otherwise, print the numeric or identifier value
                fprintf(output, "%s", node->value);
            }
            break;

        case NODE_PRINT:
            if (node->left && node->left->value[0] == '"') {
                // If the print argument is a string literal
                fprintf(output, "    printf(\"%%s\\n\", ");
            } else {
                // Otherwise, assume it's an integer expression
                fprintf(output, "    printf(\"");
            }
            generate_code(node->left, output);
            fprintf(output, "\");\n");

            break;

        case NODE_SEQUENCE:
            generate_code(node->left, output);
            generate_code(node->right, output);
            break;

        case NODE_END:
            fprintf(output, "}\n");
            break;

        default:
            fprintf(stderr, "Error: Unsupported node type %d\n", node->type);
            exit(EXIT_FAILURE);
    }
}

void reset_codegen_state() {
    has_printed_imports = 0; // Reset imports flag for new compilations
}
