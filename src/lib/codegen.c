#include <stdio.h>
#include <stdlib.h>
#include "codegen.h"

void generate_code(const ASTNode *node, FILE *output) {
    fprintf(output, "#include <stdio.h>\n\nint main() {\n");

    if (node->type == NODE_PRINT) {
        fprintf(output, "    printf(\"%s\\n\");\n", node->value);
    }

    fprintf(output, "    return 0;\n}\n");
}
