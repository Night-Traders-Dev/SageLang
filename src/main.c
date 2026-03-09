#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <setjmp.h>
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
#include "repl.h"
#include "formatter.h"
#include "linter.h"
#include "lsp.h"

extern Environment* g_global_env;

// Phase 12: REPL error recovery globals
int g_repl_mode = 0;
jmp_buf g_repl_error_jmp;

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
            "Usage: sage                    Start interactive REPL\n"
            "       sage [path]             Run a Sage source file\n"
            "       sage --repl             Start interactive REPL\n"
            "       sage -c \"source\"        Execute source string\n"
            "       sage --emit-c <input.sage> [-o output.c] [-O0..3] [-g]\n"
            "       sage --compile <input.sage> [-o output] [--cc compiler] [-O0..3] [-g]\n"
            "       sage --emit-llvm <input.sage> [-o output.ll] [-O0..3] [-g]\n"
            "       sage --compile-llvm <input.sage> [-o output] [-O0..3] [-g]\n"
            "       sage --emit-asm <input.sage> [-o output.s] [--target arch] [-O0..3]\n"
            "       sage --compile-native <input.sage> [-o output] [--target arch] [-O0..3]\n"
            "       sage --emit-pico-c <input.sage> [-o output.c]\n"
            "       sage --compile-pico <input.sage> [-o output_dir] [--board board] [--name program] [--sdk path]\n"
            "       sage fmt <file>          Format a Sage source file in-place\n"
            "       sage fmt --check <file>  Check if file is already formatted\n"
            "       sage lint <file>         Lint a Sage source file\n"
            "       sage --lsp              Start LSP server (stdin/stdout)\n");
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

// Phase 12: Print a value for the REPL (with type-aware formatting)
static void repl_print_value(Value v) {
    if (IS_NIL(v)) return;  // Don't print nil results
    if (IS_STRING(v)) {
        printf("\"%s\"\n", AS_STRING(v));
    } else {
        print_value(v);
        printf("\n");
    }
}

// Phase 12: Check if a line ends with ':' (indicating a block start)
static int line_starts_block(const char* line) {
    size_t len = strlen(line);
    // Walk backwards past whitespace
    while (len > 0 && (line[len - 1] == ' ' || line[len - 1] == '\t' ||
                       line[len - 1] == '\r' || line[len - 1] == '\n')) {
        len--;
    }
    return (len > 0 && line[len - 1] == ':');
}

// Phase 12: Read a line from stdin with a prompt
static char* repl_readline(const char* prompt) {
    printf("%s", prompt);
    fflush(stdout);

    size_t capacity = 256;
    char* line = malloc(capacity);
    if (!line) return NULL;

    size_t len = 0;
    int c;
    while ((c = fgetc(stdin)) != EOF && c != '\n') {
        if (len + 1 >= capacity) {
            capacity *= 2;
            char* new_line = realloc(line, capacity);
            if (!new_line) { free(line); return NULL; }
            line = new_line;
        }
        line[len++] = (char)c;
    }

    if (c == EOF && len == 0) {
        free(line);
        return NULL;  // EOF with no input
    }

    line[len] = '\0';
    return line;
}

// Phase 12: Track REPL source buffers (tokens point into these)
typedef struct ReplBuf {
    char* data;
    struct ReplBuf* next;
} ReplBuf;

static ReplBuf* g_repl_buffers = NULL;

static void repl_keep_buffer(char* buf) {
    ReplBuf* node = malloc(sizeof(ReplBuf));
    node->data = buf;
    node->next = g_repl_buffers;
    g_repl_buffers = node;
}

static void repl_free_buffers(void) {
    ReplBuf* cur = g_repl_buffers;
    while (cur) {
        ReplBuf* next = cur->next;
        free(cur->data);
        free(cur);
        cur = next;
    }
    g_repl_buffers = NULL;
}

// Phase 12: Interactive REPL
static void run_repl(void) {
    printf("Sage REPL v0.12.0\n");
    printf("Type :help for help, :quit to exit.\n");

    Env* env = env_create(NULL);
    g_global_env = env;
    init_stdlib(env);
    g_repl_mode = 1;

    while (1) {
        char* line = repl_readline("sage> ");
        if (line == NULL) {
            // EOF (Ctrl-D)
            printf("\n");
            break;
        }

        // Skip empty lines
        if (line[0] == '\0') {
            free(line);
            continue;
        }

        // Handle REPL commands
        if (strcmp(line, ":quit") == 0 || strcmp(line, ":exit") == 0) {
            free(line);
            break;
        }

        if (strcmp(line, ":help") == 0) {
            printf("Sage REPL Commands:\n");
            printf("  :help       Show this help message\n");
            printf("  :quit       Exit the REPL (also :exit or Ctrl-D)\n");
            printf("\n");
            printf("Enter Sage expressions and statements.\n");
            printf("Multi-line blocks (if, for, while, proc, class) are\n");
            printf("detected automatically when a line ends with ':'.\n");
            printf("End a block with an empty line.\n");
            free(line);
            continue;
        }

        // Multi-line input: if line ends with ':', read continuation lines
        size_t buf_capacity = 1024;
        size_t buf_len = 0;
        // Declared volatile to survive longjmp from error recovery
        char* volatile buffer = malloc(buf_capacity);
        if (!buffer) { free(line); continue; }

        // Copy first line
        size_t line_len = strlen(line);
        if (line_len + 2 > buf_capacity) {
            buf_capacity = line_len + 256;
            buffer = realloc(buffer, buf_capacity);
        }
        memcpy(buffer, line, line_len);
        buffer[line_len] = '\n';
        buf_len = line_len + 1;

        if (line_starts_block(line)) {
            // Read continuation lines until empty line
            int indent_depth = 1;
            (void)indent_depth;

            while (1) {
                char* cont = repl_readline("...   ");
                if (cont == NULL) {
                    // EOF during multi-line input
                    break;
                }

                // Empty line ends the block
                if (cont[0] == '\0') {
                    free(cont);
                    break;
                }

                size_t cont_len = strlen(cont);
                // Ensure buffer has enough space
                while (buf_len + cont_len + 2 > buf_capacity) {
                    buf_capacity *= 2;
                    buffer = realloc(buffer, buf_capacity);
                }
                memcpy(buffer + buf_len, cont, cont_len);
                buf_len += cont_len;
                buffer[buf_len++] = '\n';

                free(cont);
            }
        }

        buffer[buf_len] = '\0';
        free(line);

        // Parse and interpret with error recovery
        if (setjmp(g_repl_error_jmp) == 0) {
            init_lexer(buffer);
            parser_init();

            while (1) {
                Stmt* stmt = parse();
                if (stmt == NULL) break;
                retain_program_stmt(stmt);
                ExecResult result = interpret(stmt, env);

                // If it was an expression statement, print the result
                if (stmt->type == STMT_EXPRESSION && !IS_NIL(result.value)) {
                    repl_print_value(result.value);
                }
            }
        }
        // If setjmp returned non-zero, an error occurred and we recovered

        // Don't free buffer -- tokens in the AST point into it.
        // Instead, keep it alive for the session.
        repl_keep_buffer((char*)buffer);
    }

    g_repl_mode = 0;
    repl_free_buffers();
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
        // No arguments: start REPL
        run_repl();
    } else if (argc == 2 && strcmp(argv[1], "--repl") == 0) {
        // Explicit REPL flag
        run_repl();
    } else if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        print_usage(stdout);
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
    } else if (argc >= 3 && strcmp(argv[1], "fmt") == 0) {
        // Phase 12: Code formatter
        int check_mode = 0;
        const char* fmt_file = NULL;

        if (argc == 3) {
            fmt_file = argv[2];
        } else if (argc == 4 && strcmp(argv[2], "--check") == 0) {
            check_mode = 1;
            fmt_file = argv[3];
        } else {
            fprintf(stderr, "Usage: sage fmt [--check] <file>\n");
            CLEANUP_AND_EXIT(64);
        }

        FormatOptions fmt_opts = format_default_options();

        if (check_mode) {
            /* Read original file */
            FILE* f = fopen(fmt_file, "rb");
            if (!f) {
                fprintf(stderr, "sage fmt: cannot open '%s'\n", fmt_file);
                CLEANUP_AND_EXIT(74);
            }
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            rewind(f);
            char* original = malloc((size_t)sz + 1);
            size_t nread = fread(original, 1, (size_t)sz, f);
            original[nread] = '\0';
            fclose(f);

            char* formatted = format_source(original, fmt_opts);
            int differs = (strcmp(original, formatted) != 0);
            free(original);
            free(formatted);

            if (differs) {
                fprintf(stderr, "%s: needs formatting\n", fmt_file);
                CLEANUP_AND_EXIT(1);
            } else {
                printf("%s: already formatted\n", fmt_file);
            }
        } else {
            if (!format_file(fmt_file, NULL, fmt_opts)) {
                CLEANUP_AND_EXIT(1);
            }
            printf("Formatted: %s\n", fmt_file);
        }
    } else if (argc >= 3 && strcmp(argv[1], "lint") == 0) {
        // Phase 12: Code linter
        const char* lint_file_path = argv[2];
        LintOptions lint_opts = lint_default_options();
        int issues = lint_file(lint_file_path, lint_opts);
        if (issues < 0) {
            CLEANUP_AND_EXIT(74);
        } else if (issues > 0) {
            fprintf(stderr, "\n%d issue%s found.\n", issues, issues == 1 ? "" : "s");
            CLEANUP_AND_EXIT(1);
        } else {
            printf("No issues found.\n");
        }
    } else if (argc == 2 && strcmp(argv[1], "--lsp") == 0) {
        // Phase 12: Language Server Protocol mode
        lsp_run();
    } else if (argc >= 2) {
        // File mode (extra args accessible via sys.args())
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
