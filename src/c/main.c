#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <setjmp.h>
#include <ctype.h>
#include <time.h>
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
#include "typecheck.h"
#include "safety.h"
#include "program.h"
#include "runtime.h"
#include "vm.h"
#include "jit.h"
#include "aot.h"
#include "kotlin_backend.h"

extern Environment* g_global_env;
extern Stmt* parse_program(const char* source, const char* input_path);

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
            "       sage [--runtime ast|bytecode|jit|aot|auto] [--gc:arc|--gc:orc|--gc:tracing] [path]\n"
            "       sage --repl             Start interactive REPL\n"
            "       sage [--runtime ast|bytecode|jit|aot|auto] -c \"source\"\n"
            "       sage --emit-c <input.sage> [-o output.c] [-O0..3] [-g]\n"
            "       sage --emit-vm <input.sage> [-o output.svm] [-O0..3] [-g]\n"
            "       sage --run-vm <input.svm>\n"
            "       sage --compile <input.sage> [-o output] [--cc compiler] [-O0..3] [-g]\n"
            "       sage --emit-llvm <input.sage> [-o output.ll] [-O0..3] [-g]\n"
            "       sage --compile-llvm <input.sage> [-o output] [-O0..3] [-g]\n"
            "       sage --emit-asm <input.sage> [-o output.s] [--target arch[-baremetal|-osdev|-uefi]] [-O0..3] [-g]\n"
            "       sage --compile-native <input.sage> [-o output] [--target arch[-baremetal|-osdev|-uefi]] [-O0..3] [-g]\n"
            "       sage --compile-bare <input.sage> [-o output.elf] [--target arch] [-O0..3] [-g]\n"
            "       sage --compile-uefi <input.sage> [-o output.efi] [--target arch] [-O0..3] [-g]\n"
            "       sage --emit-kotlin <input.sage> [-o output.kt] [-O0..3]\n"
            "       sage --compile-android <input.sage> [-o output_dir] [--package com.example.app] [--app-name MyApp] [--min-sdk 24]\n"
            "       sage --emit-pico-c <input.sage> [-o output.c]\n"
            "       sage --compile-pico <input.sage> [-o output_dir] [--board board] [--name program] [--sdk path]\n"
            "       sage --jit <input.sage>   Run with JIT profiling and compilation\n"
            "       sage --aot <input.sage> [-o output]  AOT compile to native binary\n"
            "       sage --aot --jit <input.sage> [-o output]  Profile-guided AOT compilation\n"
            "       sage fmt <file>          Format a Sage source file in-place\n"
            "       sage fmt --check <file>  Check if file is already formatted\n"
            "       sage lint <file>         Lint a Sage source file\n"
            "       sage check <file>        Type check a Sage source file\n"
            "       sage safety <file>       Run safety analysis (ownership, borrows, lifetimes)\n"
            "       sage --strict-safety <file>  Run with strict safety enforcement\n"
            "       sage --lsp              Start LSP server (stdin/stdout)\n");
}

static const char* value_type_name(Value v) {
    switch (v.type) {
        case VAL_NIL: return "nil";
        case VAL_NUMBER: return "number";
        case VAL_BOOL: return "bool";
        case VAL_STRING: return "string";
        case VAL_FUNCTION: return "function";
        case VAL_NATIVE: return "native";
        case VAL_ARRAY: return "array";
        case VAL_DICT: return "dict";
        case VAL_TUPLE: return "tuple";
        case VAL_CLASS: return "class";
        case VAL_INSTANCE: return "instance";
        case VAL_MODULE: return "module";
        case VAL_EXCEPTION: return "exception";
        case VAL_GENERATOR: return "generator";
        case VAL_CLIB: return "clib";
        case VAL_POINTER: return "pointer";
        case VAL_THREAD: return "thread";
        case VAL_MUTEX: return "mutex";
        default: return "unknown";
    }
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

static const char* skip_space(const char* s) {
    while (*s != '\0' && isspace((unsigned char)*s)) {
        s++;
    }
    return s;
}

static int command_matches(const char* line, const char* command, const char** arg_out) {
    size_t command_len = strlen(command);
    if (strncmp(line, command, command_len) != 0) {
        return 0;
    }

    if (line[command_len] != '\0' && !isspace((unsigned char)line[command_len])) {
        return 0;
    }

    if (arg_out != NULL) {
        *arg_out = skip_space(line + command_len);
    }
    return 1;
}

static int has_suffix(const char* str, const char* suffix) {
    size_t slen = strlen(str);
    size_t suflen = strlen(suffix);
    if (slen < suflen) return 0;
    return strcmp(str + slen - suflen, suffix) == 0;
}

static void trim_suffix(char* str, const char* suffix) {
    size_t slen = strlen(str);
    size_t suflen = strlen(suffix);
    if (slen >= suflen && strcmp(str + slen - suflen, suffix) == 0) {
        str[slen - suflen] = '\0';
    }
}

static CodegenTargetSpec parse_target_spec(const char* arch) {
    CodegenTargetSpec spec;
    spec.target = codegen_detect_host_target();
    spec.profile = CODEGEN_PROFILE_HOSTED;

    if (arch == NULL) return spec;

    char normalized[128];
    size_t n = strlen(arch);
    if (n >= sizeof(normalized)) {
        fprintf(stderr, "Target specification is too long: %s\n", arch);
        exit(64);
    }
    for (size_t i = 0; i <= n; i++) {
        char c = arch[i];
        if (c == '_') c = '-';
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        normalized[i] = c;
    }

    if (has_suffix(normalized, "-baremetal") || has_suffix(normalized, "-freestanding")) {
        spec.profile = CODEGEN_PROFILE_BARE_METAL;
        trim_suffix(normalized, "-baremetal");
        trim_suffix(normalized, "-freestanding");
    } else if (has_suffix(normalized, "-osdev")) {
        spec.profile = CODEGEN_PROFILE_OSDEV;
        trim_suffix(normalized, "-osdev");
    } else if (has_suffix(normalized, "-uefi")) {
        spec.profile = CODEGEN_PROFILE_UEFI;
        trim_suffix(normalized, "-uefi");
    }

    if (strcmp(normalized, "x86-64") == 0 || strcmp(normalized, "x86") == 0 ||
        strcmp(normalized, "x64") == 0) {
        spec.target = CODEGEN_TARGET_X86_64;
    } else if (strcmp(normalized, "aarch64") == 0 || strcmp(normalized, "arm64") == 0) {
        spec.target = CODEGEN_TARGET_AARCH64;
    } else if (strcmp(normalized, "rv64") == 0 || strcmp(normalized, "riscv64") == 0) {
        spec.target = CODEGEN_TARGET_RV64;
    } else {
        fprintf(stderr,
                "Unknown target architecture/profile: %s\n"
                "Supported base targets: x86-64, aarch64, rv64\n"
                "Supported profile suffixes: -baremetal, -osdev, -uefi\n",
                arch);
        exit(64);
    }

    if (spec.profile == CODEGEN_PROFILE_UEFI && spec.target == CODEGEN_TARGET_RV64) {
        fprintf(stderr, "UEFI profile is currently supported for x86-64/aarch64 targets only.\n");
        exit(64);
    }

    return spec;
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

static char* try_read_file(const char* path) {
    FILE* file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }

    if (fseek(file, 0L, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }

    long file_size_long = ftell(file);
    if (file_size_long < 0) {
        fclose(file);
        return NULL;
    }

    size_t file_size = (size_t)file_size_long;
    rewind(file);

    char* buffer = malloc(file_size + 1);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }

    size_t bytes_read = fread(buffer, sizeof(char), file_size, file);
    buffer[bytes_read] = '\0';
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

static void repl_print_value_inline(Value v) {
    if (IS_STRING(v)) {
        printf("\"%s\"", AS_STRING(v));
    } else {
        print_value(v);
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

// Phase 12: Terminal line editor with arrow keys, history, and ctrl shortcuts
// Requires POSIX termios for raw mode
#include <termios.h>
#include <sys/ioctl.h>

static struct termios g_orig_termios;
static int g_raw_mode = 0;

static void disable_raw_mode(void) {
    if (g_raw_mode) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
        g_raw_mode = 0;
    }
}

static int enable_raw_mode(void) {
    if (!isatty(STDIN_FILENO)) return -1;
    if (g_raw_mode) return 0;
    tcgetattr(STDIN_FILENO, &g_orig_termios);
    atexit(disable_raw_mode);

    struct termios raw = g_orig_termios;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag |= OPOST;  // Keep output processing for \n -> \r\n
    raw.c_cflag |= CS8;
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    g_raw_mode = 1;
    return 0;
}

// Forward declaration of history for arrow key navigation (defined later)
#define REPL_HISTORY_MAX 500
static char* g_repl_history[REPL_HISTORY_MAX];
static int g_repl_history_count = 0;

static void repl_refresh_line(const char* prompt, const char* buf, size_t len, size_t pos) {
    // Move cursor to start of line, clear, rewrite
    printf("\r\x1b[K%s%.*s", prompt, (int)len, buf);
    // Position cursor
    int prompt_len = (int)strlen(prompt);
    if ((int)pos < (int)len) {
        printf("\r\x1b[%dC", prompt_len + (int)pos);
    }
    fflush(stdout);
}

static char* repl_readline(const char* prompt) {
    // If not a terminal, fall back to simple fgets
    if (!isatty(STDIN_FILENO)) {
        printf("%s", prompt);
        fflush(stdout);
        size_t cap = 256;
        char* line = malloc(cap);
        if (!line) return NULL;
        size_t len = 0;
        int c;
        while ((c = fgetc(stdin)) != EOF && c != '\n') {
            if (len + 1 >= cap) { cap *= 2; line = realloc(line, cap); }
            line[len++] = (char)c;
        }
        if (c == EOF && len == 0) { free(line); return NULL; }
        line[len] = '\0';
        return line;
    }

    enable_raw_mode();
    printf("%s", prompt);
    fflush(stdout);

    size_t capacity = 256;
    char* buf = malloc(capacity);
    if (!buf) { disable_raw_mode(); return NULL; }
    size_t len = 0;
    size_t pos = 0;  // Cursor position
    int history_idx = g_repl_history_count; // Points past end = current input

    // Save original input for history navigation
    char* saved_line = NULL;

    for (;;) {
        char c;
        int nread = (int)read(STDIN_FILENO, &c, 1);
        if (nread <= 0) {
            // EOF (Ctrl+D with empty line)
            if (len == 0) {
                free(buf);
                if (saved_line) free(saved_line);
                disable_raw_mode();
                return NULL;
            }
            continue;
        }

        if (c == '\r' || c == '\n') {
            // Enter
            printf("\r\n");
            break;
        } else if (c == 4) {
            // Ctrl+D
            if (len == 0) {
                free(buf);
                if (saved_line) free(saved_line);
                disable_raw_mode();
                return NULL;
            }
            // Delete char at cursor
            if (pos < len) {
                memmove(buf + pos, buf + pos + 1, len - pos - 1);
                len--;
                repl_refresh_line(prompt, buf, len, pos);
            }
        } else if (c == 3) {
            // Ctrl+C — clear line
            len = 0;
            pos = 0;
            printf("\r\n");
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 12) {
            // Ctrl+L — clear screen
            printf("\x1b[2J\x1b[H");
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 1) {
            // Ctrl+A — beginning of line
            pos = 0;
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 5) {
            // Ctrl+E — end of line
            pos = len;
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 11) {
            // Ctrl+K — kill to end of line
            len = pos;
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 21) {
            // Ctrl+U — kill to beginning of line
            memmove(buf, buf + pos, len - pos);
            len -= pos;
            pos = 0;
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 23) {
            // Ctrl+W — delete word backward
            while (pos > 0 && buf[pos - 1] == ' ') { pos--; len--; memmove(buf + pos, buf + pos + 1, len - pos); }
            while (pos > 0 && buf[pos - 1] != ' ') { pos--; len--; memmove(buf + pos, buf + pos + 1, len - pos); }
            repl_refresh_line(prompt, buf, len, pos);
        } else if (c == 127 || c == 8) {
            // Backspace
            if (pos > 0) {
                memmove(buf + pos - 1, buf + pos, len - pos);
                pos--;
                len--;
                repl_refresh_line(prompt, buf, len, pos);
            }
        } else if (c == 27) {
            // Escape sequence (arrow keys, etc.)
            char seq[3];
            if (read(STDIN_FILENO, &seq[0], 1) != 1) continue;
            if (read(STDIN_FILENO, &seq[1], 1) != 1) continue;

            if (seq[0] == '[') {
                if (seq[1] == 'A') {
                    // Up arrow — previous history
                    if (history_idx > 0) {
                        if (history_idx == g_repl_history_count) {
                            // Save current input
                            if (saved_line) free(saved_line);
                            buf[len] = '\0';
                            saved_line = strdup(buf);
                        }
                        history_idx--;
                        strncpy(buf, g_repl_history[history_idx], capacity - 1);
                        len = strlen(buf);
                        pos = len;
                        repl_refresh_line(prompt, buf, len, pos);
                    }
                } else if (seq[1] == 'B') {
                    // Down arrow — next history
                    if (history_idx < g_repl_history_count) {
                        history_idx++;
                        if (history_idx == g_repl_history_count) {
                            // Restore saved input
                            if (saved_line) {
                                strncpy(buf, saved_line, capacity - 1);
                                len = strlen(buf);
                            } else {
                                len = 0;
                            }
                        } else {
                            strncpy(buf, g_repl_history[history_idx], capacity - 1);
                            len = strlen(buf);
                        }
                        pos = len;
                        repl_refresh_line(prompt, buf, len, pos);
                    }
                } else if (seq[1] == 'C') {
                    // Right arrow
                    if (pos < len) {
                        pos++;
                        repl_refresh_line(prompt, buf, len, pos);
                    }
                } else if (seq[1] == 'D') {
                    // Left arrow
                    if (pos > 0) {
                        pos--;
                        repl_refresh_line(prompt, buf, len, pos);
                    }
                } else if (seq[1] == 'H') {
                    // Home
                    pos = 0;
                    repl_refresh_line(prompt, buf, len, pos);
                } else if (seq[1] == 'F') {
                    // End
                    pos = len;
                    repl_refresh_line(prompt, buf, len, pos);
                } else if (seq[1] == '3') {
                    // Delete key (ESC [ 3 ~)
                    char tilde;
                    read(STDIN_FILENO, &tilde, 1);
                    if (pos < len) {
                        memmove(buf + pos, buf + pos + 1, len - pos - 1);
                        len--;
                        repl_refresh_line(prompt, buf, len, pos);
                    }
                } else if (seq[1] == '1' || seq[1] == '7') {
                    // Home (alternate)
                    char tilde;
                    read(STDIN_FILENO, &tilde, 1);
                    pos = 0;
                    repl_refresh_line(prompt, buf, len, pos);
                } else if (seq[1] == '4' || seq[1] == '8') {
                    // End (alternate)
                    char tilde;
                    read(STDIN_FILENO, &tilde, 1);
                    pos = len;
                    repl_refresh_line(prompt, buf, len, pos);
                }
            } else if (seq[0] == 'O') {
                if (seq[1] == 'H') { pos = 0; repl_refresh_line(prompt, buf, len, pos); }
                if (seq[1] == 'F') { pos = len; repl_refresh_line(prompt, buf, len, pos); }
            }
        } else if (c >= 32) {
            // Printable character — insert at cursor position
            if (len + 1 >= capacity) {
                capacity *= 2;
                char* new_buf = realloc(buf, capacity);
                if (!new_buf) continue;
                buf = new_buf;
            }
            if (pos < len) {
                memmove(buf + pos + 1, buf + pos, len - pos);
            }
            buf[pos] = c;
            len++;
            pos++;
            repl_refresh_line(prompt, buf, len, pos);
        }
    }

    if (saved_line) free(saved_line);
    disable_raw_mode();
    buf[len] = '\0';
    return buf;
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

static void repl_print_help(void) {
    printf("Sage REPL Commands:\n");
    printf("\n");
    printf("  Session:\n");
    printf("    :help              Show this help message\n");
    printf("    :quit / :exit      Exit the REPL (also Ctrl-D)\n");
    printf("    :reset             Reset session, globals, and module cache\n");
    printf("    :clear             Clear the screen\n");
    printf("    :history [n]       Show last n entries (default: 20)\n");
    printf("    :save <file>       Save session history to a Sage file\n");
    printf("\n");
    printf("  Inspection:\n");
    printf("    :vars [prefix]     List bindings, optionally filtered by prefix\n");
    printf("    :type <expr>       Evaluate expression and show its type\n");
    printf("    :ast <code>        Show parsed AST for an expression or statement\n");
    printf("    :env               Show the full scope chain\n");
    printf("    :modules           List loaded modules and search paths\n");
    printf("\n");
    printf("  Compilation:\n");
    printf("    :emit-c <code>     Show C backend output for a statement\n");
    printf("    :emit-llvm <code>  Show LLVM IR output for a statement\n");
    printf("    :emit-kotlin <code> Show Kotlin backend output for a statement\n");
    printf("\n");
    printf("  Performance:\n");
    printf("    :time <expr>       Time a single expression evaluation\n");
    printf("    :bench <n> <expr>  Run expression n times and show stats\n");
    printf("\n");
    printf("  System:\n");
    printf("    :pwd               Print the current working directory\n");
    printf("    :cd <dir>          Change the current working directory\n");
    printf("    :gc                Run garbage collection and print stats\n");
    printf("    :runtime [mode]    Show or set runtime (ast, bytecode, jit, aot, auto)\n");
    printf("\n");
    printf("Multi-line blocks (if, for, while, proc, class) are\n");
    printf("detected automatically when a line ends with ':'.\n");
    printf("End a block with an empty line.\n");
}

static void repl_list_bindings(Env* env, const char* prefix) {
    int shown = 0;
    size_t prefix_len = (prefix != NULL) ? strlen(prefix) : 0;

    for (EnvNode* node = env->head; node != NULL; node = node->next) {
        if (prefix_len > 0 && strncmp(node->name, prefix, prefix_len) != 0) {
            continue;
        }

        printf("%-16s %-10s ", node->name, value_type_name(node->value));
        repl_print_value_inline(node->value);
        printf("\n");
        shown++;
    }

    if (shown == 0) {
        if (prefix_len > 0) {
            printf("No bindings match prefix \"%s\".\n", prefix);
        } else {
            printf("No bindings in the current REPL scope.\n");
        }
    } else {
        printf("%d binding%s shown.\n", shown, shown == 1 ? "" : "s");
    }
}

static void repl_print_gc_stats(Env* env) {
    g_global_env = env;
    gc_collect_with_root(env);

    GCStats stats = gc_get_stats();
    printf("collections=%d objects=%d freed_last=%d next_gc=%d bytes_allocated=%lu\n",
           stats.collections,
           stats.num_objects,
           stats.objects_freed,
           stats.next_gc,
           stats.bytes_allocated);
}

static void repl_reset_session(Env** env_ptr) {
    free_stmt(g_program_ast);
    g_program_ast = NULL;
    g_program_ast_tail = NULL;
    repl_free_buffers();
    cleanup_module_system();
    env_cleanup_all();

    init_module_system();
    *env_ptr = env_create(NULL);
    g_global_env = *env_ptr;
    init_stdlib(*env_ptr);

    printf("REPL session reset.\n");
}

static void repl_execute_source(char* buffer, Env* env, SageRuntimeMode runtime_mode,
                                int print_expr_results,
                                Value* last_value, int* last_is_expression) {
    if (last_value != NULL) {
        *last_value = val_nil();
    }
    if (last_is_expression != NULL) {
        *last_is_expression = 0;
    }

    init_lexer(buffer, "<repl>");
    parser_init();

    while (1) {
        Stmt* stmt = parse();
        if (stmt == NULL) break;
        retain_program_stmt(stmt);
        ExecResult result = sage_execute_stmt(stmt, env, runtime_mode);

        if (stmt->type == STMT_EXPRESSION) {
            if (last_value != NULL) {
                *last_value = result.value;
            }
            if (last_is_expression != NULL) {
                *last_is_expression = 1;
            }
            if (print_expr_results && !IS_NIL(result.value)) {
                repl_print_value(result.value);
            }
        } else if (last_is_expression != NULL) {
            *last_is_expression = 0;
        }
    }
}

// ============================================================================
// REPL: History tracking (arrays defined above repl_readline)
// ============================================================================

static void repl_history_add(const char* line) {
    if (line == NULL || line[0] == '\0') return;
    // Don't add duplicates of the last entry
    if (g_repl_history_count > 0 &&
        strcmp(g_repl_history[g_repl_history_count - 1], line) == 0) return;
    if (g_repl_history_count >= REPL_HISTORY_MAX) {
        // Drop oldest entry
        free(g_repl_history[0]);
        memmove(g_repl_history, g_repl_history + 1, sizeof(char*) * (REPL_HISTORY_MAX - 1));
        g_repl_history_count--;
    }
    g_repl_history[g_repl_history_count++] = strdup(line);
}

static void repl_history_free(void) {
    for (int i = 0; i < g_repl_history_count; i++) free(g_repl_history[i]);
    g_repl_history_count = 0;
}

// ============================================================================
// REPL: AST printer (compact, for :ast command)
// ============================================================================

static void repl_print_ast_expr(Expr* expr, int depth) {
    if (expr == NULL) { printf("nil"); return; }
    for (int i = 0; i < depth; i++) printf("  ");
    switch (expr->type) {
        case EXPR_NUMBER: printf("(number %g)", expr->as.number.value); break;
        case EXPR_STRING: printf("(string \"%s\")", expr->as.string.value); break;
        case EXPR_BOOL: printf("(bool %s)", expr->as.boolean.value ? "true" : "false"); break;
        case EXPR_NIL: printf("(nil)"); break;
        case EXPR_VARIABLE: printf("(var %.*s)", expr->as.variable.name.length, expr->as.variable.name.start); break;
        case EXPR_BINARY:
            printf("(binary %.*s\n", expr->as.binary.op.length, expr->as.binary.op.start);
            repl_print_ast_expr(expr->as.binary.left, depth + 1); printf("\n");
            repl_print_ast_expr(expr->as.binary.right, depth + 1); printf(")");
            break;
        case EXPR_CALL: {
            printf("(call\n");
            repl_print_ast_expr(expr->as.call.callee, depth + 1);
            for (int i = 0; i < expr->as.call.arg_count; i++) {
                printf("\n");
                repl_print_ast_expr(expr->as.call.args[i], depth + 1);
            }
            printf(")");
            break;
        }
        case EXPR_ARRAY: printf("(array count=%d)", expr->as.array.count); break;
        case EXPR_DICT: printf("(dict count=%d)", expr->as.dict.count); break;
        case EXPR_TUPLE: printf("(tuple count=%d)", expr->as.tuple.count); break;
        case EXPR_INDEX:
            printf("(index\n");
            repl_print_ast_expr(expr->as.index.array, depth + 1); printf("\n");
            repl_print_ast_expr(expr->as.index.index, depth + 1); printf(")");
            break;
        case EXPR_GET:
            printf("(get .%.*s\n", expr->as.get.property.length, expr->as.get.property.start);
            repl_print_ast_expr(expr->as.get.object, depth + 1); printf(")");
            break;
        case EXPR_SET:
            if (expr->as.set.object == NULL) {
                printf("(assign %.*s\n", expr->as.set.property.length, expr->as.set.property.start);
                repl_print_ast_expr(expr->as.set.value, depth + 1); printf(")");
            } else {
                printf("(set .%.*s\n", expr->as.set.property.length, expr->as.set.property.start);
                repl_print_ast_expr(expr->as.set.object, depth + 1); printf("\n");
                repl_print_ast_expr(expr->as.set.value, depth + 1); printf(")");
            }
            break;
        case EXPR_SLICE: printf("(slice ...)"); break;
        case EXPR_INDEX_SET: printf("(index-set ...)"); break;
        case EXPR_AWAIT: printf("(await ...)"); break;
        default: printf("(expr type=%d)", expr->type); break;
    }
}

static void repl_print_ast_stmt(Stmt* stmt, int depth) {
    if (stmt == NULL) return;
    for (int i = 0; i < depth; i++) printf("  ");
    switch (stmt->type) {
        case STMT_PRINT:
            printf("(print\n");
            repl_print_ast_expr(stmt->as.print.expression, depth + 1);
            printf(")\n");
            break;
        case STMT_EXPRESSION:
            printf("(expr\n");
            repl_print_ast_expr(stmt->as.expression, depth + 1);
            printf(")\n");
            break;
        case STMT_LET:
            printf("(let %.*s\n", stmt->as.let.name.length, stmt->as.let.name.start);
            repl_print_ast_expr(stmt->as.let.initializer, depth + 1);
            printf(")\n");
            break;
        case STMT_IF:
            printf("(if\n");
            repl_print_ast_expr(stmt->as.if_stmt.condition, depth + 1);
            printf(")\n");
            break;
        case STMT_WHILE:
            printf("(while\n");
            repl_print_ast_expr(stmt->as.while_stmt.condition, depth + 1);
            printf(")\n");
            break;
        case STMT_FOR:
            printf("(for %.*s in ...)\n", stmt->as.for_stmt.variable.length, stmt->as.for_stmt.variable.start);
            break;
        case STMT_PROC:
            printf("(proc %.*s params=%d)\n", stmt->as.proc.name.length, stmt->as.proc.name.start, stmt->as.proc.param_count);
            break;
        case STMT_CLASS:
            printf("(class %.*s)\n", stmt->as.class_stmt.name.length, stmt->as.class_stmt.name.start);
            break;
        case STMT_RETURN:
            printf("(return\n");
            repl_print_ast_expr(stmt->as.ret.value, depth + 1);
            printf(")\n");
            break;
        case STMT_BLOCK: printf("(block ...)\n"); break;
        case STMT_BREAK: printf("(break)\n"); break;
        case STMT_CONTINUE: printf("(continue)\n"); break;
        case STMT_IMPORT: printf("(import %s)\n", stmt->as.import.module_name ? stmt->as.import.module_name : "?"); break;
        case STMT_RAISE: printf("(raise ...)\n"); break;
        case STMT_TRY: printf("(try ...)\n"); break;
        case STMT_YIELD: printf("(yield ...)\n"); break;
        default: printf("(stmt type=%d)\n", stmt->type); break;
    }
}

// ============================================================================
// REPL: Scope chain printer (for :env command)
// ============================================================================

static void repl_print_env_chain(Env* env) {
    int level = 0;
    while (env != NULL) {
        int count = 0;
        for (EnvNode* n = env->head; n != NULL; n = n->next) count++;
        printf("Scope %d (%d binding%s)%s:\n", level, count, count == 1 ? "" : "s",
               env->parent == NULL ? " [global]" : "");
        for (EnvNode* n = env->head; n != NULL; n = n->next) {
            printf("  %-20s %s\n", n->name, value_type_name(n->value));
        }
        env = env->parent;
        level++;
    }
}

// ============================================================================
// REPL: Module listing (for :modules command)
// ============================================================================

static void repl_list_modules(void) {
    if (global_module_cache == NULL || global_module_cache->modules == NULL) {
        printf("No modules loaded.\n");
        return;
    }
    int count = 0;
    for (Module* m = global_module_cache->modules; m != NULL; m = m->next) {
        printf("  %-16s %s%s\n", m->name,
               m->path ? m->path : "(native)",
               m->is_loaded ? "" : " [not loaded]");
        count++;
    }
    printf("%d module%s in cache.\n", count, count == 1 ? "" : "s");

    if (global_module_cache->search_path_count > 0) {
        printf("Search paths:\n");
        for (int i = 0; i < global_module_cache->search_path_count; i++) {
            printf("  %s\n", global_module_cache->search_paths[i]);
        }
    }
}

// ============================================================================
// REPL: Session save (for :save command)
// ============================================================================

static void repl_save_session(const char* path) {
    FILE* f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, "sage repl: could not open \"%s\" for writing\n", path);
        return;
    }
    int written = 0;
    for (int i = 0; i < g_repl_history_count; i++) {
        const char* line = g_repl_history[i];
        // Skip REPL commands
        if (line[0] == ':') continue;
        fprintf(f, "%s\n", line);
        written++;
    }
    fclose(f);
    printf("Saved %d line%s to %s\n", written, written == 1 ? "" : "s", path);
}

// Phase 12: Interactive REPL
static void run_repl(SageRuntimeMode runtime_mode) {
    printf("Sage REPL v" SAGE_VERSION_STR "\n");
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

        // Record in history
        repl_history_add(line);

        // Handle REPL commands
        if (strcmp(line, ":quit") == 0 || strcmp(line, ":exit") == 0) {
            free(line);
            break;
        }

        if (strcmp(line, ":help") == 0) {
            repl_print_help();
            free(line);
            continue;
        }

        if (line[0] == ':') {
            const char* arg = NULL;

            if (command_matches(line, ":vars", &arg)) {
                repl_list_bindings(env, (*arg != '\0') ? arg : NULL);
                free(line);
                continue;
            }

            if (command_matches(line, ":pwd", NULL)) {
                char cwd[4096];
                if (getcwd(cwd, sizeof(cwd)) != NULL) {
                    printf("%s\n", cwd);
                } else {
                    perror("getcwd");
                }
                free(line);
                continue;
            }

            if (command_matches(line, ":cd", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :cd <dir>\n");
                } else if (chdir(arg) != 0) {
                    perror("chdir");
                } else {
                    char cwd[4096];
                    if (getcwd(cwd, sizeof(cwd)) != NULL) {
                        printf("%s\n", cwd);
                    }
                }
                free(line);
                continue;
            }

            if (command_matches(line, ":gc", NULL)) {
                repl_print_gc_stats(env);
                free(line);
                continue;
            }

            if (command_matches(line, ":reset", NULL)) {
                repl_reset_session(&env);
                free(line);
                continue;
            }

            if (command_matches(line, ":load", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :load <file>\n");
                    free(line);
                    continue;
                }

                char* buffer = try_read_file(arg);
                if (buffer == NULL) {
                    fprintf(stderr, "sage repl: could not open \"%s\"\n", arg);
                    free(line);
                    continue;
                }

                if (setjmp(g_repl_error_jmp) == 0) {
                    repl_execute_source(buffer, env, runtime_mode, 0, NULL, NULL);
                    printf("Loaded: %s\n", arg);
                }
                repl_keep_buffer(buffer);
                free(line);
                continue;
            }

            if (command_matches(line, ":type", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :type <expr>\n");
                    free(line);
                    continue;
                }

                size_t arg_len = strlen(arg);
                char* buffer = malloc(arg_len + 2);
                if (buffer == NULL) {
                    free(line);
                    continue;
                }
                memcpy(buffer, arg, arg_len);
                buffer[arg_len] = '\n';
                buffer[arg_len + 1] = '\0';

                if (setjmp(g_repl_error_jmp) == 0) {
                    Value last_value = val_nil();
                    int last_is_expression = 0;
                    repl_execute_source(buffer, env, runtime_mode, 0, &last_value, &last_is_expression);
                    if (last_is_expression) {
                        printf("%s = ", value_type_name(last_value));
                        repl_print_value_inline(last_value);
                        printf("\n");
                    } else {
                        printf("Expression did not produce a value.\n");
                    }
                }
                repl_keep_buffer(buffer);
                free(line);
                continue;
            }

            // :clear — clear screen
            if (command_matches(line, ":clear", NULL)) {
                printf("\033[2J\033[H");
                fflush(stdout);
                free(line);
                continue;
            }

            // :history [n] — show recent history
            if (command_matches(line, ":history", &arg)) {
                int n = 20;
                if (*arg != '\0') n = atoi(arg);
                if (n <= 0) n = 20;
                int start = g_repl_history_count - n;
                if (start < 0) start = 0;
                for (int i = start; i < g_repl_history_count; i++) {
                    printf("  %3d  %s\n", i + 1, g_repl_history[i]);
                }
                if (g_repl_history_count == 0) printf("No history.\n");
                free(line);
                continue;
            }

            // :save <file> — save session to file
            if (command_matches(line, ":save", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :save <file>\n");
                } else {
                    repl_save_session(arg);
                }
                free(line);
                continue;
            }

            // :env — show scope chain
            if (command_matches(line, ":env", NULL)) {
                repl_print_env_chain(env);
                free(line);
                continue;
            }

            // :modules — list loaded modules
            if (command_matches(line, ":modules", NULL)) {
                repl_list_modules();
                free(line);
                continue;
            }

            // :ast <code> — show parsed AST
            if (command_matches(line, ":ast", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :ast <code>\n");
                    free(line);
                    continue;
                }
                size_t arg_len = strlen(arg);
                char* buffer = SAGE_ALLOC(arg_len + 2);
                memcpy(buffer, arg, arg_len);
                buffer[arg_len] = '\n';
                buffer[arg_len + 1] = '\0';

                if (setjmp(g_repl_error_jmp) == 0) {
                    init_lexer(buffer, "<repl-ast>");
                    parser_init();
                    Stmt* stmt = parse();
                    while (stmt != NULL) {
                        repl_print_ast_stmt(stmt, 0);
                        free_stmt(stmt);
                        stmt = parse();
                    }
                }
                free(buffer);
                free(line);
                continue;
            }

            // :emit-c <code> — show C backend output
            if (command_matches(line, ":emit-c", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :emit-c <code>\n");
                    free(line);
                    continue;
                }
                size_t arg_len = strlen(arg);
                char* buffer = SAGE_ALLOC(arg_len + 2);
                memcpy(buffer, arg, arg_len);
                buffer[arg_len] = '\n';
                buffer[arg_len + 1] = '\0';

                char tmp_path[] = "/tmp/sage_repl_XXXXXX.c";
                int fd = mkstemps(tmp_path, 2);
                if (fd >= 0) close(fd);

                if (compile_source_to_c_opt(buffer, "<repl>", tmp_path, 0, 0)) {
                    char* content = try_read_file(tmp_path);
                    if (content) {
                        printf("%s", content);
                        free(content);
                    }
                }
                unlink(tmp_path);
                free(buffer);
                free(line);
                continue;
            }

            // :emit-llvm <code> — show LLVM IR output
            if (command_matches(line, ":emit-llvm", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :emit-llvm <code>\n");
                    free(line);
                    continue;
                }
                size_t arg_len = strlen(arg);
                char* buffer = SAGE_ALLOC(arg_len + 2);
                memcpy(buffer, arg, arg_len);
                buffer[arg_len] = '\n';
                buffer[arg_len + 1] = '\0';

                char tmp_path[] = "/tmp/sage_repl_XXXXXX.ll";
                int fd = mkstemps(tmp_path, 3);
                if (fd >= 0) close(fd);

                if (compile_source_to_llvm_ir(buffer, "<repl>", tmp_path, 0, 0)) {
                    char* content = try_read_file(tmp_path);
                    if (content) {
                        printf("%s", content);
                        free(content);
                    }
                }
                unlink(tmp_path);
                free(buffer);
                free(line);
                continue;
            }

            // :emit-kotlin <code> — show Kotlin backend output
            if (command_matches(line, ":emit-kotlin", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :emit-kotlin <code>\n");
                    free(line);
                    continue;
                }
                size_t arg_len = strlen(arg);
                char* buffer = SAGE_ALLOC(arg_len + 2);
                memcpy(buffer, arg, arg_len);
                buffer[arg_len] = '\n';
                buffer[arg_len + 1] = '\0';

                char tmp_path[] = "/tmp/sage_repl_XXXXXX.kt";
                int fd = mkstemps(tmp_path, 3);
                if (fd >= 0) close(fd);

                if (compile_source_to_kotlin_opt(buffer, "<repl>", tmp_path, 0, 0)) {
                    char* content = try_read_file(tmp_path);
                    if (content) {
                        printf("%s", content);
                        free(content);
                    }
                }
                unlink(tmp_path);
                free(buffer);
                free(line);
                continue;
            }

            // :time <expr> — time a single evaluation
            if (command_matches(line, ":time", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :time <expr>\n");
                    free(line);
                    continue;
                }
                size_t arg_len = strlen(arg);
                char* buffer = SAGE_ALLOC(arg_len + 2);
                memcpy(buffer, arg, arg_len);
                buffer[arg_len] = '\n';
                buffer[arg_len + 1] = '\0';

                if (setjmp(g_repl_error_jmp) == 0) {
                    struct timespec t0, t1;
                    clock_gettime(CLOCK_MONOTONIC, &t0);
                    Value last_value = val_nil();
                    int last_is_expr = 0;
                    repl_execute_source(buffer, env, runtime_mode, 0, &last_value, &last_is_expr);
                    clock_gettime(CLOCK_MONOTONIC, &t1);
                    double elapsed = (double)(t1.tv_sec - t0.tv_sec) +
                                     (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
                    if (last_is_expr && !IS_NIL(last_value)) {
                        repl_print_value(last_value);
                    }
                    if (elapsed < 0.001)
                        printf("  %.1f us\n", elapsed * 1e6);
                    else if (elapsed < 1.0)
                        printf("  %.3f ms\n", elapsed * 1e3);
                    else
                        printf("  %.3f s\n", elapsed);
                }
                repl_keep_buffer(buffer);
                free(line);
                continue;
            }

            // :bench <n> <expr> — benchmark expression n times
            if (command_matches(line, ":bench", &arg)) {
                if (*arg == '\0') {
                    printf("Usage: :bench <n> <expr>\n");
                    free(line);
                    continue;
                }
                // Parse count and expression
                int count = atoi(arg);
                const char* expr_start = arg;
                while (*expr_start && !isspace((unsigned char)*expr_start)) expr_start++;
                while (*expr_start && isspace((unsigned char)*expr_start)) expr_start++;
                if (count <= 0 || *expr_start == '\0') {
                    printf("Usage: :bench <n> <expr>\n");
                    free(line);
                    continue;
                }
                if (count > 1000000) count = 1000000;

                size_t expr_len = strlen(expr_start);
                char* buffer = SAGE_ALLOC(expr_len + 2);
                memcpy(buffer, expr_start, expr_len);
                buffer[expr_len] = '\n';
                buffer[expr_len + 1] = '\0';

                if (setjmp(g_repl_error_jmp) == 0) {
                    struct timespec t0, t1;
                    double total = 0, min_t = 1e30, max_t = 0;
                    for (int i = 0; i < count; i++) {
                        clock_gettime(CLOCK_MONOTONIC, &t0);
                        repl_execute_source(buffer, env, runtime_mode, 0, NULL, NULL);
                        clock_gettime(CLOCK_MONOTONIC, &t1);
                        double elapsed = (double)(t1.tv_sec - t0.tv_sec) +
                                         (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
                        total += elapsed;
                        if (elapsed < min_t) min_t = elapsed;
                        if (elapsed > max_t) max_t = elapsed;
                    }
                    double avg = total / count;
                    printf("%d iterations: total=%.3f ms, avg=%.1f us, min=%.1f us, max=%.1f us\n",
                           count, total * 1e3, avg * 1e6, min_t * 1e6, max_t * 1e6);
                }
                repl_keep_buffer(buffer);
                free(line);
                continue;
            }

            // :runtime [mode] — show or switch runtime mode
            if (command_matches(line, ":runtime", &arg)) {
                if (*arg == '\0') {
                    printf("Current runtime: %s\n", sage_runtime_mode_name(runtime_mode));
                } else {
                    SageRuntimeMode new_mode;
                    if (sage_runtime_parse_mode(arg, &new_mode)) {
                        runtime_mode = new_mode;
                        printf("Runtime set to: %s\n", sage_runtime_mode_name(runtime_mode));
                    } else {
                        printf("Unknown runtime mode: %s (use ast, bytecode, jit, aot, or auto)\n", arg);
                    }
                }
                free(line);
                continue;
            }

            printf("Unknown REPL command: %s\n", line);
            printf("Type :help for available commands.\n");
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
            repl_execute_source((char*)buffer, env, runtime_mode, 1, NULL, NULL);
        }
        // If setjmp returned non-zero, an error occurred and we recovered

        // Don't free buffer -- tokens in the AST point into it.
        // Instead, keep it alive for the session.
        repl_keep_buffer((char*)buffer);
    }

    g_repl_mode = 0;
    repl_free_buffers();
    repl_history_free();
}

static void run(const char* source, const char* filename, SageRuntimeMode runtime_mode) {
    init_lexer(source, filename);
    parser_init();
    Env* env = env_create(NULL);
    g_global_env = env;
    init_stdlib(env);

    while (1) {
         Stmt* result = parse();
         if (result == NULL) break;
         retain_program_stmt(result);
         sage_execute_stmt(result, env, runtime_mode);
    }
}

#define CLEANUP_AND_EXIT(code) do { \
    gc_shutdown(); \
    cleanup_module_system(); \
    cleanup_runtime_state(); \
    exit(code); \
} while(0)

int main(int argc, const char* argv[]) {
    SageRuntimeMode runtime_mode = SAGE_RUNTIME_AUTO;
    const char** cmd_argv = argv;
    int cmd_argc = argc;

    // Initialize garbage collector
    gc_init();

    // PHASE 8: Initialize module system
    sage_set_args(argc, argv);
    init_module_system();

    // Add source file's directory to module search paths for compiler commands
    if (cmd_argc >= 3 && cmd_argv[2][0] != '-') {
        module_add_source_dir(cmd_argv[2]);
    }

    if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--runtime") == 0) {
        if (!sage_runtime_parse_mode(cmd_argv[2], &runtime_mode)) {
            fprintf(stderr, "Unknown runtime mode: %s (expected ast, bytecode, jit, aot, or auto)\n", cmd_argv[2]);
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }
        cmd_argv += 2;
        cmd_argc -= 2;
    }

    // --gc:arc — switch to ARC (Automatic Reference Counting) mode
    if (cmd_argc >= 2 && strcmp(cmd_argv[1], "--gc:arc") == 0) {
        gc_set_mode(GC_MODE_ARC);
        cmd_argv += 1;
        cmd_argc -= 1;
    }
    // --gc:orc — switch to ORC (Optimized Reference Counting) mode
    if (cmd_argc >= 2 && strcmp(cmd_argv[1], "--gc:orc") == 0) {
        gc_set_mode(GC_MODE_ORC);
        cmd_argv += 1;
        cmd_argc -= 1;
    }
    // --gc:tracing — explicitly select tracing GC (default)
    if (cmd_argc >= 2 && strcmp(cmd_argv[1], "--gc:tracing") == 0) {
        gc_set_mode(GC_MODE_TRACING);
        cmd_argv += 1;
        cmd_argc -= 1;
    }

    if (cmd_argc == 1) {
        // No arguments: start REPL
        run_repl(runtime_mode);
    } else if (cmd_argc == 2 && strcmp(cmd_argv[1], "--repl") == 0) {
        // Explicit REPL flag
        run_repl(runtime_mode);
    } else if (cmd_argc == 2 && strcmp(cmd_argv[1], "--help") == 0) {
        print_usage(stdout);
    } else if (cmd_argc == 3 && strcmp(cmd_argv[1], "-c") == 0) {
        run(cmd_argv[2], "<command>", runtime_mode);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--emit-c") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".c", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_c_opt(source, cmd_argv[2], output_path, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (cmd_argc >= 3 &&
               (strcmp(cmd_argv[1], "--emit-vm") == 0 || strcmp(cmd_argv[1], "--emit-bytecode") == 0)) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".svm", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_vm_artifact(source, cmd_argv[2], output_path, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (cmd_argc == 3 &&
               (strcmp(cmd_argv[1], "--run-vm") == 0 || strcmp(cmd_argv[1], "--run-bytecode") == 0)) {
        BytecodeProgram program;
        char error[256];
        Env* env = NULL;

        bytecode_program_init(&program);
        if (!bytecode_program_read_file(&program, cmd_argv[2], error, sizeof(error))) {
            fprintf(stderr, "VM artifact error: %s\n", error[0] ? error : "unknown error");
            CLEANUP_AND_EXIT(1);
        }

        env = env_create(NULL);
        g_global_env = env;
        init_stdlib(env);
        (void)vm_execute_program(&program, env);
        bytecode_program_free(&program);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile") == 0) {
        const char* explicit_output = NULL;
        const char* cc_command = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &cc_command,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(cmd_argv[2], "", 1);
            exe_output = derived_output;
        }

        char temp_c_path[256];
        snprintf(temp_c_path, sizeof(temp_c_path), "/tmp/sagec_%d.c", (int)getpid());

        if (!compile_source_to_executable_opt(source, cmd_argv[2], temp_c_path, exe_output,
                                              cc_command, opt_level, debug_info)) {
            unlink(temp_c_path);
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        unlink(temp_c_path);
        free(source);
        free(derived_output);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--emit-llvm") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".ll", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_llvm_ir(source, cmd_argv[2], output_path, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile-llvm") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(cmd_argv[2], "", 1);
            exe_output = derived_output;
        }

        char temp_ll_path[256];
        snprintf(temp_ll_path, sizeof(temp_ll_path), "/tmp/sagell_%d.ll", (int)getpid());

        if (!compile_source_to_llvm_executable(source, cmd_argv[2], temp_ll_path, exe_output,
                                               opt_level, debug_info)) {
            unlink(temp_ll_path);
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        unlink(temp_ll_path);
        free(source);
        free(derived_output);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--emit-asm") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* target_arch_str = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &target_arch_str)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        CodegenTargetSpec spec = parse_target_spec(target_arch_str);

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".s", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_asm(source, cmd_argv[2], output_path, spec, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile-native") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* target_arch_str = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &target_arch_str)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        CodegenTargetSpec spec = parse_target_spec(target_arch_str);

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            const char* suffix = (spec.profile == CODEGEN_PROFILE_HOSTED) ? "" : ".o";
            derived_output = derive_output_path(cmd_argv[2], suffix, 1);
            exe_output = derived_output;
        }

        if (!compile_source_to_native(source, cmd_argv[2], exe_output, spec, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    // --compile-bare: compile for bare metal (freestanding, no libc)
    // Equivalent to: --compile-native --target x86-64-baremetal
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile-bare") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* target_arch_str = "x86-64-baremetal";  // default bare metal target
        int opt_level = 2, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &target_arch_str)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }
        // Force baremetal profile if not already set
        if (target_arch_str && !strstr(target_arch_str, "baremetal") && !strstr(target_arch_str, "osdev")) {
            static char bare_target[64];
            snprintf(bare_target, sizeof(bare_target), "%s-baremetal", target_arch_str);
            target_arch_str = bare_target;
        }
        CodegenTargetSpec spec = parse_target_spec(target_arch_str);
        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".elf", 1);
            exe_output = derived_output;
        }
        if (!compile_source_to_native(source, cmd_argv[2], exe_output, spec, opt_level, debug_info)) {
            free(source); free(derived_output);
            CLEANUP_AND_EXIT(1);
        }
        free(source); free(derived_output);

    // --compile-uefi: compile as UEFI application (PE format)
    // Equivalent to: --compile-native --target x86-64-uefi
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile-uefi") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* target_arch_str = "x86-64-uefi";
        int opt_level = 2, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &target_arch_str)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }
        if (target_arch_str && !strstr(target_arch_str, "uefi")) {
            static char uefi_target[64];
            snprintf(uefi_target, sizeof(uefi_target), "%s-uefi", target_arch_str);
            target_arch_str = uefi_target;
        }
        CodegenTargetSpec spec = parse_target_spec(target_arch_str);
        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* exe_output = explicit_output;
        if (exe_output == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".efi", 1);
            exe_output = derived_output;
        }
        if (!compile_source_to_native(source, cmd_argv[2], exe_output, spec, opt_level, debug_info)) {
            free(source); free(derived_output);
            CLEANUP_AND_EXIT(1);
        }
        free(source); free(derived_output);

    // --emit-kotlin: transpile Sage to Kotlin source
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--emit-kotlin") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int opt_level = 0, debug_info = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &opt_level, &debug_info, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".kt", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_kotlin_opt(source, cmd_argv[2], output_path, opt_level, debug_info)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);

    // --compile-android: generate full Android project from Sage source
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile-android") == 0) {
        const char* explicit_output = NULL;
        const char* package_name = NULL;
        const char* app_name_opt = NULL;
        int min_sdk = 0;
        int opt_level = 0, debug_info = 0;

        // Parse Android-specific options
        for (int i = 3; i < cmd_argc; i++) {
            if (strcmp(cmd_argv[i], "-o") == 0 && i + 1 < cmd_argc) {
                explicit_output = cmd_argv[++i];
            } else if (strcmp(cmd_argv[i], "--package") == 0 && i + 1 < cmd_argc) {
                package_name = cmd_argv[++i];
            } else if (strcmp(cmd_argv[i], "--app-name") == 0 && i + 1 < cmd_argc) {
                app_name_opt = cmd_argv[++i];
            } else if (strcmp(cmd_argv[i], "--min-sdk") == 0 && i + 1 < cmd_argc) {
                min_sdk = atoi(cmd_argv[++i]);
            } else if (strcmp(cmd_argv[i], "-O0") == 0) { opt_level = 0; }
            else if (strcmp(cmd_argv[i], "-O1") == 0) { opt_level = 1; }
            else if (strcmp(cmd_argv[i], "-O2") == 0) { opt_level = 2; }
            else if (strcmp(cmd_argv[i], "-O3") == 0) { opt_level = 3; }
            else if (strcmp(cmd_argv[i], "-g") == 0) { debug_info = 1; }
        }

        char* source = read_file(cmd_argv[2]);
        const char* output_dir = explicit_output;
        char derived_dir[512];
        if (output_dir == NULL) {
            // Derive from input: hello.sage → hello_android/
            const char* base = strrchr(cmd_argv[2], '/');
            base = base ? base + 1 : cmd_argv[2];
            size_t base_len = strlen(base);
            const char* dot = strrchr(base, '.');
            if (dot) base_len = (size_t)(dot - base);
            snprintf(derived_dir, sizeof(derived_dir), "%.*s_android", (int)base_len, base);
            output_dir = derived_dir;
        }

        if (!compile_source_to_android(source, cmd_argv[2], output_dir,
                                       package_name, app_name_opt, min_sdk,
                                       opt_level, debug_info)) {
            free(source);
            CLEANUP_AND_EXIT(1);
        }

        free(source);

    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--emit-pico-c") == 0) {
        const char* explicit_output = NULL;
        const char* ignored_cc = NULL;
        const char* ignored_target = NULL;
        int ignored_opt = 0, ignored_dbg = 0;
        if (!parse_codegen_options(cmd_argc, cmd_argv, 3, &explicit_output, &ignored_cc,
                                   &ignored_opt, &ignored_dbg, &ignored_target)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char* derived_output = NULL;
        const char* output_path = explicit_output;
        if (output_path == NULL) {
            derived_output = derive_output_path(cmd_argv[2], ".pico.c", 1);
            output_path = derived_output;
        }

        if (!compile_source_to_pico_c(source, cmd_argv[2], output_path)) {
            free(source);
            free(derived_output);
            CLEANUP_AND_EXIT(1);
        }

        free(source);
        free(derived_output);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--compile-pico") == 0) {
        const char* output_dir = NULL;
        const char* board = NULL;
        const char* program_name = NULL;
        const char* sdk_path = NULL;
        if (!parse_pico_options(cmd_argc, cmd_argv, 3, &output_dir, &board, &program_name, &sdk_path)) {
            print_usage(stderr);
            CLEANUP_AND_EXIT(64);
        }

        char* source = read_file(cmd_argv[2]);
        char uf2_path[1024];
        if (!compile_source_to_pico_uf2(source, cmd_argv[2], output_dir, program_name,
                                        board, sdk_path, uf2_path, sizeof(uf2_path))) {
            free(source);
            CLEANUP_AND_EXIT(1);
        }

        printf("Built UF2: %s\n", uf2_path);
        free(source);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "fmt") == 0) {
        // Phase 12: Code formatter
        int check_mode = 0;
        const char* fmt_file = NULL;

        if (cmd_argc == 3) {
            fmt_file = cmd_argv[2];
        } else if (cmd_argc == 4 && strcmp(cmd_argv[2], "--check") == 0) {
            check_mode = 1;
            fmt_file = cmd_argv[3];
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
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "check") == 0) {
        // Phase 1.6: Type checker
        const char* check_file_path = cmd_argv[2];
        char* check_source = read_file(check_file_path);
        if (!check_source) { CLEANUP_AND_EXIT(74); }
        init_lexer(check_source, check_file_path);
        Stmt* check_ast = parse_program(check_source, check_file_path);
        if (check_ast) {
            PassContext check_ctx = { .opt_level = 0 };
            pass_typecheck(check_ast, &check_ctx);
            printf("Type check complete.\n");
        }
        free(check_source);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "safety") == 0) {
        // Safety analysis: ownership, borrow checking, lifetimes
        const char* safety_file_path = cmd_argv[2];
        char* safety_source = read_file(safety_file_path);
        if (!safety_source) { CLEANUP_AND_EXIT(74); }
        init_lexer(safety_source, safety_file_path);
        Stmt* safety_ast = parse_program(safety_source, safety_file_path);
        if (safety_ast) {
            int mode = SAFETY_MODE_STRICT; // safety subcommand always strict
            if (!safety_analyze(safety_ast, mode, safety_file_path)) {
                free(safety_source);
                CLEANUP_AND_EXIT(1);
            }
            printf("Safety analysis complete: no issues found.\n");
        }
        free(safety_source);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--strict-safety") == 0) {
        // Run file with strict safety enforcement
        const char* ss_file_path = cmd_argv[2];
        module_add_source_dir(ss_file_path);
        char* ss_source = read_file(ss_file_path);
        if (!ss_source) { CLEANUP_AND_EXIT(74); }
        init_lexer(ss_source, ss_file_path);
        Stmt* ss_ast = parse_program(ss_source, ss_file_path);
        if (ss_ast) {
            if (!safety_analyze(ss_ast, SAFETY_MODE_STRICT, ss_file_path)) {
                fprintf(stderr, "Aborting due to safety errors.\n");
                free(ss_source);
                CLEANUP_AND_EXIT(1);
            }
        }
        // Safety passed — run the file normally
        run(ss_source, ss_file_path, runtime_mode);
        free(ss_source);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "lint") == 0) {
        // Phase 12: Code linter
        const char* lint_file_path = cmd_argv[2];
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
    } else if (cmd_argc == 2 && strcmp(cmd_argv[1], "--lsp") == 0) {
        // Phase 12: Language Server Protocol mode
        lsp_run();
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--jit") == 0) {
        // JIT mode: interpret with profiling, compile hot functions
        const char* jit_file = cmd_argv[2];
        module_add_source_dir(jit_file);
        char* source = read_file(jit_file);
        if (!source) { CLEANUP_AND_EXIT(74); }

        JitState jit;
        jit_init(&jit);

        // Wire JIT into interpreter
        extern void interpreter_set_jit(JitState* jit_state);
        interpreter_set_jit(&jit);

        fprintf(stderr, "JIT: Enabled (threshold=%d calls, pool=%zuKB)\n",
                JIT_HOT_THRESHOLD, jit.pool.capacity / 1024);

        // Run with interpreter (JIT profiling active)
        run(source, jit_file, runtime_mode);

        // Report JIT statistics
        int profiled = 0;
        for (int i = 0; i < jit.profile_count; i++) {
            if (jit.profiles[i] && jit.profiles[i]->call_count > 0) profiled++;
        }
        fprintf(stderr, "JIT: %d functions profiled, %d compiled, %d bailouts\n",
                profiled, jit.total_compiled, jit.total_bailouts);

        // Print type feedback for hot functions
        for (int i = 0; i < jit.profile_count; i++) {
            JitProfile* p = jit.profiles[i];
            if (p && p->call_count >= 5) {
                fprintf(stderr, "  func#%d: %d calls, return=%s",
                        i, p->call_count, jit_type_name(p->return_type));
                if (p->param_count > 0 && p->arg_types) {
                    fprintf(stderr, ", args=[");
                    for (int j = 0; j < p->param_count; j++) {
                        if (j > 0) fprintf(stderr, ", ");
                        fprintf(stderr, "%s", jit_type_name(p->arg_types[j]));
                    }
                    fprintf(stderr, "]");
                }
                if (p->jit_compiled) fprintf(stderr, " [COMPILED]");
                fprintf(stderr, "\n");
            }
        }

        interpreter_set_jit(NULL);
        jit_shutdown(&jit);
        free(source);
    } else if (cmd_argc >= 4 && strcmp(cmd_argv[1], "--aot") == 0 && strcmp(cmd_argv[2], "--jit") == 0) {
        // Combined AOT+JIT mode: profile first, then compile with type feedback
        const char* combo_file = cmd_argv[3];
        module_add_source_dir(combo_file);
        char* source = read_file(combo_file);
        if (!source) { CLEANUP_AND_EXIT(74); }

        // Phase 1: JIT profiling run
        JitState jit;
        jit_init(&jit);
        extern void interpreter_set_jit(JitState* jit_state);
        interpreter_set_jit(&jit);
        fprintf(stderr, "AOT+JIT: Phase 1 — profiling run...\n");
        run(source, combo_file, runtime_mode);
        interpreter_set_jit(NULL);

        // Phase 2: Feed profile data to AOT compiler
        fprintf(stderr, "AOT+JIT: Phase 2 — type-specialized AOT compilation...\n");
        init_lexer(source, combo_file);
        Stmt* ast = parse_program(source, combo_file);

        // Determine output path
        const char* out_path = NULL;
        for (int i = 4; i < cmd_argc - 1; i++) {
            if (strcmp(cmd_argv[i], "-o") == 0) out_path = cmd_argv[i + 1];
        }

        AotCompiler aot;
        aot_init(&aot, 2);
        aot.emit_guards = 1; // Enable type guards from JIT data

        // Transfer JIT type feedback to AOT type environment
        for (int i = 0; i < jit.profile_count; i++) {
            JitProfile* p = jit.profiles[i];
            if (p && p->call_count > 0 && p->return_type != JIT_TYPE_UNKNOWN) {
                char name[32];
                snprintf(name, sizeof(name), "__func_%d", i);
                aot_set_var_type(&aot, name, p->return_type);
            }
        }

        char* c_code = aot_compile_program(&aot, ast);

        if (out_path) {
            char c_path[512];
            snprintf(c_path, sizeof(c_path), "%s.c", out_path);
            FILE* f = fopen(c_path, "w");
            if (f) { fputs(c_code, f); fclose(f); }
            if (aot_compile_to_binary(&aot, c_path, out_path)) {
                int profiled = 0;
                for (int i = 0; i < jit.profile_count; i++)
                    if (jit.profiles[i] && jit.profiles[i]->call_count > 0) profiled++;
                fprintf(stderr, "AOT+JIT: Compiled %s → %s (%d functions profiled, %d compiled)\n",
                        combo_file, out_path, profiled, jit.total_compiled);
                unlink(c_path);
            } else {
                fprintf(stderr, "AOT+JIT: Compilation failed\n");
            }
        } else {
            fputs(c_code, stdout);
        }

        free(c_code);
        aot_free(&aot);
        jit_shutdown(&jit);
        free(source);
    } else if (cmd_argc >= 3 && strcmp(cmd_argv[1], "--aot") == 0) {
        // AOT mode: compile to optimized native binary
        const char* aot_file = cmd_argv[2];
        char* source = read_file(aot_file);
        if (!source) { CLEANUP_AND_EXIT(74); }

        init_lexer(source, aot_file);
        Stmt* ast = parse_program(source, aot_file);
        if (!ast) { free(source); CLEANUP_AND_EXIT(1); }

        // Determine output path
        const char* out_path = NULL;
        for (int i = 3; i < cmd_argc - 1; i++) {
            if (strcmp(cmd_argv[i], "-o") == 0) out_path = cmd_argv[i + 1];
        }

        AotCompiler aot;
        aot_init(&aot, 2); // -O2 default
        char* c_code = aot_compile_program(&aot, ast);

        if (out_path) {
            // Write C and compile to binary
            char c_path[512];
            snprintf(c_path, sizeof(c_path), "%s.c", out_path);
            FILE* f = fopen(c_path, "w");
            if (f) { fputs(c_code, f); fclose(f); }
            if (aot_compile_to_binary(&aot, c_path, out_path)) {
                fprintf(stderr, "AOT: Compiled %s → %s (type-specialized)\n", aot_file, out_path);
                unlink(c_path);
            } else {
                fprintf(stderr, "AOT: Compilation failed\n");
            }
        } else {
            // Just print the C code
            fputs(c_code, stdout);
        }

        free(c_code);
        aot_free(&aot);
        free(source);
    } else if (cmd_argc >= 2) {
        // File mode (extra args accessible via sys.args())
        module_add_source_dir(cmd_argv[1]);  // Add source file's dir to search paths
        char* source = read_file(cmd_argv[1]);
        run(source, cmd_argv[1], runtime_mode);
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
