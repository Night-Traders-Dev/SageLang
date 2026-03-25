#define _DEFAULT_SOURCE
#include "llvm_backend.h"

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ast.h"
#include "gc.h"
#include "graphics.h"
#include "lexer.h"
#include "parser.h"
#include "pass.h"

// ============================================================================
// LLVM IR Text Generation Backend
//
// Emits LLVM IR text (.ll files) that can be compiled with llc + cc.
// Uses the same tagged-union SageValue model as the C backend.
// Runtime functions are declared as external and linked separately.
// ============================================================================

// Forward declaration
extern Stmt* parse_program(const char* source);
static int llvm_resolve_gpu_constant(const char* name, double* out_value);

// ============================================================================
// LLVM Compiler State
// ============================================================================

typedef enum {
    IMPORT_CONST_INVALID = 0,
    IMPORT_CONST_NUMBER,
    IMPORT_CONST_BOOL,
    IMPORT_CONST_STRING,
    IMPORT_CONST_NIL
} ImportConstType;

typedef struct {
    ImportConstType type;
    double number_value;
    int bool_value;
    char* string_value;
} ImportConstValue;

typedef struct {
    char* name;
    ImportConstValue value;
} ImportedConst;

typedef struct {
    FILE* out;
    const char* input_path;
    int failed;
    int next_reg;       // SSA register counter
    int next_label;     // basic block label counter
    int next_str;       // string constant counter
    // String literal pool
    char** strings;
    int string_count;
    int string_cap;
    // Procedure names
    char** proc_names;
    int proc_count;
    int proc_cap;
    // Global variable names
    char** global_names;
    int global_count;
    int global_cap;
    // Loop label stack for break/continue
    int loop_cond_labels[64];
    int loop_end_labels[64];
    int loop_depth;
    // Track whether the current basic block has been terminated (ret/br)
    int block_terminated;
    // Imported module tracking (for GPU/graphics support)
    char** imported_modules;
    int imported_module_count;
    int imported_module_cap;
    // Imported constants from "from module import CONST [as alias]"
    ImportedConst* imported_consts;
    int imported_const_count;
    int imported_const_cap;
} LLVMCompiler;

static int llc_has_module(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->imported_module_count; i++) {
        if (strcmp(lc->imported_modules[i], name) == 0) return 1;
    }
    return 0;
}

static void llc_add_module(LLVMCompiler* lc, const char* name) {
    if (llc_has_module(lc, name)) return;
    if (lc->imported_module_count >= lc->imported_module_cap) {
        lc->imported_module_cap = lc->imported_module_cap ? lc->imported_module_cap * 2 : 8;
        lc->imported_modules = SAGE_REALLOC(lc->imported_modules,
            sizeof(char*) * (size_t)lc->imported_module_cap);
    }
    lc->imported_modules[lc->imported_module_count++] = SAGE_STRDUP(name);
}

static ImportConstValue import_const_invalid(void) {
    ImportConstValue v;
    memset(&v, 0, sizeof(v));
    v.type = IMPORT_CONST_INVALID;
    return v;
}

static ImportConstValue import_const_number(double value) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_NUMBER;
    v.number_value = value;
    return v;
}

static ImportConstValue import_const_bool(int value) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_BOOL;
    v.bool_value = value ? 1 : 0;
    return v;
}

static ImportConstValue import_const_string(const char* value) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_STRING;
    v.string_value = SAGE_STRDUP(value);
    return v;
}

static ImportConstValue import_const_nil(void) {
    ImportConstValue v = import_const_invalid();
    v.type = IMPORT_CONST_NIL;
    return v;
}

static void import_const_value_free(ImportConstValue* value) {
    if (value == NULL) return;
    if (value->type == IMPORT_CONST_STRING) {
        free(value->string_value);
    }
    value->string_value = NULL;
    value->type = IMPORT_CONST_INVALID;
}

static ImportConstValue import_const_value_clone(const ImportConstValue* value) {
    if (value == NULL) return import_const_invalid();
    switch (value->type) {
        case IMPORT_CONST_NUMBER:
            return import_const_number(value->number_value);
        case IMPORT_CONST_BOOL:
            return import_const_bool(value->bool_value);
        case IMPORT_CONST_STRING:
            return import_const_string(value->string_value ? value->string_value : "");
        case IMPORT_CONST_NIL:
            return import_const_nil();
        default:
            return import_const_invalid();
    }
}

static ImportedConst* llc_find_imported_const(LLVMCompiler* lc, const char* name) {
    for (int i = 0; i < lc->imported_const_count; i++) {
        if (strcmp(lc->imported_consts[i].name, name) == 0) {
            return &lc->imported_consts[i];
        }
    }
    return NULL;
}

static void llc_set_imported_const(LLVMCompiler* lc, const char* name, const ImportConstValue* value) {
    if (name == NULL || value == NULL || value->type == IMPORT_CONST_INVALID) return;

    ImportedConst* existing = llc_find_imported_const(lc, name);
    if (existing != NULL) {
        import_const_value_free(&existing->value);
        existing->value = import_const_value_clone(value);
        return;
    }

    if (lc->imported_const_count >= lc->imported_const_cap) {
        lc->imported_const_cap = lc->imported_const_cap ? lc->imported_const_cap * 2 : 16;
        lc->imported_consts = SAGE_REALLOC(
            lc->imported_consts,
            sizeof(ImportedConst) * (size_t)lc->imported_const_cap
        );
    }
    lc->imported_consts[lc->imported_const_count].name = SAGE_STRDUP(name);
    lc->imported_consts[lc->imported_const_count].value = import_const_value_clone(value);
    lc->imported_const_count++;
}

static int llc_new_reg(LLVMCompiler* lc) {
    return lc->next_reg++;
}

static int llc_new_label(LLVMCompiler* lc) {
    return lc->next_label++;
}

static int llc_add_string(LLVMCompiler* lc, const char* str) {
    if (lc->string_count >= lc->string_cap) {
        lc->string_cap = lc->string_cap ? lc->string_cap * 2 : 16;
        lc->strings = SAGE_REALLOC(lc->strings, sizeof(char*) * (size_t)lc->string_cap);
    }
    lc->strings[lc->string_count] = SAGE_STRDUP(str);
    return lc->string_count++;
}

static void llc_add_proc(LLVMCompiler* lc, const char* name) {
    if (lc->proc_count >= lc->proc_cap) {
        lc->proc_cap = lc->proc_cap ? lc->proc_cap * 2 : 16;
        lc->proc_names = SAGE_REALLOC(lc->proc_names, sizeof(char*) * (size_t)lc->proc_cap);
    }
    lc->proc_names[lc->proc_count++] = SAGE_STRDUP(name);
}

static void llc_add_global(LLVMCompiler* lc, const char* name) {
    if (lc->global_count >= lc->global_cap) {
        lc->global_cap = lc->global_cap ? lc->global_cap * 2 : 16;
        lc->global_names = SAGE_REALLOC(lc->global_names, sizeof(char*) * (size_t)lc->global_cap);
    }
    lc->global_names[lc->global_count++] = SAGE_STRDUP(name);
}

static void llc_free(LLVMCompiler* lc) {
    for (int i = 0; i < lc->string_count; i++) free(lc->strings[i]);
    free(lc->strings);
    for (int i = 0; i < lc->proc_count; i++) free(lc->proc_names[i]);
    free(lc->proc_names);
    for (int i = 0; i < lc->global_count; i++) free(lc->global_names[i]);
    free(lc->global_names);
    for (int i = 0; i < lc->imported_module_count; i++) free(lc->imported_modules[i]);
    free(lc->imported_modules);
    for (int i = 0; i < lc->imported_const_count; i++) {
        free(lc->imported_consts[i].name);
        import_const_value_free(&lc->imported_consts[i].value);
    }
    free(lc->imported_consts);
}

// ============================================================================
// LLVM IR Output Helpers
// ============================================================================

static void ll_emit(LLVMCompiler* lc, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(lc->out, fmt, args);
    va_end(args);
}

static void ll_line(LLVMCompiler* lc, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fputs("  ", lc->out);
    vfprintf(lc->out, fmt, args);
    fputc('\n', lc->out);
    va_end(args);
}

// ============================================================================
// Token to string helper
// ============================================================================

static char* token_to_str(Token tok) {
    char* s = SAGE_ALLOC((size_t)tok.length + 1);
    memcpy(s, tok.start, (size_t)tok.length);
    s[tok.length] = '\0';
    return s;
}

typedef struct {
    char* name;
    ImportConstValue value;
} ModuleConst;

static int import_const_truthy(const ImportConstValue* value) {
    if (value == NULL) return 0;
    switch (value->type) {
        case IMPORT_CONST_NIL:
            return 0;
        case IMPORT_CONST_BOOL:
            return value->bool_value ? 1 : 0;
        case IMPORT_CONST_NUMBER:
            return value->number_value != 0.0;
        case IMPORT_CONST_STRING:
            return value->string_value != NULL && value->string_value[0] != '\0';
        default:
            return 0;
    }
}

static int import_const_number_to_i64(const ImportConstValue* value, long long* out) {
    if (value == NULL || out == NULL) return 0;
    if (value->type != IMPORT_CONST_NUMBER) return 0;
    *out = (long long)value->number_value;
    return 1;
}

static int module_const_find_index(ModuleConst* consts, int count, const char* name) {
    for (int i = 0; i < count; i++) {
        if (strcmp(consts[i].name, name) == 0) return i;
    }
    return -1;
}

static ModuleConst* module_const_find(ModuleConst* consts, int count, const char* name) {
    int idx = module_const_find_index(consts, count, name);
    if (idx >= 0) return &consts[idx];
    return NULL;
}

static void module_const_set(ModuleConst** consts, int* count, int* cap,
                             const char* name, const ImportConstValue* value) {
    if (consts == NULL || count == NULL || cap == NULL || name == NULL || value == NULL) return;
    if (value->type == IMPORT_CONST_INVALID) return;

    int idx = module_const_find_index(*consts, *count, name);
    if (idx >= 0) {
        import_const_value_free(&(*consts)[idx].value);
        (*consts)[idx].value = import_const_value_clone(value);
        return;
    }

    if (*count >= *cap) {
        *cap = *cap ? *cap * 2 : 16;
        *consts = SAGE_REALLOC(*consts, sizeof(ModuleConst) * (size_t)*cap);
    }
    (*consts)[*count].name = SAGE_STRDUP(name);
    (*consts)[*count].value = import_const_value_clone(value);
    (*count)++;
}

static void module_const_free_all(ModuleConst* consts, int count) {
    for (int i = 0; i < count; i++) {
        free(consts[i].name);
        import_const_value_free(&consts[i].value);
    }
    free(consts);
}

static char* llvm_read_file_contents(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long size = ftell(f);
    if (size < 0) {
        fclose(f);
        return NULL;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }
    char* buf = SAGE_ALLOC((size_t)size + 1);
    size_t nread = fread(buf, 1, (size_t)size, f);
    buf[nread] = '\0';
    fclose(f);
    return buf;
}

static char* resolve_module_path_for_llvm(const LLVMCompiler* lc, const char* module_name) {
    if (module_name == NULL || module_name[0] == '\0') return NULL;

    // Keep module-name validation aligned with the runtime resolver.
    for (const char* p = module_name; *p != '\0'; p++) {
        if (!((*p >= 'a' && *p <= 'z') ||
              (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') ||
              *p == '_' || *p == '.')) {
            return NULL;
        }
    }
    if (strstr(module_name, "..") != NULL) return NULL;

    char dir[PATH_MAX];
    if (lc->input_path != NULL) {
        strncpy(dir, lc->input_path, sizeof(dir) - 1);
        dir[sizeof(dir) - 1] = '\0';
        char* slash = strrchr(dir, '/');
        if (slash) *(slash + 1) = '\0';
        else strcpy(dir, "./");
    } else {
        strcpy(dir, "./");
    }

    // Convert dots to slashes in module name
    size_t mlen = strlen(module_name);
    char path_name[PATH_MAX];
    if (mlen >= sizeof(path_name)) return NULL;
    for (size_t i = 0; i < mlen; i++) {
        path_name[i] = (module_name[i] == '.') ? '/' : module_name[i];
    }
    path_name[mlen] = '\0';

    char path[PATH_MAX];
    // Search relative to source file directory
    const char* search[] = { "", "lib/", "modules/" };
    for (int i = 0; i < 3; i++) {
        snprintf(path, sizeof(path), "%s%s%s.sage", dir, search[i], path_name);
        if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
    }
    // Search relative to CWD
    for (int i = 0; i < 3; i++) {
        snprintf(path, sizeof(path), "./%s%s.sage", search[i], path_name);
        if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
    }
    // Search installed library path
#ifndef SAGE_LIB_DIR
#define SAGE_LIB_DIR "/usr/local/share/sage/lib"
#endif
    snprintf(path, sizeof(path), "%s/%s.sage", SAGE_LIB_DIR, path_name);
    if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
    // Search SAGE_PATH
    const char* sage_path = getenv("SAGE_PATH");
    if (sage_path != NULL) {
        char env_buf[4096];
        size_t elen = strlen(sage_path);
        if (elen < sizeof(env_buf)) {
            memcpy(env_buf, sage_path, elen + 1);
            char* start = env_buf;
            for (char* p = env_buf; ; p++) {
                if (*p == ':' || *p == '\0') {
                    char ec = *p;
                    *p = '\0';
                    if (p > start) {
                        snprintf(path, sizeof(path), "%s/%s.sage", start, path_name);
                        if (access(path, F_OK) == 0) return SAGE_STRDUP(path);
                    }
                    if (ec == '\0') break;
                    start = p + 1;
                }
            }
        }
    }
    return NULL;
}

static Stmt* llvm_parse_program_with_path(const char* source, const char* input_path) {
    init_lexer(source, input_path);
    parser_init();

    Stmt* head = NULL;
    Stmt* tail = NULL;
    while (1) {
        Stmt* stmt = parse();
        if (stmt == NULL) break;
        if (head == NULL) {
            head = stmt;
        } else {
            tail->next = stmt;
        }
        tail = stmt;
    }
    return head;
}

static ImportConstValue llvm_eval_const_expr(Expr* expr, ModuleConst* consts, int const_count) {
    if (expr == NULL) return import_const_invalid();

    switch (expr->type) {
        case EXPR_NUMBER:
            return import_const_number(expr->as.number.value);
        case EXPR_STRING:
            return import_const_string(expr->as.string.value);
        case EXPR_BOOL:
            return import_const_bool(expr->as.boolean.value);
        case EXPR_NIL:
            return import_const_nil();
        case EXPR_VARIABLE: {
            char* name = token_to_str(expr->as.variable.name);
            ModuleConst* hit = module_const_find(consts, const_count, name);
            free(name);
            if (hit == NULL) return import_const_invalid();
            return import_const_value_clone(&hit->value);
        }
        case EXPR_BINARY: {
            Token op = expr->as.binary.op;
            ImportConstValue left = llvm_eval_const_expr(expr->as.binary.left, consts, const_count);
            ImportConstValue right = llvm_eval_const_expr(expr->as.binary.right, consts, const_count);
            ImportConstValue result = import_const_invalid();

            if (op.type == TOKEN_NOT) {
                if (left.type != IMPORT_CONST_INVALID) {
                    result = import_const_bool(!import_const_truthy(&left));
                }
                import_const_value_free(&left);
                import_const_value_free(&right);
                return result;
            }

            if (op.type == TOKEN_PLUS) {
                if (left.type == IMPORT_CONST_NUMBER && right.type == IMPORT_CONST_NUMBER) {
                    result = import_const_number(left.number_value + right.number_value);
                } else if (left.type == IMPORT_CONST_STRING && right.type == IMPORT_CONST_STRING) {
                    size_t llen = strlen(left.string_value);
                    size_t rlen = strlen(right.string_value);
                    char* joined = SAGE_ALLOC(llen + rlen + 1);
                    memcpy(joined, left.string_value, llen);
                    memcpy(joined + llen, right.string_value, rlen + 1);
                    result = import_const_string(joined);
                    free(joined);
                }
            } else if (op.type == TOKEN_MINUS &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_number(left.number_value - right.number_value);
            } else if (op.type == TOKEN_STAR &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_number(left.number_value * right.number_value);
            } else if (op.type == TOKEN_SLASH &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER &&
                       right.number_value != 0.0) {
                result = import_const_number(left.number_value / right.number_value);
            } else if (op.type == TOKEN_PERCENT &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER &&
                       right.number_value != 0.0) {
                result = import_const_number(fmod(left.number_value, right.number_value));
            } else if (op.type == TOKEN_EQ) {
                int equal = 0;
                if (left.type == right.type) {
                    if (left.type == IMPORT_CONST_NUMBER) equal = left.number_value == right.number_value;
                    else if (left.type == IMPORT_CONST_BOOL) equal = left.bool_value == right.bool_value;
                    else if (left.type == IMPORT_CONST_STRING) equal = strcmp(left.string_value, right.string_value) == 0;
                    else if (left.type == IMPORT_CONST_NIL) equal = 1;
                }
                result = import_const_bool(equal);
            } else if (op.type == TOKEN_NEQ) {
                int equal = 0;
                if (left.type == right.type) {
                    if (left.type == IMPORT_CONST_NUMBER) equal = left.number_value == right.number_value;
                    else if (left.type == IMPORT_CONST_BOOL) equal = left.bool_value == right.bool_value;
                    else if (left.type == IMPORT_CONST_STRING) equal = strcmp(left.string_value, right.string_value) == 0;
                    else if (left.type == IMPORT_CONST_NIL) equal = 1;
                }
                result = import_const_bool(!equal);
            } else if (op.type == TOKEN_LT &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value < right.number_value);
            } else if (op.type == TOKEN_GT &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value > right.number_value);
            } else if (op.type == TOKEN_LTE &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value <= right.number_value);
            } else if (op.type == TOKEN_GTE &&
                       left.type == IMPORT_CONST_NUMBER &&
                       right.type == IMPORT_CONST_NUMBER) {
                result = import_const_bool(left.number_value >= right.number_value);
            } else if (op.type == TOKEN_AND) {
                result = import_const_bool(import_const_truthy(&left) && import_const_truthy(&right));
            } else if (op.type == TOKEN_OR) {
                result = import_const_bool(import_const_truthy(&left) || import_const_truthy(&right));
            } else if (op.type == TOKEN_AMP || op.type == TOKEN_PIPE ||
                       op.type == TOKEN_CARET || op.type == TOKEN_LSHIFT ||
                       op.type == TOKEN_RSHIFT) {
                long long li = 0;
                long long ri = 0;
                if (import_const_number_to_i64(&left, &li) && import_const_number_to_i64(&right, &ri)) {
                    if (op.type == TOKEN_AMP) result = import_const_number((double)(li & ri));
                    if (op.type == TOKEN_PIPE) result = import_const_number((double)(li | ri));
                    if (op.type == TOKEN_CARET) result = import_const_number((double)(li ^ ri));
                    if (op.type == TOKEN_LSHIFT) result = import_const_number((double)(li << ri));
                    if (op.type == TOKEN_RSHIFT) result = import_const_number((double)(li >> ri));
                }
            }

            import_const_value_free(&left);
            import_const_value_free(&right);
            return result;
        }
        default:
            return import_const_invalid();
    }
}

static void llvm_process_import_constants(LLVMCompiler* lc, ImportStmt* import_stmt) {
    if (import_stmt == NULL || import_stmt->item_count <= 0) return;
    if (import_stmt->module_name == NULL) return;

    // Native GPU constants are resolved from the static table.
    if (strcmp(import_stmt->module_name, "gpu") == 0) {
        for (int i = 0; i < import_stmt->item_count; i++) {
            const char* item_name = import_stmt->items[i];
            const char* bind_name = item_name;
            if (import_stmt->item_aliases != NULL && import_stmt->item_aliases[i] != NULL) {
                bind_name = import_stmt->item_aliases[i];
            }
            double value = 0.0;
            if (llvm_resolve_gpu_constant(item_name, &value)) {
                ImportConstValue const_value = import_const_number(value);
                llc_set_imported_const(lc, bind_name, &const_value);
                import_const_value_free(&const_value);
            } else {
                fprintf(stderr,
                        "LLVM backend: unresolved imported constant '%s' from module '%s'\n",
                        item_name, import_stmt->module_name);
                lc->failed = 1;
            }
        }
        return;
    }

    char* module_path = resolve_module_path_for_llvm(lc, import_stmt->module_name);
    if (module_path == NULL) {
        return;
    }

    char* source = llvm_read_file_contents(module_path);
    if (source == NULL) {
        free(module_path);
        return;
    }

    Stmt* module_ast = llvm_parse_program_with_path(source, module_path);

    ModuleConst* consts = NULL;
    int const_count = 0;
    int const_cap = 0;

    for (Stmt* s = module_ast; s != NULL; s = s->next) {
        if (s->type == STMT_LET) {
            char* name = token_to_str(s->as.let.name);
            ImportConstValue value = llvm_eval_const_expr(s->as.let.initializer, consts, const_count);
            if (value.type != IMPORT_CONST_INVALID) {
                module_const_set(&consts, &const_count, &const_cap, name, &value);
            }
            import_const_value_free(&value);
            free(name);
        }
    }

    for (int i = 0; i < import_stmt->item_count; i++) {
        const char* item_name = import_stmt->items[i];
        const char* bind_name = item_name;
        if (import_stmt->item_aliases != NULL && import_stmt->item_aliases[i] != NULL) {
            bind_name = import_stmt->item_aliases[i];
        }
        ModuleConst* hit = module_const_find(consts, const_count, item_name);
        if (hit != NULL) {
            llc_set_imported_const(lc, bind_name, &hit->value);
        } else {
            fprintf(stderr,
                    "LLVM backend: unresolved imported constant '%s' from module '%s'\n",
                    item_name, import_stmt->module_name);
            lc->failed = 1;
        }
    }

    module_const_free_all(consts, const_count);
    free_stmt(module_ast);
    free(source);
    free(module_path);
}

// ============================================================================
// Escape string for LLVM IR string constant
// ============================================================================

static void emit_escaped_string(FILE* out, const char* str) {
    for (const char* p = str; *p; p++) {
        if (*p == '\\') { fputs("\\5C", out); }
        else if (*p == '"') { fputs("\\22", out); }
        else if (*p == '\n') { fputs("\\0A", out); }
        else if (*p == '\r') { fputs("\\0D", out); }
        else if (*p == '\t') { fputs("\\09", out); }
        else if ((unsigned char)*p < 32) { fprintf(out, "\\%02X", (unsigned char)*p); }
        else { fputc(*p, out); }
    }
}

// ============================================================================
// Type Definitions and Runtime Declarations
// ============================================================================

static void emit_type_definitions(LLVMCompiler* lc) {
    ll_emit(lc, "; SageLang LLVM IR - generated by sage compiler\n");
    ll_emit(lc, "target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128\"\n");
    ll_emit(lc, "target triple = \"x86_64-pc-linux-gnu\"\n\n");

    // SageValue — must match clang's ABI lowering of:
    //   struct { int32_t type; union { double; void*; int32_t; } as; }
    // clang lowers this to { i32, i64 } for SysV x86_64 ABI.
    ll_emit(lc, "%%SageValue = type { i32, i64 }\n\n");

    // Runtime function declarations
    ll_emit(lc, "; Runtime function declarations\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_number(double)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bool(i32)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_string(i8*)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_nil()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_add(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_sub(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mul(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_div(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_mod(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_eq(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_neq(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_lt(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gt(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_lte(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gte(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_and(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_or(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_not(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_neg(%%SageValue)\n");
    ll_emit(lc, "declare void @sage_rt_print(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_str(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_len(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_tonumber(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_new(i32)\n");
    ll_emit(lc, "declare void @sage_rt_array_set(%%SageValue, i32, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_push(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_array_pop(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_index(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_is_truthy(%%SageValue)\n");
    ll_emit(lc, "declare i32 @sage_rt_get_bool(%%SageValue)\n");
    // Dict operations
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_new()\n");
    ll_emit(lc, "declare void @sage_rt_dict_set(%%SageValue, i8*, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_get(%%SageValue, i8*)\n");
    // Tuple
    ll_emit(lc, "declare %%SageValue @sage_rt_tuple_new(i32)\n");
    ll_emit(lc, "declare void @sage_rt_tuple_set(%%SageValue, i32, %%SageValue)\n");
    // Slice
    ll_emit(lc, "declare %%SageValue @sage_rt_slice(%%SageValue, %%SageValue, %%SageValue)\n");
    // Property access
    ll_emit(lc, "declare %%SageValue @sage_rt_get_attr(%%SageValue, i8*)\n");
    ll_emit(lc, "declare void @sage_rt_set_attr(%%SageValue, i8*, %%SageValue)\n");
    // Array iteration
    ll_emit(lc, "declare i32 @sage_rt_array_len(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_range(%%SageValue)\n");
    // Index set
    ll_emit(lc, "declare void @sage_rt_index_set(%%SageValue, %%SageValue, %%SageValue)\n");
    // Dict query operations
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_keys(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_values(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_dict_has(%%SageValue, %%SageValue)\n");
    // Type query
    ll_emit(lc, "declare %%SageValue @sage_rt_type(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_chr(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_ord(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_input(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_readfile(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_writefile(%%SageValue, %%SageValue)\n");
    // ML native runtime
    ll_emit(lc, "declare %%SageValue @sage_rt_load_weights(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_matmul(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_rms_norm(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_silu(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_scale(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_cross_entropy(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    // Abort (for raise)
    ll_emit(lc, "declare void @abort() noreturn\n");
    // Bitwise operations
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_and(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_or(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_xor(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_bit_not(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_shl(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_shr(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "\n");

    // GPU runtime declarations (linked from gpu_api + llvm_runtime)
    ll_emit(lc, "; GPU runtime declarations\n");
    // Core lifecycle
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_has_vulkan()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_has_opengl()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init_opengl(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_shutdown()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_device_name()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_device_limits()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_last_error()\n");
    // Buffers
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_buffer(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_buffer_upload(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_buffer_download(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_buffer_size(%%SageValue)\n");
    // Images
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_image(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_image_3d(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_image(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_image_dims(%%SageValue)\n");
    // Samplers
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_sampler(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_sampler_advanced(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_sampler(%%SageValue)\n");
    // Shaders
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_shader(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_shader_glsl(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_reload_shader(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_shader(%%SageValue)\n");
    // Descriptors
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_descriptor_layout(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_descriptor_pool(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_allocate_descriptor_set(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_allocate_descriptor_sets(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_descriptor(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_descriptor_image(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_descriptor_range(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    // Pipelines
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_pipeline_layout(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_compute_pipeline(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_graphics_pipeline(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_pipeline(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_pipeline_cache()\n");
    // Render pass / Framebuffer
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_render_pass(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_render_pass_mrt(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_render_pass(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_framebuffer(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_framebuffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_depth_buffer(%%SageValue, %%SageValue, %%SageValue)\n");
    // Commands
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_command_pool(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_command_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_secondary_command_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_begin_commands(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_begin_secondary(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_end_commands(%%SageValue)\n");
    // Command recording
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_compute_pipeline(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_graphics_pipeline(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_descriptor_set(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_dispatch(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_dispatch_indirect(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_push_constants(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_begin_render_pass(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_end_render_pass(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw_indexed(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw_indirect(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_draw_indexed_indirect(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_vertex_buffer(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_vertex_buffers(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_bind_index_buffer(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_set_viewport(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_set_scissor(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_pipeline_barrier(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_image_barrier(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_copy_buffer(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_copy_buffer_to_image(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_execute_commands(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_cmd_queue_transfer_barrier(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    // Sync
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_fence(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_wait_fence(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_reset_fence(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_fence(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_semaphore()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_semaphore(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_submit(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_submit_compute(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_submit_with_sync(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_queue_wait_idle()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_device_wait_idle()\n");
    // Window / Swapchain
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_window(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_destroy_window()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_window_should_close()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_poll_events()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init_windowed(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_init_opengl_windowed(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_shutdown_windowed()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_swapchain_image_count()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_swapchain_format()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_swapchain_extent()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_acquire_next_image(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_present(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_swapchain_framebuffers(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_swapchain_framebuffers_depth(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_recreate_swapchain()\n");
    // Input
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_pressed(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_down(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_just_pressed(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_key_just_released(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_pos()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_button(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_just_pressed(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_just_released(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_mouse_delta()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_scroll_delta()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_set_cursor_mode(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_get_time()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_window_size()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_set_title(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_window_resized()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_input()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_text_input_available()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_text_input_read()\n");
    // Textures / Upload
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_texture(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_texture_dims(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_generate_mipmaps(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_cubemap(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_upload_device_local(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_upload_bytes(%%SageValue, %%SageValue)\n");
    // Uniform buffers
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_uniform_buffer(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_update_uniform(%%SageValue, %%SageValue)\n");
    // Offscreen / Screenshot
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_create_offscreen_target(%%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_screenshot(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_save_screenshot(%%SageValue)\n");
    // Font
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_font(%%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_atlas(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_set_atlas(%%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_text_verts(%%SageValue, %%SageValue, %%SageValue, %%SageValue, %%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_font_measure(%%SageValue, %%SageValue, %%SageValue)\n");
    // glTF
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_load_gltf(%%SageValue)\n");
    // Queue families
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_graphics_family()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_compute_family()\n");
    // Platform
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_set_platform(%%SageValue)\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_get_platform()\n");
    ll_emit(lc, "declare %%SageValue @sage_rt_gpu_detected_platform()\n");
    ll_emit(lc, "\n");
}

// ============================================================================
// GPU Module Constant Resolution
// ============================================================================

typedef struct { const char* name; double value; } GPUConstant;

static const GPUConstant g_gpu_constants[] = {
    // Buffer usage
    {"BUFFER_STORAGE", 0x01}, {"BUFFER_UNIFORM", 0x02}, {"BUFFER_VERTEX", 0x04},
    {"BUFFER_INDEX", 0x08}, {"BUFFER_STAGING", 0x10}, {"BUFFER_INDIRECT", 0x20},
    {"BUFFER_TRANSFER_SRC", 0x40}, {"BUFFER_TRANSFER_DST", 0x80},
    // Memory
    {"MEMORY_DEVICE_LOCAL", 0x01}, {"MEMORY_HOST_VISIBLE", 0x02}, {"MEMORY_HOST_COHERENT", 0x04},
    // Formats
    {"FORMAT_RGBA8", 0}, {"FORMAT_RGBA16F", 1}, {"FORMAT_RGBA32F", 2},
    {"FORMAT_R32F", 3}, {"FORMAT_RG32F", 4}, {"FORMAT_DEPTH32F", 5},
    {"FORMAT_DEPTH24_S8", 6}, {"FORMAT_R8", 7}, {"FORMAT_RG8", 8},
    {"FORMAT_BGRA8", 9}, {"FORMAT_R32U", 10}, {"FORMAT_RG16F", 11},
    {"FORMAT_R16F", 12}, {"FORMAT_SWAPCHAIN", 99},
    // Image usage
    {"IMAGE_SAMPLED", 0x01}, {"IMAGE_STORAGE", 0x02}, {"IMAGE_COLOR_ATTACH", 0x04},
    {"IMAGE_DEPTH_ATTACH", 0x08}, {"IMAGE_TRANSFER_SRC", 0x10}, {"IMAGE_TRANSFER_DST", 0x20},
    {"IMAGE_INPUT_ATTACH", 0x40},
    // Image types
    {"IMAGE_1D", 0}, {"IMAGE_2D", 1}, {"IMAGE_3D", 2}, {"IMAGE_CUBE", 3},
    // Filter
    {"FILTER_NEAREST", 0}, {"FILTER_LINEAR", 1},
    // Address
    {"ADDRESS_REPEAT", 0}, {"ADDRESS_MIRRORED_REPEAT", 1},
    {"ADDRESS_CLAMP_EDGE", 2}, {"ADDRESS_CLAMP_BORDER", 3},
    // Descriptor types
    {"DESC_STORAGE_BUFFER", 0}, {"DESC_UNIFORM_BUFFER", 1}, {"DESC_SAMPLED_IMAGE", 2},
    {"DESC_STORAGE_IMAGE", 3}, {"DESC_SAMPLER", 4}, {"DESC_COMBINED_SAMPLER", 5},
    // Shader stages
    {"STAGE_VERTEX", 0x01}, {"STAGE_FRAGMENT", 0x02}, {"STAGE_COMPUTE", 0x04},
    {"STAGE_GEOMETRY", 0x08}, {"STAGE_ALL", 0x3F},
    // Topology
    {"TOPO_POINT_LIST", 0}, {"TOPO_LINE_LIST", 1}, {"TOPO_LINE_STRIP", 2},
    {"TOPO_TRIANGLE_LIST", 3}, {"TOPO_TRIANGLE_STRIP", 4}, {"TOPO_TRIANGLE_FAN", 5},
    // Polygon mode
    {"POLY_FILL", 0}, {"POLY_LINE", 1}, {"POLY_POINT", 2},
    // Cull mode
    {"CULL_NONE", 0}, {"CULL_FRONT", 1}, {"CULL_BACK", 2},
    // Front face
    {"FRONT_CCW", 0}, {"FRONT_CW", 1},
    // Blend
    {"BLEND_ZERO", 0}, {"BLEND_ONE", 1}, {"BLEND_SRC_ALPHA", 2},
    {"BLEND_ONE_MINUS_SRC_ALPHA", 3},
    {"BLEND_OP_ADD", 0}, {"BLEND_OP_SUBTRACT", 1}, {"BLEND_OP_MIN", 2}, {"BLEND_OP_MAX", 3},
    // Compare
    {"COMPARE_NEVER", 0}, {"COMPARE_LESS", 1}, {"COMPARE_LEQUAL", 3},
    {"COMPARE_GREATER", 4}, {"COMPARE_ALWAYS", 7},
    // Load/Store
    {"LOAD_CLEAR", 0}, {"LOAD_LOAD", 1}, {"LOAD_DONTCARE", 2},
    {"STORE_STORE", 0}, {"STORE_DONTCARE", 1},
    // Layout
    {"LAYOUT_UNDEFINED", 0}, {"LAYOUT_GENERAL", 1}, {"LAYOUT_COLOR_ATTACH", 2},
    {"LAYOUT_DEPTH_ATTACH", 3}, {"LAYOUT_SHADER_READ", 4},
    {"LAYOUT_TRANSFER_SRC", 5}, {"LAYOUT_TRANSFER_DST", 6}, {"LAYOUT_PRESENT", 7},
    // Pipeline stages
    {"PIPE_TOP", 0x0001}, {"PIPE_VERTEX_INPUT", 0x0004}, {"PIPE_VERTEX_SHADER", 0x0008},
    {"PIPE_FRAGMENT", 0x0010}, {"PIPE_COLOR_OUTPUT", 0x0080},
    {"PIPE_COMPUTE", 0x0100}, {"PIPE_TRANSFER", 0x0200},
    {"PIPE_BOTTOM", 0x0400}, {"PIPE_ALL_COMMANDS", 0x2000},
    // Access
    {"ACCESS_NONE", 0}, {"ACCESS_SHADER_READ", 0x0001}, {"ACCESS_SHADER_WRITE", 0x0002},
    {"ACCESS_TRANSFER_READ", 0x0040}, {"ACCESS_TRANSFER_WRITE", 0x0080},
    {"ACCESS_HOST_READ", 0x0100}, {"ACCESS_HOST_WRITE", 0x0200},
    {"ACCESS_MEMORY_READ", 0x0400}, {"ACCESS_MEMORY_WRITE", 0x0800},
    // Vertex input
    {"INPUT_RATE_VERTEX", 0}, {"INPUT_RATE_INSTANCE", 1},
    {"ATTR_FLOAT", 0}, {"ATTR_VEC2", 1}, {"ATTR_VEC3", 2}, {"ATTR_VEC4", 3},
    {"ATTR_INT", 4}, {"ATTR_UINT", 8},
    // Key constants
    {"KEY_W", 87}, {"KEY_A", 65}, {"KEY_S", 83}, {"KEY_D", 68},
    {"KEY_Q", 81}, {"KEY_E", 69}, {"KEY_R", 82}, {"KEY_F", 70},
    {"KEY_SPACE", 32}, {"KEY_ESCAPE", 256}, {"KEY_ENTER", 257},
    {"KEY_TAB", 258}, {"KEY_BACKSPACE", 259},
    {"KEY_UP", 265}, {"KEY_DOWN", 264}, {"KEY_LEFT", 263}, {"KEY_RIGHT", 262},
    {"KEY_LEFT_SHIFT", 340}, {"KEY_LEFT_CONTROL", 341}, {"KEY_LEFT_ALT", 342},
    {"KEY_RIGHT_SHIFT", 344}, {"KEY_RIGHT_CONTROL", 345},
    {"KEY_F1", 290}, {"KEY_F2", 291}, {"KEY_F3", 292}, {"KEY_F4", 293},
    {"KEY_F5", 294}, {"KEY_F6", 295}, {"KEY_F7", 296},
    {"KEY_1", 49}, {"KEY_2", 50}, {"KEY_3", 51}, {"KEY_4", 52},
    {"KEY_MINUS", 45}, {"KEY_EQUAL", 61},
    // Cursor modes
    {"CURSOR_NORMAL", 0x00034001}, {"CURSOR_HIDDEN", 0x00034002},
    {"CURSOR_DISABLED", 0x00034003},
    // Sentinel
    {NULL, 0}
};

static int llvm_resolve_gpu_constant(const char* name, double* out_value) {
    for (int i = 0; g_gpu_constants[i].name != NULL; i++) {
        if (strcmp(g_gpu_constants[i].name, name) == 0) {
            *out_value = g_gpu_constants[i].value;
            return 1;
        }
    }
    return 0;
}

// Try to emit a GPU module method call. Returns the result register, or -1 if not a known GPU method.
static int llvm_try_emit_gpu_call(LLVMCompiler* lc, const char* method, int* arg_regs, int arg_count) {
    int r = llc_new_reg(lc);

    // Macro for emitting calls with variable args
    #define GPU_CALL_0(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "()", r); return r;
    #define GPU_CALL_1(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d)", r, arg_regs[0]); return r;
    #define GPU_CALL_2(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]); return r;
    #define GPU_CALL_3(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2]); return r;
    #define GPU_CALL_4(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3]); return r;
    #define GPU_CALL_5(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4]); return r;
    #define GPU_CALL_6(fn) \
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4], arg_regs[5]); return r;

    // For calls with 7-8 args, emit inline
    #define GPU_CALL_7(fn) do { \
        fprintf(lc->out, "  %%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)\n", \
            r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4], arg_regs[5], arg_regs[6]); \
        return r; } while(0)
    #define GPU_CALL_8(fn) do { \
        fprintf(lc->out, "  %%%d = call %%SageValue @sage_rt_gpu_" fn "(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)\n", \
            r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4], arg_regs[5], arg_regs[6], arg_regs[7]); \
        return r; } while(0)

    // Core lifecycle
    if (strcmp(method, "has_vulkan") == 0) { GPU_CALL_0("has_vulkan"); }
    if (strcmp(method, "has_opengl") == 0) { GPU_CALL_0("has_opengl"); }
    if (strcmp(method, "initialize") == 0 || strcmp(method, "init") == 0) { GPU_CALL_2("init"); }
    if (strcmp(method, "init_opengl") == 0) { GPU_CALL_3("init_opengl"); }
    if (strcmp(method, "shutdown") == 0) { GPU_CALL_0("shutdown"); }
    if (strcmp(method, "device_name") == 0) { GPU_CALL_0("device_name"); }
    if (strcmp(method, "last_error") == 0) { GPU_CALL_0("last_error"); }
    // Buffers
    if (strcmp(method, "create_buffer") == 0) { GPU_CALL_3("create_buffer"); }
    if (strcmp(method, "destroy_buffer") == 0) { GPU_CALL_1("destroy_buffer"); }
    if (strcmp(method, "buffer_upload") == 0) { GPU_CALL_2("buffer_upload"); }
    if (strcmp(method, "buffer_download") == 0) { GPU_CALL_1("buffer_download"); }
    if (strcmp(method, "buffer_size") == 0) { GPU_CALL_1("buffer_size"); }
    // Images
    if (strcmp(method, "create_image") == 0) { GPU_CALL_5("create_image"); }
    if (strcmp(method, "create_image_3d") == 0) { GPU_CALL_5("create_image_3d"); }
    if (strcmp(method, "destroy_image") == 0) { GPU_CALL_1("destroy_image"); }
    if (strcmp(method, "image_dims") == 0) { GPU_CALL_1("image_dims"); }
    // Samplers
    if (strcmp(method, "create_sampler") == 0) { GPU_CALL_3("create_sampler"); }
    if (strcmp(method, "create_sampler_advanced") == 0) { GPU_CALL_6("create_sampler_advanced"); }
    if (strcmp(method, "destroy_sampler") == 0) { GPU_CALL_1("destroy_sampler"); }
    // Shaders
    if (strcmp(method, "load_shader") == 0) { GPU_CALL_2("load_shader"); }
    if (strcmp(method, "load_shader_glsl") == 0) { GPU_CALL_2("load_shader_glsl"); }
    if (strcmp(method, "reload_shader") == 0) { GPU_CALL_2("reload_shader"); }
    if (strcmp(method, "destroy_shader") == 0) { GPU_CALL_1("destroy_shader"); }
    // Descriptors
    if (strcmp(method, "create_descriptor_layout") == 0) { GPU_CALL_1("create_descriptor_layout"); }
    if (strcmp(method, "create_descriptor_pool") == 0) { GPU_CALL_2("create_descriptor_pool"); }
    if (strcmp(method, "allocate_descriptor_set") == 0) { GPU_CALL_2("allocate_descriptor_set"); }
    if (strcmp(method, "allocate_descriptor_sets") == 0) { GPU_CALL_3("allocate_descriptor_sets"); }
    if (strcmp(method, "update_descriptor") == 0) { GPU_CALL_4("update_descriptor"); }
    if (strcmp(method, "update_descriptor_image") == 0) { GPU_CALL_5("update_descriptor_image"); }
    if (strcmp(method, "update_descriptor_range") == 0) { GPU_CALL_4("update_descriptor_range"); }
    // Pipelines
    if (strcmp(method, "create_pipeline_layout") == 0) { GPU_CALL_3("create_pipeline_layout"); }
    if (strcmp(method, "create_compute_pipeline") == 0) { GPU_CALL_2("create_compute_pipeline"); }
    if (strcmp(method, "create_graphics_pipeline") == 0) { GPU_CALL_1("create_graphics_pipeline"); }
    if (strcmp(method, "destroy_pipeline") == 0) { GPU_CALL_1("destroy_pipeline"); }
    if (strcmp(method, "create_pipeline_cache") == 0) { GPU_CALL_0("create_pipeline_cache"); }
    // Render pass / Framebuffer
    if (strcmp(method, "create_render_pass") == 0) { GPU_CALL_2("create_render_pass"); }
    if (strcmp(method, "create_render_pass_mrt") == 0) { GPU_CALL_2("create_render_pass_mrt"); }
    if (strcmp(method, "destroy_render_pass") == 0) { GPU_CALL_1("destroy_render_pass"); }
    if (strcmp(method, "create_framebuffer") == 0) { GPU_CALL_4("create_framebuffer"); }
    if (strcmp(method, "destroy_framebuffer") == 0) { GPU_CALL_1("destroy_framebuffer"); }
    if (strcmp(method, "create_depth_buffer") == 0) { GPU_CALL_3("create_depth_buffer"); }
    // Commands
    if (strcmp(method, "create_command_pool") == 0) { GPU_CALL_1("create_command_pool"); }
    if (strcmp(method, "create_command_buffer") == 0) { GPU_CALL_1("create_command_buffer"); }
    if (strcmp(method, "create_secondary_command_buffer") == 0) { GPU_CALL_1("create_secondary_command_buffer"); }
    if (strcmp(method, "begin_commands") == 0) { GPU_CALL_1("begin_commands"); }
    if (strcmp(method, "begin_secondary") == 0) { GPU_CALL_4("begin_secondary"); }
    if (strcmp(method, "end_commands") == 0) { GPU_CALL_1("end_commands"); }
    // Command recording
    if (strcmp(method, "cmd_bind_compute_pipeline") == 0) { GPU_CALL_2("cmd_bind_compute_pipeline"); }
    if (strcmp(method, "cmd_bind_graphics_pipeline") == 0) { GPU_CALL_2("cmd_bind_graphics_pipeline"); }
    if (strcmp(method, "cmd_bind_descriptor_set") == 0) { GPU_CALL_4("cmd_bind_descriptor_set"); }
    if (strcmp(method, "cmd_dispatch") == 0) { GPU_CALL_4("cmd_dispatch"); }
    if (strcmp(method, "cmd_dispatch_indirect") == 0) { GPU_CALL_3("cmd_dispatch_indirect"); }
    if (strcmp(method, "cmd_push_constants") == 0) { GPU_CALL_4("cmd_push_constants"); }
    if (strcmp(method, "cmd_begin_render_pass") == 0) { GPU_CALL_6("cmd_begin_render_pass"); }
    if (strcmp(method, "cmd_end_render_pass") == 0) { GPU_CALL_1("cmd_end_render_pass"); }
    if (strcmp(method, "cmd_draw") == 0) { GPU_CALL_5("cmd_draw"); }
    if (strcmp(method, "cmd_draw_indexed") == 0) { GPU_CALL_6("cmd_draw_indexed"); }
    if (strcmp(method, "cmd_draw_indirect") == 0) { GPU_CALL_5("cmd_draw_indirect"); }
    if (strcmp(method, "cmd_draw_indexed_indirect") == 0) { GPU_CALL_5("cmd_draw_indexed_indirect"); }
    if (strcmp(method, "cmd_bind_vertex_buffer") == 0) { GPU_CALL_2("cmd_bind_vertex_buffer"); }
    if (strcmp(method, "cmd_bind_vertex_buffers") == 0) { GPU_CALL_2("cmd_bind_vertex_buffers"); }
    if (strcmp(method, "cmd_bind_index_buffer") == 0) { GPU_CALL_2("cmd_bind_index_buffer"); }
    if (strcmp(method, "cmd_set_viewport") == 0) { GPU_CALL_7("cmd_set_viewport"); }
    if (strcmp(method, "cmd_set_scissor") == 0) { GPU_CALL_5("cmd_set_scissor"); }
    if (strcmp(method, "cmd_pipeline_barrier") == 0) { GPU_CALL_5("cmd_pipeline_barrier"); }
    if (strcmp(method, "cmd_image_barrier") == 0) { GPU_CALL_8("cmd_image_barrier"); }
    if (strcmp(method, "cmd_copy_buffer") == 0) { GPU_CALL_4("cmd_copy_buffer"); }
    if (strcmp(method, "cmd_copy_buffer_to_image") == 0) { GPU_CALL_5("cmd_copy_buffer_to_image"); }
    if (strcmp(method, "cmd_execute_commands") == 0) { GPU_CALL_2("cmd_execute_commands"); }
    if (strcmp(method, "cmd_queue_transfer_barrier") == 0) { GPU_CALL_4("cmd_queue_transfer_barrier"); }
    // Sync
    if (strcmp(method, "create_fence") == 0) { GPU_CALL_1("create_fence"); }
    if (strcmp(method, "wait_fence") == 0) { GPU_CALL_2("wait_fence"); }
    if (strcmp(method, "reset_fence") == 0) { GPU_CALL_1("reset_fence"); }
    if (strcmp(method, "destroy_fence") == 0) { GPU_CALL_1("destroy_fence"); }
    if (strcmp(method, "create_semaphore") == 0) { GPU_CALL_0("create_semaphore"); }
    if (strcmp(method, "destroy_semaphore") == 0) { GPU_CALL_1("destroy_semaphore"); }
    if (strcmp(method, "submit") == 0) { GPU_CALL_2("submit"); }
    if (strcmp(method, "submit_compute") == 0) { GPU_CALL_2("submit_compute"); }
    if (strcmp(method, "submit_with_sync") == 0) { GPU_CALL_4("submit_with_sync"); }
    if (strcmp(method, "queue_wait_idle") == 0) { GPU_CALL_0("queue_wait_idle"); }
    if (strcmp(method, "device_wait_idle") == 0) { GPU_CALL_0("device_wait_idle"); }
    // Window / Swapchain
    if (strcmp(method, "create_window") == 0) { GPU_CALL_3("create_window"); }
    if (strcmp(method, "destroy_window") == 0) { GPU_CALL_0("destroy_window"); }
    if (strcmp(method, "window_should_close") == 0) { GPU_CALL_0("window_should_close"); }
    if (strcmp(method, "poll_events") == 0) { GPU_CALL_0("poll_events"); }
    if (strcmp(method, "init_windowed") == 0) { GPU_CALL_4("init_windowed"); }
    if (strcmp(method, "init_opengl_windowed") == 0) { GPU_CALL_5("init_opengl_windowed"); }
    if (strcmp(method, "shutdown_windowed") == 0) { GPU_CALL_0("shutdown_windowed"); }
    if (strcmp(method, "swapchain_image_count") == 0) { GPU_CALL_0("swapchain_image_count"); }
    if (strcmp(method, "swapchain_format") == 0) { GPU_CALL_0("swapchain_format"); }
    if (strcmp(method, "swapchain_extent") == 0) { GPU_CALL_0("swapchain_extent"); }
    if (strcmp(method, "acquire_next_image") == 0) { GPU_CALL_1("acquire_next_image"); }
    if (strcmp(method, "present") == 0) { GPU_CALL_2("present"); }
    if (strcmp(method, "create_swapchain_framebuffers") == 0) { GPU_CALL_1("create_swapchain_framebuffers"); }
    if (strcmp(method, "create_swapchain_framebuffers_depth") == 0) { GPU_CALL_2("create_swapchain_framebuffers_depth"); }
    if (strcmp(method, "recreate_swapchain") == 0) { GPU_CALL_0("recreate_swapchain"); }
    // Input
    if (strcmp(method, "key_pressed") == 0) { GPU_CALL_1("key_pressed"); }
    if (strcmp(method, "key_down") == 0) { GPU_CALL_1("key_down"); }
    if (strcmp(method, "key_just_pressed") == 0) { GPU_CALL_1("key_just_pressed"); }
    if (strcmp(method, "key_just_released") == 0) { GPU_CALL_1("key_just_released"); }
    if (strcmp(method, "mouse_pos") == 0) { GPU_CALL_0("mouse_pos"); }
    if (strcmp(method, "mouse_button") == 0) { GPU_CALL_1("mouse_button"); }
    if (strcmp(method, "mouse_just_pressed") == 0) { GPU_CALL_1("mouse_just_pressed"); }
    if (strcmp(method, "mouse_just_released") == 0) { GPU_CALL_1("mouse_just_released"); }
    if (strcmp(method, "mouse_delta") == 0) { GPU_CALL_0("mouse_delta"); }
    if (strcmp(method, "scroll_delta") == 0) { GPU_CALL_0("scroll_delta"); }
    if (strcmp(method, "set_cursor_mode") == 0) { GPU_CALL_1("set_cursor_mode"); }
    if (strcmp(method, "get_time") == 0) { GPU_CALL_0("get_time"); }
    if (strcmp(method, "window_size") == 0) { GPU_CALL_0("window_size"); }
    if (strcmp(method, "set_title") == 0) { GPU_CALL_1("set_title"); }
    if (strcmp(method, "window_resized") == 0) { GPU_CALL_0("window_resized"); }
    if (strcmp(method, "update_input") == 0) { GPU_CALL_0("update_input"); }
    if (strcmp(method, "text_input_available") == 0) { GPU_CALL_0("text_input_available"); }
    if (strcmp(method, "text_input_read") == 0) { GPU_CALL_0("text_input_read"); }
    // Textures / Upload
    if (strcmp(method, "load_texture") == 0) { GPU_CALL_4("load_texture"); }
    if (strcmp(method, "texture_dims") == 0) { GPU_CALL_1("texture_dims"); }
    if (strcmp(method, "generate_mipmaps") == 0) { GPU_CALL_1("generate_mipmaps"); }
    if (strcmp(method, "create_cubemap") == 0) { GPU_CALL_1("create_cubemap"); }
    if (strcmp(method, "upload_device_local") == 0) { GPU_CALL_2("upload_device_local"); }
    if (strcmp(method, "upload_bytes") == 0) { GPU_CALL_2("upload_bytes"); }
    // Uniform buffers
    if (strcmp(method, "create_uniform_buffer") == 0) { GPU_CALL_1("create_uniform_buffer"); }
    if (strcmp(method, "update_uniform") == 0) { GPU_CALL_2("update_uniform"); }
    // Offscreen / Screenshot
    if (strcmp(method, "create_offscreen_target") == 0) { GPU_CALL_4("create_offscreen_target"); }
    if (strcmp(method, "screenshot") == 0) { GPU_CALL_1("screenshot"); }
    if (strcmp(method, "save_screenshot") == 0) { GPU_CALL_1("save_screenshot"); }
    // Font
    if (strcmp(method, "load_font") == 0) { GPU_CALL_2("load_font"); }
    if (strcmp(method, "font_atlas") == 0) { GPU_CALL_1("font_atlas"); }
    if (strcmp(method, "font_set_atlas") == 0) { GPU_CALL_3("font_set_atlas"); }
    if (strcmp(method, "font_text_verts") == 0) { GPU_CALL_5("font_text_verts"); }
    if (strcmp(method, "font_measure") == 0) { GPU_CALL_3("font_measure"); }
    // glTF
    if (strcmp(method, "load_gltf") == 0) { GPU_CALL_1("load_gltf"); }
    // Queue families
    if (strcmp(method, "graphics_family") == 0) { GPU_CALL_0("graphics_family"); }
    if (strcmp(method, "compute_family") == 0) { GPU_CALL_0("compute_family"); }
    // Platform
    if (strcmp(method, "set_platform") == 0) { GPU_CALL_1("set_platform"); }
    if (strcmp(method, "get_platform") == 0) { GPU_CALL_0("get_platform"); }
    if (strcmp(method, "detected_platform") == 0) { GPU_CALL_0("detected_platform"); }
    // Device limits (takes 0 args, returns dict)
    if (strcmp(method, "device_limits") == 0) { GPU_CALL_0("device_limits"); }

    #undef GPU_CALL_0
    #undef GPU_CALL_1
    #undef GPU_CALL_2
    #undef GPU_CALL_3
    #undef GPU_CALL_4
    #undef GPU_CALL_5
    #undef GPU_CALL_6
    #undef GPU_CALL_7
    #undef GPU_CALL_8

    return -1;  // Not a known GPU method
}

// ============================================================================
// Collect top-level symbols
// ============================================================================

// Build a "ClassName_methodName" string for class methods
static char* class_method_name(const char* class_name, Token method_token) {
    char* method = token_to_str(method_token);
    size_t clen = strlen(class_name);
    size_t mlen = strlen(method);
    char* result = SAGE_ALLOC(clen + 1 + mlen + 1);
    memcpy(result, class_name, clen);
    result[clen] = '_';
    memcpy(result + clen + 1, method, mlen + 1);
    free(method);
    return result;
}

static void llvm_collect_symbols(LLVMCompiler* lc, Stmt* program) {
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = token_to_str(s->as.proc.name);
            llc_add_proc(lc, name);
            free(name);
        } else if (s->type == STMT_LET) {
            char* name = token_to_str(s->as.let.name);
            llc_add_global(lc, name);
            free(name);
        } else if (s->type == STMT_IMPORT) {
            if (s->as.import.module_name != NULL) {
                llc_add_module(lc, s->as.import.module_name);
                // Create a global variable for the module binding
                // import agent.critic -> binding name is "critic"
                // import foo as bar -> binding name is "bar"
                const char* bind = s->as.import.alias;
                if (bind == NULL && s->as.import.item_count == 0) {
                    // Extract last component of dotted name
                    const char* dot = strrchr(s->as.import.module_name, '.');
                    if (dot != NULL) {
                        bind = dot + 1;
                    } else {
                        bind = s->as.import.module_name;
                    }
                }
                if (bind != NULL) {
                    llc_add_global(lc, bind);
                }
            }
            if (s->as.import.item_count > 0) {
                llvm_process_import_constants(lc, &s->as.import);
            }
        } else if (s->type == STMT_CLASS) {
            char* cname = token_to_str(s->as.class_stmt.name);
            // Each method becomes a function sage_fn_ClassName_methodName
            for (Stmt* m = s->as.class_stmt.methods; m != NULL; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = class_method_name(cname, m->as.proc.name);
                    llc_add_proc(lc, mname);
                    free(mname);
                }
            }
            free(cname);
        }
    }
}

// ============================================================================
// Expression Emission - returns SSA register number
// ============================================================================

static int llvm_emit_expr(LLVMCompiler* lc, Expr* expr);

static int llvm_emit_expr(LLVMCompiler* lc, Expr* expr) {
    if (expr == NULL) {
        int r = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
        return r;
    }

    switch (expr->type) {
        case EXPR_NUMBER: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %e)", r, expr->as.number.value);
            return r;
        }
        case EXPR_STRING: {
            int str_id = llc_add_string(lc, expr->as.string.value);
            size_t slen = strlen(expr->as.string.value) + 1;
            int ptr_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                    ptr_reg, slen, slen, str_id);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_string(i8* %%%d)", r, ptr_reg);
            return r;
        }
        case EXPR_BOOL: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 %d)", r, expr->as.boolean.value ? 1 : 0);
            return r;
        }
        case EXPR_NIL: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
        case EXPR_BINARY: {
            int left = llvm_emit_expr(lc, expr->as.binary.left);
            int right = llvm_emit_expr(lc, expr->as.binary.right);
            int r = llc_new_reg(lc);

            const char* op = expr->as.binary.op.start;
            int op_len = expr->as.binary.op.length;

            if (op_len == 1) {
                switch (*op) {
                    case '+': ll_line(lc, "%%%d = call %%SageValue @sage_rt_add(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '-': ll_line(lc, "%%%d = call %%SageValue @sage_rt_sub(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '*': ll_line(lc, "%%%d = call %%SageValue @sage_rt_mul(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '/': ll_line(lc, "%%%d = call %%SageValue @sage_rt_div(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '%': ll_line(lc, "%%%d = call %%SageValue @sage_rt_mod(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '<': ll_line(lc, "%%%d = call %%SageValue @sage_rt_lt(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '>': ll_line(lc, "%%%d = call %%SageValue @sage_rt_gt(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '&': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_and(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '|': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_or(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '^': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_xor(%%SageValue %%%d, %%SageValue %%%d)", r, left, right); break;
                    case '~': ll_line(lc, "%%%d = call %%SageValue @sage_rt_bit_not(%%SageValue %%%d)", r, right); break;
                    default:
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                        break;
                }
            } else if (op_len == 2) {
                if (op[0] == '=' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_eq(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '!' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_neq(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '<' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_lte(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '>' && op[1] == '=') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_gte(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (memcmp(op, "or", 2) == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_or(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '<' && op[1] == '<') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_shl(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else if (op[0] == '>' && op[1] == '>') {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_shr(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
                } else {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                }
            } else if (op_len == 3 && memcmp(op, "and", 3) == 0) {
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_and(%%SageValue %%%d, %%SageValue %%%d)", r, left, right);
            } else if (op_len == 3 && memcmp(op, "not", 3) == 0) {
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_not(%%SageValue %%%d)", r, right);
            } else {
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            }
            return r;
        }
        case EXPR_VARIABLE: {
            char* name = token_to_str(expr->as.variable.name);
            // Module references (gpu, math, etc.) are handled at EXPR_GET/EXPR_CALL level;
            // if we reach here, emit nil as a placeholder (module objects don't exist in LLVM mode)
            if (llc_has_module(lc, name)) {
                int r = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                free(name);
                return r;
            }

            ImportedConst* imported = llc_find_imported_const(lc, name);
            if (imported != NULL) {
                int r = llc_new_reg(lc);
                switch (imported->value.type) {
                    case IMPORT_CONST_NUMBER:
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %e)",
                                r, imported->value.number_value);
                        break;
                    case IMPORT_CONST_BOOL:
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 %d)",
                                r, imported->value.bool_value ? 1 : 0);
                        break;
                    case IMPORT_CONST_STRING: {
                        int str_id = llc_add_string(lc, imported->value.string_value);
                        size_t slen = strlen(imported->value.string_value) + 1;
                        int ptr_reg = llc_new_reg(lc);
                        ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                                ptr_reg, slen, slen, str_id);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_string(i8* %%%d)", r, ptr_reg);
                        break;
                    }
                    case IMPORT_CONST_NIL:
                    default:
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                        break;
                }
                free(name);
                return r;
            }

            int r = llc_new_reg(lc);
            // Check if it's a global variable
            int is_global = 0;
            for (int i = 0; i < lc->global_count; i++) {
                if (strcmp(lc->global_names[i], name) == 0) { is_global = 1; break; }
            }
            // Check if it's a known proc (used as first-class value / callback)
            int is_proc = 0;
            for (int i = 0; i < lc->proc_count; i++) {
                if (strcmp(lc->proc_names[i], name) == 0) { is_proc = 1; break; }
            }
            if (is_proc) {
                // Proc reference as value — emit nil placeholder
                // (LLVM functions can't be SageValue directly; callbacks work via nil sentinel)
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            } else if (is_global) {
                ll_line(lc, "%%%d = load %%SageValue, %%SageValue* @%s", r, name);
            } else {
                ll_line(lc, "%%%d = load %%SageValue, %%SageValue* %%%s", r, name);
            }
            free(name);
            return r;
        }
        case EXPR_CALL: {
            // Emit arguments
            int* arg_regs = NULL;
            if (expr->as.call.arg_count > 0) {
                arg_regs = SAGE_ALLOC(sizeof(int) * (size_t)expr->as.call.arg_count);
                for (int i = 0; i < expr->as.call.arg_count; i++) {
                    arg_regs[i] = llvm_emit_expr(lc, expr->as.call.args[i]);
                }
            }

            int r = llc_new_reg(lc);

            // Check for builtin calls
            if (expr->as.call.callee->type == EXPR_VARIABLE) {
                char* name = token_to_str(expr->as.call.callee->as.variable.name);

                if (strcmp(name, "str") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_str(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "len") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_len(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "tonumber") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_tonumber(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "push") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_push(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "pop") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_pop(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "range") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_range(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "dict_keys") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_keys(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "dict_values") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_values(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "dict_has") == 0 && expr->as.call.arg_count == 2) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_has(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                } else if (strcmp(name, "type") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_type(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "chr") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_chr(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "ord") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_ord(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "input") == 0 && expr->as.call.arg_count == 1) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_input(%%SageValue %%%d)", r, arg_regs[0]);
                } else if (strcmp(name, "gc_disable") == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                } else if (strcmp(name, "gc_enable") == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                } else if (strcmp(name, "gc_collect") == 0) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                } else {
                    // User function call
                    fprintf(lc->out, "  %%%d = call %%SageValue @sage_fn_%s(", r, name);
                    for (int i = 0; i < expr->as.call.arg_count; i++) {
                        if (i > 0) fputs(", ", lc->out);
                        fprintf(lc->out, "%%SageValue %%%d", arg_regs[i]);
                    }
                    fputs(")\n", lc->out);
                }

                free(name);
            } else if (expr->as.call.callee->type == EXPR_GET &&
                       expr->as.call.callee->as.get.object->type == EXPR_VARIABLE) {
                // Module method call: module.method(args...)
                char* mod_name = token_to_str(expr->as.call.callee->as.get.object->as.variable.name);
                char* method_name = token_to_str(expr->as.call.callee->as.get.property);

                if (llc_has_module(lc, mod_name) && strcmp(mod_name, "gpu") == 0) {
                    int gpu_r = llvm_try_emit_gpu_call(lc, method_name, arg_regs, expr->as.call.arg_count);
                    if (gpu_r >= 0) {
                        free(mod_name);
                        free(method_name);
                        free(arg_regs);
                        return gpu_r;
                    }
                }

                // io module: readfile, writefile
                int handled = 0;
                if (strcmp(mod_name, "io") == 0) {
                    if (strcmp(method_name, "readfile") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_readfile(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    } else if (strcmp(method_name, "writefile") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_writefile(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    }
                }
                // ml_native module: dispatch to sage_rt_* runtime functions
                if (!handled && strcmp(mod_name, "ml_native") == 0) {
                    if (strcmp(method_name, "load_weights") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_load_weights(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "matmul") == 0 && expr->as.call.arg_count == 5) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_matmul(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "rms_norm") == 0 && expr->as.call.arg_count == 5) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_rms_norm(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3], arg_regs[4]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "silu") == 0 && expr->as.call.arg_count == 1) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_silu(%%SageValue %%%d)", r, arg_regs[0]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "add") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_add(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "scale") == 0 && expr->as.call.arg_count == 2) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_scale(%%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "cross_entropy") == 0 && expr->as.call.arg_count == 4) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_cross_entropy(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arg_regs[0], arg_regs[1], arg_regs[2], arg_regs[3]);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "benchmark") == 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "gpu_available") == 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_bool(i32 0)", r);
                        handled = 1;
                    }
                    if (!handled && strcmp(method_name, "auto_parallel") == 0) {
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double 1.0)", r);
                        handled = 1;
                    }
                }

                // Fallback: emit as nil for unrecognized module calls
                if (!handled) {
                    ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                }
                free(mod_name);
                free(method_name);
            } else {
                // Dynamic call not supported in LLVM backend yet
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            }

            free(arg_regs);
            return r;
        }
        case EXPR_ARRAY: {
            int arr_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_array_new(i32 %d)", arr_reg, expr->as.array.count);
            for (int i = 0; i < expr->as.array.count; i++) {
                int elem = llvm_emit_expr(lc, expr->as.array.elements[i]);
                ll_line(lc, "call void @sage_rt_array_set(%%SageValue %%%d, i32 %d, %%SageValue %%%d)", arr_reg, i, elem);
            }
            return arr_reg;
        }
        case EXPR_INDEX: {
            int arr = llvm_emit_expr(lc, expr->as.index.array);
            int idx = llvm_emit_expr(lc, expr->as.index.index);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_index(%%SageValue %%%d, %%SageValue %%%d)", r, arr, idx);
            return r;
        }
        case EXPR_INDEX_SET: {
            int arr = llvm_emit_expr(lc, expr->as.index_set.array);
            int idx = llvm_emit_expr(lc, expr->as.index_set.index);
            int val = llvm_emit_expr(lc, expr->as.index_set.value);
            ll_line(lc, "call void @sage_rt_index_set(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", arr, idx, val);
            return val;
        }
        case EXPR_DICT: {
            int dict_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_dict_new()", dict_reg);
            for (int i = 0; i < expr->as.dict.count; i++) {
                int val = llvm_emit_expr(lc, expr->as.dict.values[i]);
                int str_id = llc_add_string(lc, expr->as.dict.keys[i]);
                size_t slen = strlen(expr->as.dict.keys[i]) + 1;
                int ptr = llc_new_reg(lc);
                ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                        ptr, slen, slen, str_id);
                ll_line(lc, "call void @sage_rt_dict_set(%%SageValue %%%d, i8* %%%d, %%SageValue %%%d)", dict_reg, ptr, val);
            }
            return dict_reg;
        }
        case EXPR_TUPLE: {
            int tup_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_tuple_new(i32 %d)", tup_reg, expr->as.tuple.count);
            for (int i = 0; i < expr->as.tuple.count; i++) {
                int elem = llvm_emit_expr(lc, expr->as.tuple.elements[i]);
                ll_line(lc, "call void @sage_rt_tuple_set(%%SageValue %%%d, i32 %d, %%SageValue %%%d)", tup_reg, i, elem);
            }
            return tup_reg;
        }
        case EXPR_SLICE: {
            int arr = llvm_emit_expr(lc, expr->as.slice.array);
            int start = llvm_emit_expr(lc, expr->as.slice.start);
            int end = llvm_emit_expr(lc, expr->as.slice.end);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_slice(%%SageValue %%%d, %%SageValue %%%d, %%SageValue %%%d)", r, arr, start, end);
            return r;
        }
        case EXPR_GET: {
            // Check for GPU module constant access: gpu.BUFFER_STORAGE etc.
            if (expr->as.get.object->type == EXPR_VARIABLE) {
                char* mod_name = token_to_str(expr->as.get.object->as.variable.name);
                char* prop_name = token_to_str(expr->as.get.property);
                if (llc_has_module(lc, mod_name) && strcmp(mod_name, "gpu") == 0) {
                    double const_val;
                    if (llvm_resolve_gpu_constant(prop_name, &const_val)) {
                        int r = llc_new_reg(lc);
                        ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %e)", r, const_val);
                        free(mod_name);
                        free(prop_name);
                        return r;
                    }
                }
                free(mod_name);
                free(prop_name);
            }
            int obj = llvm_emit_expr(lc, expr->as.get.object);
            char* prop = token_to_str(expr->as.get.property);
            int str_id = llc_add_string(lc, prop);
            size_t slen = strlen(prop) + 1;
            int ptr = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                    ptr, slen, slen, str_id);
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_get_attr(%%SageValue %%%d, i8* %%%d)", r, obj, ptr);
            free(prop);
            return r;
        }
        case EXPR_SET: {
            if (expr->as.set.object == NULL) {
                // Variable assignment: name = value
                int val = llvm_emit_expr(lc, expr->as.set.value);
                char* name = token_to_str(expr->as.set.property);
                // Check if it's a global variable
                int is_global = 0;
                for (int i = 0; i < lc->global_count; i++) {
                    if (strcmp(lc->global_names[i], name) == 0) { is_global = 1; break; }
                }
                if (is_global) {
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* @%s", val, name);
                } else {
                    ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", val, name);
                }
                free(name);
                return val;
            }
            // Property set: object.property = value
            int obj = llvm_emit_expr(lc, expr->as.set.object);
            int val = llvm_emit_expr(lc, expr->as.set.value);
            char* prop = token_to_str(expr->as.set.property);
            int str_id = llc_add_string(lc, prop);
            size_t slen = strlen(prop) + 1;
            int ptr = llc_new_reg(lc);
            ll_line(lc, "%%%d = getelementptr [%zu x i8], [%zu x i8]* @.str.%d, i64 0, i64 0",
                    ptr, slen, slen, str_id);
            ll_line(lc, "call void @sage_rt_set_attr(%%SageValue %%%d, i8* %%%d, %%SageValue %%%d)", obj, ptr, val);
            free(prop);
            return val;
        }
        case EXPR_AWAIT: {
            // Await not supported in LLVM backend
            fprintf(stderr, "LLVM backend: await not supported in compiled mode\n");
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
        case EXPR_SUPER: {
            // super.method() in LLVM: emits nil (classes are interpreter-only for now)
            // The LLVM backend doesn't support full class dispatch yet
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
        default: {
            int r = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
            return r;
        }
    }
}

// ============================================================================
// Statement Emission
// ============================================================================

static void llvm_emit_stmt(LLVMCompiler* lc, Stmt* stmt);

static void llvm_emit_stmt_list(LLVMCompiler* lc, Stmt* head) {
    for (Stmt* s = head; s != NULL; s = s->next) {
        if (lc->block_terminated) break;
        llvm_emit_stmt(lc, s);
    }
}

static void llvm_emit_stmt(LLVMCompiler* lc, Stmt* stmt) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT: {
            int r = llvm_emit_expr(lc, stmt->as.print.expression);
            ll_line(lc, "call void @sage_rt_print(%%SageValue %%%d)", r);
            break;
        }
        case STMT_EXPRESSION: {
            llvm_emit_expr(lc, stmt->as.expression);
            break;
        }
        case STMT_LET: {
            char* name = token_to_str(stmt->as.let.name);
            int val = llvm_emit_expr(lc, stmt->as.let.initializer);
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", val, name);
            free(name);
            break;
        }
        case STMT_IF: {
            int cond_val = llvm_emit_expr(lc, stmt->as.if_stmt.condition);
            int bool_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", bool_reg, cond_val);
            int cmp_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", cmp_reg, bool_reg);

            int then_label = llc_new_label(lc);
            int else_label = llc_new_label(lc);
            int merge_label = llc_new_label(lc);

            if (stmt->as.if_stmt.else_branch != NULL) {
                ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, then_label, else_label);
            } else {
                ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, then_label, merge_label);
            }

            ll_emit(lc, "L%d:\n", then_label);
            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.if_stmt.then_branch);
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", merge_label);

            if (stmt->as.if_stmt.else_branch != NULL) {
                ll_emit(lc, "L%d:\n", else_label);
                lc->block_terminated = 0;
                llvm_emit_stmt_list(lc, stmt->as.if_stmt.else_branch);
                if (!lc->block_terminated) ll_line(lc, "br label %%L%d", merge_label);
            }

            ll_emit(lc, "L%d:\n", merge_label);
            lc->block_terminated = 0;
            break;
        }
        case STMT_WHILE: {
            if (lc->loop_depth >= 64) {
                fprintf(stderr, "LLVM backend: loop nesting too deep (max 64)\n");
                lc->failed = 1;
                return;
            }
            int cond_label = llc_new_label(lc);
            int body_label = llc_new_label(lc);
            int end_label = llc_new_label(lc);

            // Push loop labels for break/continue
            lc->loop_cond_labels[lc->loop_depth] = cond_label;
            lc->loop_end_labels[lc->loop_depth] = end_label;
            lc->loop_depth++;

            ll_line(lc, "br label %%L%d", cond_label);
            ll_emit(lc, "L%d:\n", cond_label);

            int cond_val = llvm_emit_expr(lc, stmt->as.while_stmt.condition);
            int bool_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i32 @sage_rt_get_bool(%%SageValue %%%d)", bool_reg, cond_val);
            int cmp_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp ne i32 %%%d, 0", cmp_reg, bool_reg);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp_reg, body_label, end_label);

            ll_emit(lc, "L%d:\n", body_label);
            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.while_stmt.body);
            if (!lc->block_terminated) ll_line(lc, "br label %%L%d", cond_label);

            ll_emit(lc, "L%d:\n", end_label);
            lc->block_terminated = 0;
            lc->loop_depth--;
            break;
        }
        case STMT_BLOCK:
            llvm_emit_stmt_list(lc, stmt->as.block.statements);
            break;
        case STMT_RETURN: {
            if (lc->block_terminated) break;
            if (stmt->as.ret.value != NULL) {
                int r = llvm_emit_expr(lc, stmt->as.ret.value);
                ll_line(lc, "ret %%SageValue %%%d", r);
            } else {
                int r = llc_new_reg(lc);
                ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", r);
                ll_line(lc, "ret %%SageValue %%%d", r);
            }
            lc->block_terminated = 1;
            break;
        }
        case STMT_PROC:
            // Procs handled at top level
            break;
        case STMT_FOR: {
            // for variable in iterable: body
            if (lc->loop_depth >= 64) {
                fprintf(stderr, "LLVM backend: loop nesting too deep (max 64)\n");
                lc->failed = 1;
                return;
            }
            // Emit iterable (must be array)
            int iter = llvm_emit_expr(lc, stmt->as.for_stmt.iterable);
            int len_reg = llc_new_reg(lc);
            ll_line(lc, "%%%d = call i32 @sage_rt_array_len(%%SageValue %%%d)", len_reg, iter);

            // Loop variable (alloca already emitted by collect_local_names at function entry)
            char* var_name = token_to_str(stmt->as.for_stmt.variable);
            int idx_ptr = llc_new_reg(lc);
            ll_line(lc, "%%%d = alloca i32", idx_ptr);
            ll_line(lc, "store i32 0, i32* %%%d", idx_ptr);

            int cond_label = llc_new_label(lc);
            int body_label = llc_new_label(lc);
            int end_label = llc_new_label(lc);

            // Push loop labels for break/continue
            lc->loop_cond_labels[lc->loop_depth] = cond_label;
            lc->loop_end_labels[lc->loop_depth] = end_label;
            lc->loop_depth++;

            ll_line(lc, "br label %%L%d", cond_label);
            ll_emit(lc, "L%d:\n", cond_label);

            int cur_idx = llc_new_reg(lc);
            ll_line(lc, "%%%d = load i32, i32* %%%d", cur_idx, idx_ptr);
            int cmp = llc_new_reg(lc);
            ll_line(lc, "%%%d = icmp slt i32 %%%d, %%%d", cmp, cur_idx, len_reg);
            ll_line(lc, "br i1 %%%d, label %%L%d, label %%L%d", cmp, body_label, end_label);

            ll_emit(lc, "L%d:\n", body_label);

            // Get current element: arr[idx]
            // Convert i32 idx to SageValue number for indexing
            int idx_double = llc_new_reg(lc);
            ll_line(lc, "%%%d = sitofp i32 %%%d to double", idx_double, cur_idx);
            int idx_sage = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_number(double %%%d)", idx_sage, idx_double);
            int elem = llc_new_reg(lc);
            ll_line(lc, "%%%d = call %%SageValue @sage_rt_index(%%SageValue %%%d, %%SageValue %%%d)", elem, iter, idx_sage);

            // Store element in loop variable
            ll_line(lc, "store %%SageValue %%%d, %%SageValue* %%%s", elem, var_name);

            lc->block_terminated = 0;
            llvm_emit_stmt_list(lc, stmt->as.for_stmt.body);

            // Increment counter
            int next_idx = llc_new_reg(lc);
            ll_line(lc, "%%%d = add i32 %%%d, 1", next_idx, cur_idx);
            ll_line(lc, "store i32 %%%d, i32* %%%d", next_idx, idx_ptr);
            ll_line(lc, "br label %%L%d", cond_label);

            ll_emit(lc, "L%d:\n", end_label);

            lc->loop_depth--;
            free(var_name);
            break;
        }
        case STMT_BREAK: {
            if (lc->loop_depth > 0 && !lc->block_terminated) {
                ll_line(lc, "br label %%L%d", lc->loop_end_labels[lc->loop_depth - 1]);
                lc->block_terminated = 1;
                // Emit unreachable label for any following code
                int unr = llc_new_label(lc);
                ll_emit(lc, "L%d:\n", unr);
                lc->block_terminated = 0;
            }
            break;
        }
        case STMT_CONTINUE: {
            if (lc->loop_depth > 0 && !lc->block_terminated) {
                ll_line(lc, "br label %%L%d", lc->loop_cond_labels[lc->loop_depth - 1]);
                lc->block_terminated = 1;
                int unr = llc_new_label(lc);
                ll_emit(lc, "L%d:\n", unr);
                lc->block_terminated = 0;
            }
            break;
        }
        case STMT_CLASS:
            // Classes are collected and emitted at the top level
            break;
        case STMT_TRY: {
            // Simplified try/catch: execute try block, ignore catch for now
            // (Full setjmp/longjmp exception handling would require a different approach)
            llvm_emit_stmt_list(lc, stmt->as.try_stmt.try_block);
            break;
        }
        case STMT_RAISE: {
            // Emit the exception value, print it, then abort
            if (stmt->as.raise.exception != NULL) {
                int val = llvm_emit_expr(lc, stmt->as.raise.exception);
                ll_line(lc, "call void @sage_rt_print(%%SageValue %%%d)", val);
            }
            ll_line(lc, "call void @abort()");
            ll_line(lc, "unreachable");
            // Need a landing pad for any code after the raise
            int unr = llc_new_label(lc);
            ll_emit(lc, "L%d:\n", unr);
            break;
        }
        case STMT_IMPORT: {
            // Track imported modules for GPU/graphics support in compiled mode
            const char* mod_name = stmt->as.import.module_name;
            if (mod_name != NULL) {
                llc_add_module(lc, mod_name);
            }
            break;
        }
        case STMT_MATCH: {
            int match_val = llvm_emit_expr(lc, stmt->as.match_stmt.value);
            int lbl_end = llc_new_label(lc);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                CaseClause* clause = stmt->as.match_stmt.cases[i];
                int pat_reg = llvm_emit_expr(lc, clause->pattern);
                int cmp_reg = lc->next_reg++;
                int bool_reg = lc->next_reg++;
                int lbl_then = llc_new_label(lc);
                int lbl_next = llc_new_label(lc);
                fprintf(lc->out, "  %%%d = call %%SageValue @sage_rt_eq(%%SageValue %%%d, %%SageValue %%%d)\n", cmp_reg, match_val, pat_reg);
                fprintf(lc->out, "  %%%d = call i1 @sage_rt_get_bool(%%SageValue %%%d)\n", bool_reg, cmp_reg);
                fprintf(lc->out, "  br i1 %%%d, label %%L%d, label %%L%d\n", bool_reg, lbl_then, lbl_next);
                fprintf(lc->out, "L%d:\n", lbl_then);
                lc->block_terminated = 0;
                llvm_emit_stmt_list(lc, clause->body);
                if (!lc->block_terminated) {
                    fprintf(lc->out, "  br label %%L%d\n", lbl_end);
                }
                fprintf(lc->out, "L%d:\n", lbl_next);
                lc->block_terminated = 0;
            }
            if (stmt->as.match_stmt.default_case) {
                llvm_emit_stmt_list(lc, stmt->as.match_stmt.default_case);
            }
            if (!lc->block_terminated) {
                fprintf(lc->out, "  br label %%L%d\n", lbl_end);
            }
            fprintf(lc->out, "L%d:\n", lbl_end);
            lc->block_terminated = 0;
            break;
        }
        case STMT_DEFER:
            // In LLVM compiled code, emit defer body inline (best-effort)
            llvm_emit_stmt_list(lc, stmt->as.defer.statement);
            break;
        case STMT_YIELD:
        case STMT_ASYNC_PROC:
            fprintf(stderr, "LLVM backend: unsupported statement type %d (yield/async)\n", stmt->type);
            break;
    }
}

// ============================================================================
// Local Variable Collection (pre-allocate all locals with alloca at entry)
// ============================================================================

static void collect_local_names(Stmt* stmt, char*** names, int* count, int* cap) {
    for (Stmt* s = stmt; s != NULL; s = s->next) {
        if (s->type == STMT_LET) {
            char* name = token_to_str(s->as.let.name);
            // Check for duplicates
            int dup = 0;
            for (int i = 0; i < *count; i++) {
                if (strcmp((*names)[i], name) == 0) { dup = 1; break; }
            }
            if (!dup) {
                if (*count >= *cap) {
                    *cap = *cap ? *cap * 2 : 16;
                    *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                }
                (*names)[(*count)++] = name;
            } else {
                free(name);
            }
        }
        // Recurse into sub-blocks
        if (s->type == STMT_IF) {
            collect_local_names(s->as.if_stmt.then_branch, names, count, cap);
            collect_local_names(s->as.if_stmt.else_branch, names, count, cap);
        } else if (s->type == STMT_WHILE) {
            collect_local_names(s->as.while_stmt.body, names, count, cap);
        } else if (s->type == STMT_FOR) {
            // For loop variable
            char* var = token_to_str(s->as.for_stmt.variable);
            int dup = 0;
            for (int i = 0; i < *count; i++) {
                if (strcmp((*names)[i], var) == 0) { dup = 1; break; }
            }
            if (!dup) {
                if (*count >= *cap) {
                    *cap = *cap ? *cap * 2 : 16;
                    *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                }
                (*names)[(*count)++] = var;
            } else {
                free(var);
            }
            collect_local_names(s->as.for_stmt.body, names, count, cap);
        } else if (s->type == STMT_BLOCK) {
            collect_local_names(s->as.block.statements, names, count, cap);
        } else if (s->type == STMT_TRY) {
            collect_local_names(s->as.try_stmt.try_block, names, count, cap);
        } else if (s->type == STMT_IMPORT) {
            // Import binding variable (e.g. import agent.critic -> "critic")
            const char* bind = s->as.import.alias;
            if (bind == NULL && s->as.import.item_count == 0 && s->as.import.module_name != NULL) {
                const char* dot = strrchr(s->as.import.module_name, '.');
                bind = dot ? dot + 1 : s->as.import.module_name;
            }
            if (bind != NULL) {
                char* var = SAGE_STRDUP(bind);
                int dup = 0;
                for (int i = 0; i < *count; i++) {
                    if (strcmp((*names)[i], var) == 0) { dup = 1; break; }
                }
                if (!dup) {
                    if (*count >= *cap) {
                        *cap = *cap ? *cap * 2 : 16;
                        *names = SAGE_REALLOC(*names, sizeof(char*) * (size_t)*cap);
                    }
                    (*names)[(*count)++] = var;
                } else {
                    free(var);
                }
            }
        }
    }
}

// ============================================================================
// Function Definition Emission
// ============================================================================

static void llvm_emit_function(LLVMCompiler* lc, Stmt* proc) {
    lc->block_terminated = 0;
    char* name = token_to_str(proc->as.proc.name);

    fprintf(lc->out, "define %%SageValue @sage_fn_%s(", name);
    for (int i = 0; i < proc->as.proc.param_count; i++) {
        if (i > 0) fputs(", ", lc->out);
        char* param = token_to_str(proc->as.proc.params[i]);
        fprintf(lc->out, "%%SageValue %%arg_%s", param);
        free(param);
    }
    fputs(") {\n", lc->out);
    fputs("entry:\n", lc->out);

    // Allocate parameter variables
    for (int i = 0; i < proc->as.proc.param_count; i++) {
        char* param = token_to_str(proc->as.proc.params[i]);
        ll_line(lc, "%%%s = alloca %%SageValue", param);
        ll_line(lc, "store %%SageValue %%arg_%s, %%SageValue* %%%s", param, param);
        free(param);
    }

    // Collect and allocate local variables at function entry
    char** locals = NULL;
    int local_count = 0, local_cap = 0;
    collect_local_names(proc->as.proc.body, &locals, &local_count, &local_cap);
    for (int i = 0; i < local_count; i++) {
        // Skip if it's already a parameter
        int is_param = 0;
        for (int j = 0; j < proc->as.proc.param_count; j++) {
            char* p = token_to_str(proc->as.proc.params[j]);
            if (strcmp(p, locals[i]) == 0) is_param = 1;
            free(p);
            if (is_param) break;
        }
        if (!is_param) {
            ll_line(lc, "%%%s = alloca %%SageValue", locals[i]);
        }
        free(locals[i]);
    }
    free(locals);

    // Emit body
    llvm_emit_stmt_list(lc, proc->as.proc.body);

    // Default return nil (only if block not already terminated)
    if (!lc->block_terminated) {
        int nil_reg = llc_new_reg(lc);
        ll_line(lc, "%%%d = call %%SageValue @sage_rt_nil()", nil_reg);
        ll_line(lc, "ret %%SageValue %%%d", nil_reg);
    }

    fputs("}\n\n", lc->out);
    free(name);
}

// ============================================================================
// Main Compilation Function
// ============================================================================

static int write_llvm_output(const char* source, const char* input_path, const char* output_path,
                             int opt_level, int debug_info) {
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "Could not open LLVM output \"%s\": %s\n", output_path, strerror(errno));
        return 0;
    }

    LLVMCompiler lc;
    memset(&lc, 0, sizeof(lc));
    lc.out = out;
    lc.input_path = input_path;
    lc.next_reg = 0;
    lc.next_label = 0;

    Stmt* program = parse_program(source);

    // Run optimization passes
    if (opt_level > 0) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        program = run_passes(program, &pass_ctx);
    }

    // Collect symbols
    llvm_collect_symbols(&lc, program);
    if (lc.failed) {
        fclose(out);
        free_stmt(program);
        llc_free(&lc);
        return 0;
    }

    // Emit type definitions and runtime declarations
    emit_type_definitions(&lc);

    // Emit string constants (first pass to collect, then we'll fix up)
    // We do a two-pass approach: first emit functions, capture strings, then prepend
    // For simplicity, emit strings after functions (LLVM allows forward refs)

    // Emit global variables
    for (int i = 0; i < lc.global_count; i++) {
        fprintf(out, "@%s = internal global %%SageValue zeroinitializer\n", lc.global_names[i]);
    }
    if (lc.global_count > 0) fputc('\n', out);

    // Emit function definitions
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            lc.next_reg = 0;  // Reset per function
            llvm_emit_function(&lc, s);
        } else if (s->type == STMT_CLASS) {
            // Emit each class method as a standalone function
            char* cname = token_to_str(s->as.class_stmt.name);
            for (Stmt* m = s->as.class_stmt.methods; m != NULL; m = m->next) {
                if (m->type == STMT_PROC) {
                    // Temporarily rename the proc to ClassName_methodName
                    Token orig_name = m->as.proc.name;
                    char* mname = class_method_name(cname, orig_name);
                    // Create a modified token pointing to the new name
                    Token new_name = orig_name;
                    new_name.start = mname;
                    new_name.length = (int)strlen(mname);
                    m->as.proc.name = new_name;
                    lc.next_reg = 0;
                    llvm_emit_function(&lc, m);
                    m->as.proc.name = orig_name;  // Restore
                    free(mname);
                }
            }
            free(cname);
        }
    }

    // Emit main function
    lc.next_reg = 0;
    fprintf(out, "define i32 @main() {\n");
    fprintf(out, "entry:\n");

    // Pre-allocate all local variables used in main (for/let inside loops/blocks)
    {
        char** main_locals = NULL;
        int main_local_count = 0, main_local_cap = 0;
        // Collect locals from non-proc, non-class top-level statements
        for (Stmt* ms = program; ms != NULL; ms = ms->next) {
            if (ms->type != STMT_PROC && ms->type != STMT_CLASS) {
                // Wrap single stmt in a temporary chain for collect
                Stmt* saved_next = ms->next;
                ms->next = NULL;
                collect_local_names(ms, &main_locals, &main_local_count, &main_local_cap);
                ms->next = saved_next;
            }
        }
        for (int ml = 0; ml < main_local_count; ml++) {
            // Skip globals (they use @name, not %name)
            int is_global = 0;
            for (int gi = 0; gi < lc.global_count; gi++) {
                if (strcmp(lc.global_names[gi], main_locals[ml]) == 0) { is_global = 1; break; }
            }
            if (!is_global) {
                ll_line(&lc, "%%%s = alloca %%SageValue", main_locals[ml]);
            }
            free(main_locals[ml]);
        }
        free(main_locals);
    }

    // Emit top-level statements
    for (Stmt* s = program; s != NULL; s = s->next) {
        if (s->type != STMT_PROC && s->type != STMT_CLASS) {
            if (s->type == STMT_LET) {
                char* name = token_to_str(s->as.let.name);
                int val = llvm_emit_expr(&lc, s->as.let.initializer);
                ll_line(&lc, "store %%SageValue %%%d, %%SageValue* @%s", val, name);
                free(name);
            } else {
                llvm_emit_stmt(&lc, s);
            }
        }
    }

    ll_line(&lc, "ret i32 0");
    fprintf(out, "}\n\n");

    // Emit string constants
    for (int i = 0; i < lc.string_count; i++) {
        size_t slen = strlen(lc.strings[i]) + 1;
        fprintf(out, "@.str.%d = private unnamed_addr constant [%zu x i8] c\"", i, slen);
        emit_escaped_string(out, lc.strings[i]);
        fprintf(out, "\\00\"\n");
    }

    fclose(out);
    free_stmt(program);
    llc_free(&lc);
    return 1;
}

// ============================================================================
// Public API
// ============================================================================

int compile_source_to_llvm_ir(const char* source, const char* input_path,
                              const char* output_path, int opt_level, int debug_info) {
    return write_llvm_output(source, input_path, output_path, opt_level, debug_info);
}

int compile_source_to_llvm_executable(const char* source, const char* input_path,
                                      const char* ll_output_path, const char* exe_output_path,
                                      int opt_level, int debug_info) {
    if (!write_llvm_output(source, input_path, ll_output_path, opt_level, debug_info)) {
        return 0;
    }

    // Use clang to compile the LLVM IR directly
    // clang can handle .ll files natively
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Could not fork for LLVM compilation.\n");
        return 0;
    }

    if (pid == 0) {
        // Find the LLVM runtime object next to the sage executable
        const char* rt_paths[] = { "obj/llvm_runtime.o", "./llvm_runtime.o", NULL };
        const char* rt_path = NULL;
        for (int i = 0; rt_paths[i] != NULL; i++) {
            if (access(rt_paths[i], F_OK) == 0) { rt_path = rt_paths[i]; break; }
        }

        // Find the GPU API object for GPU support
        const char* gpu_paths[] = { "obj/gpu_api.o", "./gpu_api.o", NULL };
        const char* gpu_path = NULL;
        for (int i = 0; gpu_paths[i] != NULL; i++) {
            if (access(gpu_paths[i], F_OK) == 0) { gpu_path = gpu_paths[i]; break; }
        }

        // Build clang argument list dynamically based on available libraries
        const char* args[32];
        int argc = 0;
        args[argc++] = "clang";
        args[argc++] = "-O2";
        args[argc++] = ll_output_path;
        if (rt_path) args[argc++] = rt_path;
        if (gpu_path) args[argc++] = gpu_path;
        args[argc++] = "-o";
        args[argc++] = exe_output_path;
        args[argc++] = "-lm";
        args[argc++] = "-lpthread";
        // Link GPU libraries if gpu_api.o is available
        if (gpu_path) {
            // Vulkan
            #ifdef SAGE_HAS_VULKAN
            args[argc++] = "-lvulkan";
            #endif
            // GLFW
            #ifdef SAGE_HAS_GLFW
            args[argc++] = "-lglfw";
            #endif
            // OpenGL (always try — linker will skip if unused)
            args[argc++] = "-lGL";
            args[argc++] = "-ldl";
        }
        args[argc] = NULL;

        execvp("clang", (char* const*)args);
        // If clang not found, fall through
        fprintf(stderr, "Could not execute clang: %s\n", strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Could not wait for clang.\n");
        return 0;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "LLVM compilation failed.\n");
        return 0;
    }

    return 1;
}
