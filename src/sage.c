#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lib/lexer.h"
#include "lib/parser.h"
#include "lib/codegen.h"

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <input.sage> <output.c>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *input_file = argv[1];
    const char *output_file = argv[2];

    FILE *file = fopen(input_file, "r");
    if (!file) {
        perror("Error opening input file");
        return EXIT_FAILURE;
    }

    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);

    char *source = malloc(length + 1);
    if (!source) {
        perror("Memory allocation failed");
        fclose(file);
        return EXIT_FAILURE;
    }
    fread(source, 1, length, file);
    source[length] = '\0';
    fclose(file);

    TokenList tokens = lex(source);
    free(source);

    ASTNode *ast = parse(&tokens);
    free_tokens(&tokens);

    FILE *output = fopen(output_file, "w");
    if (!output) {
        perror("Error opening output file");
        free_ast(ast);
        return EXIT_FAILURE;
    }
    generate_code(ast, output);
    fclose(output);

    free_ast(ast);
    printf("Compiled to %s\n", output_file);
    return EXIT_SUCCESS;
}
