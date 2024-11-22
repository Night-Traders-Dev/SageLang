#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../lib/parser.h"
#include "sage_risc.h"

void generate_riscv_code(ASTNode *node, FILE *file) {
    static int var_offset = 0;  // Offset for variable storage on the stack
    if (!node) {
        fprintf(stderr, "Error: Null AST node encountered.\n");
        exit(EXIT_FAILURE);
    }

    if (node->type == NODE_TYPE_VAR_DECL) {
        // Variable declaration: let x = value
        fprintf(file, "    li t0, %s\n", node->left->value);    // Load immediate value
        fprintf(file, "    sw t0, %d(sp)\n", var_offset);      // Store value on the stack
        var_offset += 4;                                       // Reserve 4 bytes for the variable
    } else if (node->type == NODE_TYPE_PRINT) {
        // Print statement: print x or print literal
        generate_riscv_code(node->left, file);
        fprintf(file, "    li a7, 64\n");                      // Syscall: write
        fprintf(file, "    ecall\n");
    } else if (node->type == NODE_TYPE_OPERATOR) {
        // Arithmetic operation: x + y, etc.
        generate_riscv_code(node->left, file);                 // Generate left operand
        fprintf(file, "    sw t0, %d(sp)\n", var_offset);      // Save result on stack
        var_offset += 4;
        generate_riscv_code(node->right, file);                // Generate right operand
        fprintf(file, "    lw t1, %d(sp)\n", var_offset - 4);  // Load left operand
        if (strcmp(node->value, "+") == 0) {
            fprintf(file, "    add t0, t1, t0\n");
        } else if (strcmp(node->value, "-") == 0) {
            fprintf(file, "    sub t0, t1, t0\n");
        } else if (strcmp(node->value, "*") == 0) {
            fprintf(file, "    mul t0, t1, t0\n");
        } else if (strcmp(node->value, "/") == 0) {
            fprintf(file, "    div t0, t1, t0\n");
        }
        var_offset -= 4;                                       // Reclaim stack space
    } else if (node->type == NODE_TYPE_LITERAL) {
        // Literal value: "5", "10", etc.
        fprintf(file, "    li t0, %s\n", node->value);
    } else {
        fprintf(stderr, "Error: Unsupported node type %d\n", node->type);
        exit(EXIT_FAILURE);
    }
}

void compile_riscv(const char *source_code, const char *output_file) {
    fprintf(stderr, "Debug: Starting RISC-V compilation.\n");
    fprintf(stderr, "Source code: %s\n", source_code);

    TokenList token_list;
    tokenize(source_code, &token_list);

    fprintf(stderr, "Debug: Tokens generated:\n");
    for (int i = 0; i < token_list.count; i++) {
        fprintf(stderr, "Token[%d]: %s\n", i, token_list.tokens[i]);
    }

    ASTNode *ast = parse(&token_list);

    fprintf(stderr, "Debug: AST generated.\n");

    FILE *file = fopen(output_file, "w");
    if (!file) {
        perror("Error writing RISC-V assembly");
        exit(EXIT_FAILURE);
    }

    fprintf(file, ".section .text\n.global main\nmain:\n");
    generate_riscv_code(ast, file);
    fprintf(file, "    ret\n");

    fclose(file);
    free_ast(ast);
    fprintf(stderr, "Debug: RISC-V compilation completed successfully.\n");
}
