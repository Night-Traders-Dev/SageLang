#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../lib/parser.h"
#include "sage_arm.h"

void generate_arm_code(ASTNode *node, FILE *file, FILE *data_file) {
    static int string_counter = 0;  // Counter for unique string labels
    static int var_offset = 0;     // Offset for variable storage on the stack

    if (!node) {
        fprintf(stderr, "Error: Null AST node encountered.\n");
        exit(EXIT_FAILURE);
    }

    if (node->type == NODE_TYPE_VAR_DECL) {
        // Variable declaration: let x = value
        fprintf(file, "    mov x0, #%s\n", node->left->value);  // Load immediate value
        fprintf(file, "    str x0, [sp, #%d]\n", var_offset);   // Store value at offset
        var_offset += 8;                                       // Reserve 8 bytes for the variable
        var_offset = (var_offset + 15) & ~15;                  // Align to 16 bytes
    } else if (node->type == NODE_TYPE_PRINT) {
        // Print statement: print x or print literal
        generate_arm_code(node->left, file, data_file);
        fprintf(file, "    mov x8, 64\n");  // Syscall: write
        fprintf(file, "    svc 0\n");
    } else if (node->type == NODE_TYPE_OPERATOR) {
        // Arithmetic operation: x + y, etc.
        generate_arm_code(node->left, file, data_file);                   // Generate left operand
        fprintf(file, "    str x0, [sp, #%d]\n", var_offset);             // Save result on stack
        var_offset += 8;
        generate_arm_code(node->right, file, data_file);                  // Generate right operand
        fprintf(file, "    ldr x1, [sp, #%d]\n", var_offset - 8);         // Load left operand
        if (strcmp(node->value, "+") == 0) {
            fprintf(file, "    add x0, x1, x0\n");
        } else if (strcmp(node->value, "-") == 0) {
            fprintf(file, "    sub x0, x1, x0\n");
        } else if (strcmp(node->value, "*") == 0) {
            fprintf(file, "    mul x0, x1, x0\n");
        } else if (strcmp(node->value, "/") == 0) {
            fprintf(file, "    sdiv x0, x1, x0\n");
        }
        var_offset -= 8;  // Reclaim stack space
    } else if (node->type == NODE_TYPE_LITERAL) {
        // Literal value: numbers or strings
        if (node->value[0] == '"') {
            // It's a string literal
            char label[32];
            snprintf(label, sizeof(label), "str_%d", string_counter++);
            fprintf(stderr, "Debug: Writing string literal '%s' to .data with label '%s'\n", node->value, label);
            fprintf(data_file, "%s: .asciz %s\n", label, node->value);  // Add string to .data section
            fprintf(file, "    ldr x0, =%s\n", label);                 // Load address of the string
        } else {
            // It's a number
            fprintf(file, "    mov x0, #%s\n", node->value);
        }
    } else {
        fprintf(stderr, "Error: Unsupported node type %d\n", node->type);
        exit(EXIT_FAILURE);
    }
}

void compile_arm(const char *source_code, const char *output_file) {
    fprintf(stderr, "Debug: Starting ARM compilation.\n");
    fprintf(stderr, "Source code: %s\n", source_code);

    TokenList token_list;
    tokenize(source_code, &token_list);

    fprintf(stderr, "Debug: Tokens generated:\n");
    for (int i = 0; i < token_list.count; i++) {
        fprintf(stderr, "Token[%d]: %s\n", i, token_list.tokens[i]);
    }

    ASTNode *ast = parse(&token_list);

    fprintf(stderr, "Debug: AST generated.\n");

    char data_file_name[256];
    snprintf(data_file_name, sizeof(data_file_name), "%s_data", output_file);

    FILE *text_file = fopen(output_file, "w");
    FILE *data_file = fopen(data_file_name, "w");

    if (!text_file || !data_file) {
        perror("Error opening output files");
        exit(EXIT_FAILURE);
    }

    // Write the sections
    fprintf(text_file, ".section .text\n.global main\nmain:\n");
    fprintf(data_file, ".section .data\n");

    // Generate ARM code
    generate_arm_code(ast, text_file, data_file);

    fprintf(text_file, "    ret\n");

    fclose(text_file);
    fclose(data_file);

    // Merge text and data sections
    FILE *final_file = fopen(output_file, "w");
    if (!final_file) {
        perror("Error creating final output file");
        exit(EXIT_FAILURE);
    }

    // Append the data section
    data_file = fopen(data_file_name, "r");
    if (!data_file) {
        perror("Error opening temporary data file");
        exit(EXIT_FAILURE);
    }
    char line[256];
    while (fgets(line, sizeof(line), data_file)) {
        fputs(line, final_file);
    }
    fclose(data_file);

    // Append the text section
    text_file = fopen(output_file, "r");
    if (!text_file) {
        perror("Error opening temporary text file");
        exit(EXIT_FAILURE);
    }
    while (fgets(line, sizeof(line), text_file)) {
        fputs(line, final_file);
    }
    fclose(text_file);
    fclose(final_file);

    free_ast(ast);
    fprintf(stderr, "Debug: ARM compilation completed successfully.\n");
}
