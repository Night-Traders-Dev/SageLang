#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "lexer.h"
#include "token.h"
#include "ast.h"
#include "parser.h"
#include "interpreter.h"
#include "env.h"
#include "gc.h"
#include "module.h"
#include "compiler.h"

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

static void print_usage(FILE* stream) {
    fprintf(stream,
            "Usage: sage [path]\n"
            "       sage -c \"source\"\n"
            "       sage --emit-c <input.sage> [-o output.c]\n"
            "       sage --compile <input.sage> [-o output] [--cc compiler]\n");
}

static int parse_codegen_options(int argc, const char* argv[], int start_index,
                                 const char** output_path, const char** cc_command) {
    *output_path = NULL;
    *cc_command = NULL;

    for (int i = start_index; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing output path after -o.\n");
                return 0;
            }
            *output_path = argv[++i];
        } else if (strcmp(argv[i], "--cc") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing compiler name after --cc.\n");
                return 0;
            }
            *cc_command = argv[++i];
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            return 0;
        }
    }

    return 1;
}

static char* derive_output_path(const char* input_path, const char* suffix, int replace_extension) {
    const char* last_slash = strrchr(input_path, '/');
    const char* last_dot = strrchr(input_path, '.');
    size_t base_len = strlen(input_path);

    if (replace_extension && last_dot != NULL && (last_slash == NULL || last_dot > last_slash)) {
        base_len = (size_t)(last_dot - input_path);
    }

    size_t suffix_len = strlen(suffix);
    char* output = malloc(base_len + suffix_len + 1);
    if (output == NULL) {
        fprintf(stderr, "Not enough memory to derive output path.\n");
        exit(74);
    }

    memcpy(output, input_path, base_len);
    memcpy(output + base_len, suffix, suffix_len + 1);
    return output;
}


// Helper to read entire file into memory
static char* read_file(const char* path) {
    FILE* file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "Could not open file \"%s\".\n", path);
        exit(74);
    }

    fseek(file, 0L, SEEK_END);
    long fileSizeLong = ftell(file);
    if (fileSizeLong < 0) {
        fprintf(stderr, "Could not determine size of \"%s\".\n", path);
        fclose(file);
        exit(74);
    }
    size_t fileSize = (size_t)fileSizeLong;
    rewind(file);

    char* buffer = (char*)SAGE_ALLOC(fileSize + 1);

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
        print_usage(stderr);
        gc_shutdown();
        cleanup_module_system();
        cleanup_runtime_state();
        exit(64);
    } else if (argc == 3 && strcmp(argv[1], "-c") == 0) {
        run(argv[2]);
    } else if (argc >= 3 && strcmp(argv[1], "--emit-c") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc)) {
            print_usage(stderr);
            gc_shutdown();
            cleanup_module_system();
            cleanup_runtime_state();
            exit(64);
        }

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(argv[2], ".c", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_c(source, argv[2], output_path)) {
            free(source);
            free(derived_output);
            gc_shutdown();
            cleanup_module_system();
            cleanup_runtime_state();
            exit(1);
        }

        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--compile") == 0) {
        const char* explicit_output = NULL;
        const char* cc_command = NULL;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &cc_command)) {
            print_usage(stderr);
            gc_shutdown();
            cleanup_module_system();
            cleanup_runtime_state();
            exit(64);
        }

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(argv[2], "", 1);
            exe_output = derived_output;
        }

        char temp_c_path[256];
        snprintf(temp_c_path, sizeof(temp_c_path), "/tmp/sagec_%d.c", (int)getpid());

        if (!compile_source_to_executable(source, argv[2], temp_c_path, exe_output, cc_command)) {
            unlink(temp_c_path);
            free(source);
            free(derived_output);
            gc_shutdown();
            cleanup_module_system();
            cleanup_runtime_state();
            exit(1);
        }

        unlink(temp_c_path);
        free(source);
        free(derived_output);
    } else if (argc == 2) {
        // File mode
        char* source = read_file(argv[1]);
        run(source);
        free(source);
    } else {
        print_usage(stderr);
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
