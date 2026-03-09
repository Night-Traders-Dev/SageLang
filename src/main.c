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
#include "llvm_backend.h"
#include "codegen.h"

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
            "       sage --emit-c <input.sage> [-o output.c] [-O0..3] [-g]\n"
            "       sage --compile <input.sage> [-o output] [--cc compiler] [-O0..3] [-g]\n"
            "       sage --emit-llvm <input.sage> [-o output.ll] [-O0..3] [-g]\n"
            "       sage --compile-llvm <input.sage> [-o output] [-O0..3] [-g]\n"
            "       sage --emit-asm <input.sage> [-o output.s] [--target arch] [-O0..3]\n"
            "       sage --compile-native <input.sage> [-o output] [--target arch] [-O0..3]\n"
            "       sage --emit-pico-c <input.sage> [-o output.c]\n"
            "       sage --compile-pico <input.sage> [-o output_dir] [--board board] [--name program] [--sdk path]\n");
}

static int parse_codegen_options(int argc, const char* argv[], int start_index,
                                 const char** output_path, const char** cc_command,
                                 int* opt_level, int* debug_info, const char** target_arch) {
    *output_path = NULL;
    *cc_command = NULL;
    *opt_level = 0;
    *debug_info = 0;
    if (target_arch) *target_arch = NULL;

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
        } else if (strcmp(argv[i], "--target") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing target after --target.\n");
                return 0;
            }
            if (target_arch) *target_arch = argv[++i];
            else ++i;
        } else if (strcmp(argv[i], "-O0") == 0) {
            *opt_level = 0;
        } else if (strcmp(argv[i], "-O1") == 0) {
            *opt_level = 1;
        } else if (strcmp(argv[i], "-O2") == 0) {
            *opt_level = 2;
        } else if (strcmp(argv[i], "-O3") == 0) {
            *opt_level = 3;
        } else if (strcmp(argv[i], "-g") == 0) {
            *debug_info = 1;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            return 0;
        }
    }

    return 1;
}

static int parse_pico_options(int argc, const char* argv[], int start_index,
                              const char** output_dir, const char** board,
                              const char** program_name, const char** sdk_path) {
    *output_dir = NULL;
    *board = NULL;
    *program_name = NULL;
    *sdk_path = NULL;

    for (int i = start_index; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing output directory after -o.\n");
                return 0;
            }
            *output_dir = argv[++i];
        } else if (strcmp(argv[i], "--board") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing board after --board.\n");
                return 0;
            }
            *board = argv[++i];
        } else if (strcmp(argv[i], "--name") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing program name after --name.\n");
                return 0;
            }
            *program_name = argv[++i];
        } else if (strcmp(argv[i], "--sdk") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Missing SDK path after --sdk.\n");
                return 0;
            }
            *sdk_path = argv[++i];
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

static CodegenTarget parse_target_arch(const char* arch) {
    if (arch == NULL) return codegen_detect_host_target();
    if (strcmp(arch, "x86-64") == 0 || strcmp(arch, "x86_64") == 0) return CODEGEN_TARGET_X86_64;
    if (strcmp(arch, "aarch64") == 0 || strcmp(arch, "arm64") == 0) return CODEGEN_TARGET_AARCH64;
    if (strcmp(arch, "rv64") == 0 || strcmp(arch, "riscv64") == 0) return CODEGEN_TARGET_RV64;
    fprintf(stderr, "Unknown target architecture: %s (supported: x86-64, aarch64, rv64)\n", arch);
    exit(64);
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

#define CLEANUP_AND_EXIT(code) do { \
    gc_shutdown(); \
    cleanup_module_system(); \
    cleanup_runtime_state(); \
    exit(code); \
} while(0)

int main(int argc, const char* argv[]) {
    // Initialize garbage collector
    gc_init();

    // PHASE 8: Initialize module system
    sage_set_args(argc, argv);
    init_module_system();

    if (argc == 1) {
        print_usage(stderr);
        CLEANUP_AND_EXIT(64);
    } else if (argc == 3 && strcmp(argv[1], "-c") == 0) {
        run(argv[2]);
    } else if (argc >= 3 && strcmp(argv[1], "--emit-c") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(argv[2], ".c", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_c_opt(source, argv[2], output_path, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--compile") == 0) {
        const char* explicit_output = NULL;
        const char* cc_command = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &cc_command,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
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

        if (!compile_source_to_executable_opt(source, argv[2], temp_c_path, exe_output,
                                              cc_command, opt_level, debug_info)) {
            unlink(temp_c_path);
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        unlink(temp_c_path);
        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--emit-llvm") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(argv[2], ".ll", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_llvm_ir(source, argv[2], output_path, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--compile-llvm") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(argv[2], "", 1);
            exe_output = derived_output;
        }

        char temp_ll_path[256];
        snprintf(temp_ll_path, sizeof(temp_ll_path), "/tmp/sagell_%d.ll", (int)getpid());

        if (!compile_source_to_llvm_executable(source, argv[2], temp_ll_path, exe_output,
                                               opt_level, debug_info)) {
            unlink(temp_ll_path);
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        unlink(temp_ll_path);
        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--emit-asm") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* target_arch_str = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &target_arch_str)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        CodegenTarget target = parse_target_arch(target_arch_str);

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(argv[2], ".s", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_asm(source, argv[2], output_path, target, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--compile-native") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* target_arch_str = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &target_arch_str)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        CodegenTarget target = parse_target_arch(target_arch_str);

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(argv[2], "", 1);
            exe_output = derived_output;
        }

        if (!compile_source_to_native(source, argv[2], exe_output, target, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--emit-pico-c") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int ignored_opt = 0, ignored_dbg = 0;
        if (!parse_codegen_options(argc, argv, 3, &explicit_output, &ignored_cc,
                                   &ignored_opt, &ignored_dbg, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(argv[2], ".pico.c", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_pico_c(source, argv[2], output_path)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (argc >= 3 && strcmp(argv[1], "--compile-pico") == 0) {
        const char* output_dir = NULL;
        const char* board = NULL;
        const char* program_name = NULL;
        const char* sdk_path = NULL;
        if (!parse_pico_options(argc, argv, 3, &output_dir, &board, &program_name, &sdk_path)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(argv[2]);
        char uf2_path[1024];
        if (!compile_source_to_pico_uf2(source, argv[2], output_dir, program_name,
                                        board, sdk_path, uf2_path, sizeof(uf2_path))) {
            free(source);
            CLEANUP_AND_EXIT(1);
        }

        printf("Built UF2: %s\n", uf2_path);
        free(source);
    } else if (argc == 2) {
        // File mode
        char* source = read_file(argv[1]);
        run(source);
        free(source);
    } else {
        print_usage(stderr);
        CLEANUP_AND_EXIT(64);
    }

    // Cleanup and shutdown GC
    gc_shutdown();
    cleanup_module_system();
    cleanup_runtime_state();
    return 0;
}
