#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lexer.h"
#include "token.h"
#include "ast.h"
#include "parser.h"
#include "interpreter.h"
#include "env.h"
#include "gc.h"
#include "module.h"

extern Environment* g_global_env;

static Stmt* g_program_ast = NULL;
static Stmt* g_program_ast_tail = NULL;

static void retain_program_stmt(Stmt* stmt) {
    if (stmt == NULL) {
        return;
    }

    if (g_program_ast == NULL) {
        g_program_ast = stmt;
    } else {
        g_program_ast_tail->next = stmt;
    }
    g_program_ast_tail = stmt;
}

static void cleanup_runtime_state(void) {
    free_stmt(g_program_ast);
    g_program_ast = NULL;
    g_program_ast_tail = NULL;
    env_cleanup_all();
    g_global_env = NULL;
}


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
    g_global_env = env;
    init_stdlib(env);

    while (1) {
         Stmt* result = parse();
         if (result == NULL) break;
         retain_program_stmt(result);
         interpret(result, env);
    }
}

int main(int argc, const char* argv[]) {
    // Initialize garbage collector
    gc_init();
    
    // PHASE 8: Initialize module system
    init_module_system();
    
    if (argc == 1) {
        // REPL mode (interactive) could go here later
        fprintf(stderr, "Usage: sage [path] | sage -c \"source\"\n");
        gc_shutdown();
        cleanup_module_system();
        cleanup_runtime_state();
        exit(64);
    } else if (argc == 3 && strcmp(argv[1], "-c") == 0) {
        run(argv[2]);
    } else if (argc == 2) {
        // File mode
        char* source = read_file(argv[1]);
        run(source);
        free(source);
    } else {
        fprintf(stderr, "Usage: sage [path] | sage -c \"source\"\n");
        gc_shutdown();
        cleanup_module_system();
        cleanup_runtime_state();
        exit(64);
    }

    // Cleanup and shutdown GC
    gc_shutdown();
    cleanup_module_system();
    cleanup_runtime_state();
    return 0;
}
