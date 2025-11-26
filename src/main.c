#include <stdio.h>
#include <stdlib.h>
#include "lexer.h"
#include "token.h"
#include "ast.h"
#include "interpreter.h"
#include "env.h"

Stmt* parse();
void parser_init();

// Helper to read entire file into memory
static char* read_file(const char* path) {
    FILE* file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "Could not open file \"%s\".\n", path);
        exit(74);
    }

    fseek(file, 0L, SEEK_END);
    size_t fileSize = ftell(file);
    rewind(file);

    char* buffer = (char*)malloc(fileSize + 1);
    if (buffer == NULL) {
        fprintf(stderr, "Not enough memory to read \"%s\".\n", path);
        exit(74);
    }

    size_t bytesRead = fread(buffer, sizeof(char), fileSize, file);
    buffer[bytesRead] = '\0';

    fclose(file);
    return buffer;
}

static void run(const char* source) {
    init_lexer(source);
    parser_init();
    Env* env = env_create(NULL);
    init_stdlib(env);

    while (1) {
         Stmt* result = parse();
         if (result == NULL) break;
         interpret(result, env);
    }
}

int main(int argc, const char* argv[]) {
    if (argc == 1) {
        // REPL mode (interactive) could go here later
        fprintf(stderr, "Usage: sage [path]\n");
        exit(64);
    } else if (argc == 2) {
        // File mode
        char* source = read_file(argv[1]);
        run(source);
        free(source);
    } else {
        fprintf(stderr, "Usage: sage [path]\n");
        exit(64);
    }

    return 0;
}
