#define _DEFAULT_SOURCE
#include "compiler.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ast.h"
#include "diagnostic.h"
#include "lexer.h"
#include "parser.h"
#include "pass.h"

typedef struct NameEntry {
    char* sage_name;
    char* c_name;
    struct NameEntry* next;
} NameEntry;

typedef struct ProcEntry {
    char* sage_name;
    char* c_name;
    int param_count;
    struct ProcEntry* next;
} ProcEntry;

typedef struct ClassInfo {
    char* class_name;
    char* parent_name;
    Stmt* methods;
    struct ClassInfo* next;
} ClassInfo;

typedef struct ImportedModule {
    char* name;
    char* path;
    char* source;
    Stmt* ast;
    struct ImportedModule* next;
} ImportedModule;

typedef struct {
    char* data;
    size_t len;
    size_t cap;
} StringBuffer;

typedef struct {
    FILE* out;
    const char* input_path;
    int failed;
    int in_function_body;
    int indent;
    int next_unique_id;
    NameEntry* globals;
    ProcEntry* procs;
    NameEntry* locals;
    ClassInfo* classes;
    ImportedModule* modules;
} Compiler;

typedef enum {
    COMPILER_TARGET_HOST,
    COMPILER_TARGET_PICO
} CompilerTarget;

static void sb_init(StringBuffer* sb) {
    sb->cap = 128;
    sb->len = 0;
    sb->data = malloc(sb->cap);
    if (sb->data == NULL) {
        fprintf(stderr, "Out of memory in compiler string buffer.\n");
        exit(1);
    }
    sb->data[0] = '\0';
}

static void sb_reserve(StringBuffer* sb, size_t extra) {
    size_t needed = sb->len + extra + 1;
    if (needed <= sb->cap) {
        return;
    }

    while (sb->cap < needed) {
        sb->cap *= 2;
    }

    char* next = realloc(sb->data, sb->cap);
    if (next == NULL) {
        fprintf(stderr, "Out of memory growing compiler string buffer.\n");
        exit(1);
    }
    sb->data = next;
}

static void sb_append(StringBuffer* sb, const char* text) {
    size_t len = strlen(text);
    sb_reserve(sb, len);
    memcpy(sb->data + sb->len, text, len + 1);
    sb->len += len;
}

static void sb_append_char(StringBuffer* sb, char ch) {
    sb_reserve(sb, 1);
    sb->data[sb->len++] = ch;
    sb->data[sb->len] = '\0';
}

static void sb_appendf(StringBuffer* sb, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    va_list args_copy;
    va_copy(args_copy, args);
    int needed = vsnprintf(NULL, 0, fmt, args_copy);
    va_end(args_copy);
    if (needed < 0) {
        fprintf(stderr, "Compiler formatting error.\n");
        exit(1);
    }

    sb_reserve(sb, (size_t)needed);
    vsnprintf(sb->data + sb->len, sb->cap - sb->len, fmt, args);
    sb->len += (size_t)needed;
    va_end(args);
}

static char* sb_take(StringBuffer* sb) {
    char* result = sb->data;
    sb->data = NULL;
    sb->len = 0;
    sb->cap = 0;
    return result;
}

static char* str_dup(const char* text) {
    size_t len = strlen(text);
    char* copy = malloc(len + 1);
    if (copy == NULL) {
        fprintf(stderr, "Out of memory duplicating compiler string.\n");
        exit(1);
    }
    memcpy(copy, text, len + 1);
    return copy;
}

static char* token_to_string(Token token) {
    char* text = malloc((size_t)token.length + 1);
    if (text == NULL) {
        fprintf(stderr, "Out of memory duplicating token.\n");
        exit(1);
    }
    memcpy(text, token.start, (size_t)token.length);
    text[token.length] = '\0';
    return text;
}

static char* sanitize_identifier(const char* text) {
    size_t len = strlen(text);
    StringBuffer sb;
    sb_init(&sb);

    if (len == 0 || isdigit((unsigned char)text[0])) {
        sb_append_char(&sb, '_');
    }

    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)text[i];
        if (isalnum(ch) || ch == '_') {
            sb_append_char(&sb, (char)ch);
        } else {
            sb_append_char(&sb, '_');
        }
    }

    return sb_take(&sb);
}

static char* escape_c_string(const char* text) {
    StringBuffer sb;
    sb_init(&sb);

    for (size_t i = 0; text[i] != '\0'; i++) {
        switch (text[i]) {
            case '\\':
                sb_append(&sb, "\\\\");
                break;
            case '"':
                sb_append(&sb, "\\\"");
                break;
            case '\n':
                sb_append(&sb, "\\n");
                break;
            case '\r':
                sb_append(&sb, "\\r");
                break;
            case '\t':
                sb_append(&sb, "\\t");
                break;
            default:
                sb_append_char(&sb, text[i]);
                break;
        }
    }

    return sb_take(&sb);
}

static void free_name_entries(NameEntry* entry) {
    while (entry != NULL) {
        NameEntry* next = entry->next;
        free(entry->sage_name);
        free(entry->c_name);
        free(entry);
        entry = next;
    }
}

static void free_proc_entries(ProcEntry* entry) {
    while (entry != NULL) {
        ProcEntry* next = entry->next;
        free(entry->sage_name);
        free(entry->c_name);
        free(entry);
        entry = next;
    }
}

static NameEntry* find_name_entry(NameEntry* list, const char* sage_name) {
    while (list != NULL) {
        if (strcmp(list->sage_name, sage_name) == 0) {
            return list;
        }
        list = list->next;
    }
    return NULL;
}

static ProcEntry* find_proc_entry(ProcEntry* list, const char* sage_name) {
    while (list != NULL) {
        if (strcmp(list->sage_name, sage_name) == 0) {
            return list;
        }
        list = list->next;
    }
    return NULL;
}

static int token_span(const Token* token) {
    return (token != NULL && token->length > 0) ? token->length : 1;
}

static void compiler_verror(Compiler* compiler, const Token* token,
                            const char* help, const char* fmt, va_list args) {
    if (token != NULL) {
        sage_vprint_token_diagnosticf("error", token, compiler->input_path,
                                      token_span(token), help, fmt, args);
    } else {
        fprintf(stderr, "error");
        if (compiler->input_path != NULL) {
            fprintf(stderr, " in %s", compiler->input_path);
        }
        fprintf(stderr, ": ");
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        if (help != NULL && help[0] != '\0') {
            fprintf(stderr, "  = help: %s\n", help);
        }
    }
    compiler->failed = 1;
}

static void compiler_error_at(Compiler* compiler, const Token* token,
                              const char* help, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    compiler_verror(compiler, token, help, fmt, args);
    va_end(args);
}

static void compiler_error(Compiler* compiler, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    compiler_verror(compiler, NULL, NULL, fmt, args);
    va_end(args);
}

static const Token* expr_token(const Expr* expr) {
    if (expr == NULL) return NULL;

    switch (expr->type) {
        case EXPR_BINARY:
            return &expr->as.binary.op;
        case EXPR_VARIABLE:
            return &expr->as.variable.name;
        case EXPR_CALL:
            return expr_token(expr->as.call.callee);
        case EXPR_INDEX:
            return expr_token(expr->as.index.array);
        case EXPR_INDEX_SET:
            return expr_token(expr->as.index_set.array);
        case EXPR_SLICE:
            return expr_token(expr->as.slice.array);
        case EXPR_GET:
            return &expr->as.get.property;
        case EXPR_SET:
            return &expr->as.set.property;
        case EXPR_AWAIT:
            return expr_token(expr->as.await.expression);
        default:
            return NULL;
    }
}

static const Token* stmt_token(const Stmt* stmt) {
    if (stmt == NULL) return NULL;

    switch (stmt->type) {
        case STMT_PRINT:
            return expr_token(stmt->as.print.expression);
        case STMT_EXPRESSION:
            return expr_token(stmt->as.expression);
        case STMT_LET:
            return &stmt->as.let.name;
        case STMT_IF:
            return expr_token(stmt->as.if_stmt.condition);
        case STMT_WHILE:
            return expr_token(stmt->as.while_stmt.condition);
        case STMT_PROC:
            return &stmt->as.proc.name;
        case STMT_FOR:
            return &stmt->as.for_stmt.variable;
        case STMT_RETURN:
            return expr_token(stmt->as.ret.value);
        case STMT_CLASS:
            return &stmt->as.class_stmt.name;
        case STMT_RAISE:
            return expr_token(stmt->as.raise.exception);
        case STMT_ASYNC_PROC:
            return &stmt->as.async_proc.name;
        default:
            return NULL;
    }
}

static void emit_indent(Compiler* compiler) {
    for (int i = 0; i < compiler->indent; i++) {
        fputs("    ", compiler->out);
    }
}

static void emit_line(Compiler* compiler, const char* fmt, ...) {
    emit_indent(compiler);
    va_list args;
    va_start(args, fmt);
    vfprintf(compiler->out, fmt, args);
    va_end(args);
    fputc('\n', compiler->out);
}

static char* make_unique_name(Compiler* compiler, const char* prefix, const char* sage_name) {
    char* sanitized = sanitize_identifier(sage_name);
    StringBuffer sb;
    sb_init(&sb);
    sb_appendf(&sb, "%s_%s_%d", prefix, sanitized, compiler->next_unique_id++);
    free(sanitized);
    return sb_take(&sb);
}

static NameEntry* add_name_entry(Compiler* compiler, NameEntry** list,
                                 const char* sage_name, const char* prefix) {
    NameEntry* existing = find_name_entry(*list, sage_name);
    if (existing != NULL) {
        return existing;
    }

    NameEntry* entry = malloc(sizeof(NameEntry));
    if (entry == NULL) {
        fprintf(stderr, "Out of memory creating compiler symbol entry.\n");
        exit(1);
    }

    entry->sage_name = str_dup(sage_name);
    entry->c_name = make_unique_name(compiler, prefix, sage_name);
    entry->next = *list;
    *list = entry;
    return entry;
}

static ProcEntry* add_proc_entry(Compiler* compiler, const char* sage_name,
                                 int param_count, const Token* token) {
    ProcEntry* existing = find_proc_entry(compiler->procs, sage_name);
    if (existing != NULL) {
        if (existing->param_count != param_count) {
            compiler_error_at(compiler, token,
                              "rename one of the procedures or keep the parameter counts consistent",
                              "procedure '%s' is redefined with %d parameter%s; the earlier definition used %d",
                              sage_name, param_count, param_count == 1 ? "" : "s",
                              existing->param_count);
        }
        return existing;
    }

    ProcEntry* entry = malloc(sizeof(ProcEntry));
    if (entry == NULL) {
        fprintf(stderr, "Out of memory creating compiler proc entry.\n");
        exit(1);
    }

    entry->sage_name = str_dup(sage_name);
    entry->c_name = make_unique_name(compiler, "sage_fn", sage_name);
    entry->param_count = param_count;
    entry->next = compiler->procs;
    compiler->procs = entry;
    return entry;
}

static ClassInfo* find_class_info(ClassInfo* list, const char* name) {
    for (ClassInfo* c = list; c != NULL; c = c->next) {
        if (strcmp(c->class_name, name) == 0) return c;
    }
    return NULL;
}

static int bounded_edit_distance(const char* left, const char* right) {
    size_t left_len = strlen(left);
    size_t right_len = strlen(right);

    if (left_len == 0) return (int)right_len;
    if (right_len == 0) return (int)left_len;
    if (left_len > 63 || right_len > 63) return 99;

    int previous[64];
    int current[64];

    for (size_t j = 0; j <= right_len; j++) {
        previous[j] = (int)j;
    }

    for (size_t i = 1; i <= left_len; i++) {
        current[0] = (int)i;
        for (size_t j = 1; j <= right_len; j++) {
            int cost = left[i - 1] == right[j - 1] ? 0 : 1;
            int deletion = previous[j] + 1;
            int insertion = current[j - 1] + 1;
            int substitution = previous[j - 1] + cost;
            int best = deletion < insertion ? deletion : insertion;
            current[j] = substitution < best ? substitution : best;
        }
        memcpy(previous, current, sizeof(int) * (right_len + 1));
    }

    return previous[right_len];
}

static void consider_suggestion(const char* needle, const char* candidate,
                                const char** best_name, int* best_score) {
    if (candidate == NULL || candidate[0] == '\0' || strcmp(candidate, needle) == 0) {
        return;
    }

    int score = bounded_edit_distance(needle, candidate);
    if (score > 3) {
        return;
    }

    if (*best_name == NULL || score < *best_score ||
        (score == *best_score && strcmp(candidate, *best_name) < 0)) {
        *best_name = candidate;
        *best_score = score;
    }
}

static const char* find_name_suggestion(Compiler* compiler, const char* name) {
    static const char* builtins[] = {
        "str", "len", "push", "pop", "range", "tonumber",
        "dict_keys", "dict_values", "dict_has", "dict_delete",
        "upper", "lower", "strip", "split", "join", "replace",
        "mem_alloc", "mem_free", "mem_read", "mem_write", "mem_size",
        "struct_def", "struct_new", "struct_get", "struct_set", "struct_size",
        "clock", "input", "slice", "asm_arch"
    };

    const char* best_name = NULL;
    int best_score = 99;

    for (NameEntry* local = compiler->locals; local != NULL; local = local->next) {
        consider_suggestion(name, local->sage_name, &best_name, &best_score);
    }
    for (NameEntry* global = compiler->globals; global != NULL; global = global->next) {
        consider_suggestion(name, global->sage_name, &best_name, &best_score);
    }
    for (ProcEntry* proc = compiler->procs; proc != NULL; proc = proc->next) {
        consider_suggestion(name, proc->sage_name, &best_name, &best_score);
    }
    for (ClassInfo* class_info = compiler->classes; class_info != NULL; class_info = class_info->next) {
        consider_suggestion(name, class_info->class_name, &best_name, &best_score);
    }
    for (size_t i = 0; i < sizeof(builtins) / sizeof(builtins[0]); i++) {
        consider_suggestion(name, builtins[i], &best_name, &best_score);
    }

    return best_name;
}

static const char* compiler_unknown_name_help(Compiler* compiler, const char* name,
                                              const char* fallback,
                                              char* buffer, size_t buffer_size) {
    const char* suggestion = find_name_suggestion(compiler, name);
    if (suggestion != NULL) {
        snprintf(buffer, buffer_size, "did you mean '%s'?", suggestion);
        return buffer;
    }
    return fallback;
}

static void compiler_builtin_arity_error(Compiler* compiler, CallExpr* call,
                                         const char* builtin_name,
                                         const char* usage,
                                         const char* expected) {
    compiler_error_at(compiler, expr_token(call->callee), usage,
                      "%s() expects %s argument%s, but this call has %d",
                      builtin_name, expected,
                      strcmp(expected, "1") == 0 ? "" : "s",
                      call->arg_count);
}

static ClassInfo* add_class_info(Compiler* compiler, const char* name, const char* parent, Stmt* methods) {
    ClassInfo* info = malloc(sizeof(ClassInfo));
    if (info == NULL) { fprintf(stderr, "Out of memory\n"); exit(1); }
    info->class_name = str_dup(name);
    info->parent_name = parent ? str_dup(parent) : NULL;
    info->methods = methods;
    info->next = compiler->classes;
    compiler->classes = info;
    return info;
}

static void free_class_info(ClassInfo* list) {
    while (list != NULL) {
        ClassInfo* next = list->next;
        free(list->class_name);
        free(list->parent_name);
        free(list);
        list = next;
    }
}

static void free_imported_modules(ImportedModule* list) {
    while (list != NULL) {
        ImportedModule* next = list->next;
        free(list->name);
        free(list->source);
        free_stmt(list->ast);
        free(list);
        list = next;
    }
}

static char* read_file_contents(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    if (size < 0) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_SET);
    char* buf = malloc((size_t)size + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t nread = fread(buf, 1, (size_t)size, f);
    buf[nread] = '\0';
    fclose(f);
    return buf;
}

static char* resolve_module_path_for_compiler(const Compiler* compiler, const char* module_name) {
    char dir[PATH_MAX];
    if (compiler->input_path != NULL) {
        strncpy(dir, compiler->input_path, sizeof(dir) - 1);
        dir[sizeof(dir) - 1] = '\0';
        char* slash = strrchr(dir, '/');
        if (slash) *(slash + 1) = '\0';
        else strcpy(dir, "./");
    } else {
        strcpy(dir, "./");
    }
    char path[PATH_MAX];
    const char* search[] = { "", "lib/", "modules/" };
    for (int i = 0; i < 3; i++) {
        snprintf(path, sizeof(path), "%s%s%s.sage", dir, search[i], module_name);
        if (access(path, F_OK) == 0) return str_dup(path);
    }
    return NULL;
}

static void collect_local_lets(Compiler* compiler, Stmt* stmt, NameEntry** locals) {
    while (stmt != NULL) {
        switch (stmt->type) {
            case STMT_LET: {
                char* name = token_to_string(stmt->as.let.name);
                if (find_name_entry(*locals, name) == NULL) {
                    add_name_entry(compiler, locals, name, "sage_local");
                }
                free(name);
                break;
            }
            case STMT_BLOCK:
                collect_local_lets(compiler, stmt->as.block.statements, locals);
                break;
            case STMT_IF:
                collect_local_lets(compiler, stmt->as.if_stmt.then_branch, locals);
                collect_local_lets(compiler, stmt->as.if_stmt.else_branch, locals);
                break;
            case STMT_WHILE:
                collect_local_lets(compiler, stmt->as.while_stmt.body, locals);
                break;
            case STMT_PROC:
                compiler_error(compiler, "nested procedure declarations are not supported by the C backend");
                return;
            case STMT_FOR: {
                char* var_name = token_to_string(stmt->as.for_stmt.variable);
                if (find_name_entry(*locals, var_name) == NULL) {
                    add_name_entry(compiler, locals, var_name, "sage_local");
                }
                free(var_name);
                collect_local_lets(compiler, stmt->as.for_stmt.body, locals);
                break;
            }
            case STMT_TRY: {
                collect_local_lets(compiler, stmt->as.try_stmt.try_block, locals);
                for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                    char* catch_var = token_to_string(stmt->as.try_stmt.catches[i]->exception_var);
                    if (find_name_entry(*locals, catch_var) == NULL) {
                        add_name_entry(compiler, locals, catch_var, "sage_local");
                    }
                    free(catch_var);
                    collect_local_lets(compiler, stmt->as.try_stmt.catches[i]->body, locals);
                }
                if (stmt->as.try_stmt.finally_block != NULL) {
                    collect_local_lets(compiler, stmt->as.try_stmt.finally_block, locals);
                }
                break;
            }
            case STMT_CLASS:
            case STMT_MATCH:
            case STMT_DEFER:
            case STMT_RAISE:
            case STMT_YIELD:
            case STMT_IMPORT:
            case STMT_ASYNC_PROC:
                break;
            case STMT_PRINT:
            case STMT_EXPRESSION:
            case STMT_RETURN:
            case STMT_BREAK:
            case STMT_CONTINUE:
                break;
        }
        stmt = stmt->next;
    }
}

static void collect_global_lets(Compiler* compiler, Stmt* stmt) {
    while (stmt != NULL) {
        switch (stmt->type) {
            case STMT_LET: {
                char* name = token_to_string(stmt->as.let.name);
                if (find_proc_entry(compiler->procs, name) != NULL) {
                    compiler_error(compiler, "global '%s' conflicts with procedure name", name);
                } else {
                    add_name_entry(compiler, &compiler->globals, name, "sage_global");
                }
                free(name);
                break;
            }
            case STMT_BLOCK:
                collect_global_lets(compiler, stmt->as.block.statements);
                break;
            case STMT_IF:
                collect_global_lets(compiler, stmt->as.if_stmt.then_branch);
                collect_global_lets(compiler, stmt->as.if_stmt.else_branch);
                break;
            case STMT_WHILE:
                collect_global_lets(compiler, stmt->as.while_stmt.body);
                break;
            case STMT_FOR: {
                char* var_name = token_to_string(stmt->as.for_stmt.variable);
                if (find_proc_entry(compiler->procs, var_name) != NULL) {
                    compiler_error(compiler, "for-loop variable '%s' conflicts with procedure name", var_name);
                } else {
                    add_name_entry(compiler, &compiler->globals, var_name, "sage_global");
                }
                free(var_name);
                collect_global_lets(compiler, stmt->as.for_stmt.body);
                break;
            }
            case STMT_TRY: {
                collect_global_lets(compiler, stmt->as.try_stmt.try_block);
                for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                    char* catch_var = token_to_string(stmt->as.try_stmt.catches[i]->exception_var);
                    add_name_entry(compiler, &compiler->globals, catch_var, "sage_global");
                    free(catch_var);
                    collect_global_lets(compiler, stmt->as.try_stmt.catches[i]->body);
                }
                if (stmt->as.try_stmt.finally_block != NULL) {
                    collect_global_lets(compiler, stmt->as.try_stmt.finally_block);
                }
                break;
            }
            default:
                break;
        }
        stmt = stmt->next;
    }
}

Stmt* parse_program(const char* source, const char* input_path);

static int is_in_import_list(ImportStmt* import, const char* name) {
    for (int i = 0; i < import->item_count; i++) {
        if (strcmp(import->items[i], name) == 0) return 1;
    }
    return 0;
}

static void process_import(Compiler* compiler, ImportStmt* import) {
    /* Check if already loaded */
    for (ImportedModule* m = compiler->modules; m != NULL; m = m->next) {
        if (strcmp(m->name, import->module_name) == 0) return;
    }

    char* module_path = resolve_module_path_for_compiler(compiler, import->module_name);
    if (module_path == NULL) {
        compiler_error(compiler, "cannot find module '%s'", import->module_name);
        return;
    }

    char* source = read_file_contents(module_path);
    if (source == NULL) {
        compiler_error(compiler, "cannot read module '%s' at '%s'", import->module_name, module_path);
        free(module_path);
        return;
    }

    Stmt* ast = parse_program(source, module_path);

    ImportedModule* mod = malloc(sizeof(ImportedModule));
    if (mod == NULL) { fprintf(stderr, "Out of memory\n"); exit(1); }
    mod->name = str_dup(import->module_name);
    mod->path = module_path;
    mod->source = source;
    mod->ast = ast;
    mod->next = compiler->modules;
    compiler->modules = mod;

    /* Collect module's procs and classes */
    for (Stmt* s = ast; s != NULL; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = token_to_string(s->as.proc.name);
            if (import->import_all || is_in_import_list(import, name)) {
                add_proc_entry(compiler, name, s->as.proc.param_count, &s->as.proc.name);
            }
            free(name);
        }
        if (s->type == STMT_CLASS) {
            char* class_name = token_to_string(s->as.class_stmt.name);
            if (import->import_all || is_in_import_list(import, class_name)) {
                char* parent_name = NULL;
                if (s->as.class_stmt.has_parent) {
                    parent_name = token_to_string(s->as.class_stmt.parent);
                }
                add_class_info(compiler, class_name, parent_name, s->as.class_stmt.methods);
                free(parent_name);
            }
            free(class_name);
        }
    }

    /* Collect module's globals */
    for (Stmt* s = ast; s != NULL; s = s->next) {
        if (s->type != STMT_PROC && s->type != STMT_CLASS) {
            collect_global_lets(compiler, s);
        }
    }
}

static void collect_top_level_symbols(Compiler* compiler, Stmt* program) {
    /* First pass: collect procs, classes, and imports */
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_PROC) {
            char* name = token_to_string(stmt->as.proc.name);
            add_proc_entry(compiler, name, stmt->as.proc.param_count, &stmt->as.proc.name);
            free(name);
        }
        if (stmt->type == STMT_CLASS) {
            char* class_name = token_to_string(stmt->as.class_stmt.name);
            char* parent_name = NULL;
            if (stmt->as.class_stmt.has_parent) {
                parent_name = token_to_string(stmt->as.class_stmt.parent);
            }
            add_class_info(compiler, class_name, parent_name, stmt->as.class_stmt.methods);
            free(class_name);
            free(parent_name);
        }
        if (stmt->type == STMT_IMPORT) {
            process_import(compiler, &stmt->as.import);
            if (compiler->failed) return;
        }
    }

    /* Second pass: collect global lets */
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type != STMT_PROC && stmt->type != STMT_CLASS) {
            collect_global_lets(compiler, stmt);
        }
    }
}

static const char* resolve_slot_name(Compiler* compiler, const char* sage_name) {
    NameEntry* local = find_name_entry(compiler->locals, sage_name);
    if (local != NULL) {
        return local->c_name;
    }

    NameEntry* global = find_name_entry(compiler->globals, sage_name);
    if (global != NULL) {
        return global->c_name;
    }

    return NULL;
}

static char* emit_expr(Compiler* compiler, Expr* expr);

static char* emit_array_expr(Compiler* compiler, ArrayExpr* array) {
    StringBuffer sb;
    sb_init(&sb);
    if (array->count == 0) {
        sb_append(&sb, "sage_make_array(0, NULL)");
        return sb_take(&sb);
    }

    sb_appendf(&sb, "sage_make_array(%d, (SageValue[]){", array->count);

    for (int i = 0; i < array->count; i++) {
        char* element = emit_expr(compiler, array->elements[i]);
        if (i > 0) {
            sb_append(&sb, ", ");
        }
        sb_append(&sb, element);
        free(element);
        if (compiler->failed) {
            free(sb_take(&sb));
            return str_dup("sage_nil()");
        }
    }

    sb_append(&sb, "})");
    return sb_take(&sb);
}

static char* emit_index_expr(Compiler* compiler, IndexExpr* index) {
    char* array_expr = emit_expr(compiler, index->array);
    char* index_expr = emit_expr(compiler, index->index);
    if (compiler->failed) {
        free(array_expr);
        free(index_expr);
        return str_dup("sage_nil()");
    }

    StringBuffer sb;
    sb_init(&sb);
    sb_appendf(&sb, "sage_index(%s, %s)", array_expr, index_expr);
    free(array_expr);
    free(index_expr);
    return sb_take(&sb);
}

static char* emit_slice_expr(Compiler* compiler, SliceExpr* slice) {
    char* array_expr = emit_expr(compiler, slice->array);
    char* start_expr = slice->start != NULL ? emit_expr(compiler, slice->start) : str_dup("sage_nil()");
    char* end_expr = slice->end != NULL ? emit_expr(compiler, slice->end) : str_dup("sage_nil()");
    if (compiler->failed) {
        free(array_expr);
        free(start_expr);
        free(end_expr);
        return str_dup("sage_nil()");
    }

    StringBuffer sb;
    sb_init(&sb);
    sb_appendf(&sb, "sage_slice(%s, %s, %s)", array_expr, start_expr, end_expr);
    free(array_expr);
    free(start_expr);
    free(end_expr);
    return sb_take(&sb);
}

static char* emit_dict_expr(Compiler* compiler, DictExpr* dict) {
    StringBuffer sb;
    sb_init(&sb);
    if (dict->count == 0) {
        sb_append(&sb, "sage_make_dict()");
        return sb_take(&sb);
    }

    sb_appendf(&sb, "sage_make_dict_from_entries(%d, (const char*[]){", dict->count);
    for (int i = 0; i < dict->count; i++) {
        char* escaped = escape_c_string(dict->keys[i]);
        if (i > 0) {
            sb_append(&sb, ", ");
        }
        sb_appendf(&sb, "\"%s\"", escaped);
        free(escaped);
        if (compiler->failed) {
            free(sb_take(&sb));
            return str_dup("sage_nil()");
        }
    }
    sb_append(&sb, "}, (SageValue[]){");
    for (int i = 0; i < dict->count; i++) {
        char* val = emit_expr(compiler, dict->values[i]);
        if (i > 0) {
            sb_append(&sb, ", ");
        }
        sb_append(&sb, val);
        free(val);
        if (compiler->failed) {
            free(sb_take(&sb));
            return str_dup("sage_nil()");
        }
    }
    sb_append(&sb, "})");
    return sb_take(&sb);
}

static char* emit_tuple_expr(Compiler* compiler, TupleExpr* tuple) {
    StringBuffer sb;
    sb_init(&sb);
    if (tuple->count == 0) {
        sb_append(&sb, "sage_make_tuple(0, NULL)");
        return sb_take(&sb);
    }

    sb_appendf(&sb, "sage_make_tuple(%d, (SageValue[]){", tuple->count);
    for (int i = 0; i < tuple->count; i++) {
        char* element = emit_expr(compiler, tuple->elements[i]);
        if (i > 0) sb_append(&sb, ", ");
        sb_append(&sb, element);
        free(element);
        if (compiler->failed) {
            free(sb_take(&sb));
            return str_dup("sage_nil()");
        }
    }
    sb_append(&sb, "})");
    return sb_take(&sb);
}

static char* emit_binary_expr(Compiler* compiler, BinaryExpr* binary) {
    char* left = emit_expr(compiler, binary->left);
    if (compiler->failed) {
        free(left);
        return str_dup("sage_nil()");
    }

    if (binary->op.type == TOKEN_NOT) {
        StringBuffer sb;
        sb_init(&sb);
        sb_appendf(&sb, "sage_not(%s)", left);
        free(left);
        return sb_take(&sb);
    }

    if (binary->op.type == TOKEN_TILDE) {
        StringBuffer sb;
        sb_init(&sb);
        sb_appendf(&sb, "sage_bit_not(%s)", left);
        free(left);
        return sb_take(&sb);
    }

    char* right = emit_expr(compiler, binary->right);
    if (compiler->failed) {
        free(left);
        free(right);
        return str_dup("sage_nil()");
    }

    const char* helper = NULL;
    switch (binary->op.type) {
        case TOKEN_PLUS: helper = "sage_add"; break;
        case TOKEN_MINUS: helper = "sage_sub"; break;
        case TOKEN_STAR: helper = "sage_mul"; break;
        case TOKEN_SLASH: helper = "sage_div"; break;
        case TOKEN_PERCENT: helper = "sage_mod"; break;
        case TOKEN_EQ: helper = "sage_eq"; break;
        case TOKEN_NEQ: helper = "sage_neq"; break;
        case TOKEN_GT: helper = "sage_gt"; break;
        case TOKEN_LT: helper = "sage_lt"; break;
        case TOKEN_GTE: helper = "sage_gte"; break;
        case TOKEN_LTE: helper = "sage_lte"; break;
        case TOKEN_AMP: helper = "sage_bit_and"; break;
        case TOKEN_PIPE: helper = "sage_bit_or"; break;
        case TOKEN_CARET: helper = "sage_bit_xor"; break;
        case TOKEN_LSHIFT: helper = "sage_lshift"; break;
        case TOKEN_RSHIFT: helper = "sage_rshift"; break;
        case TOKEN_AND: helper = "sage_and"; break;
        case TOKEN_OR: helper = "sage_or"; break;
        default: break;
    }

    if (helper == NULL) {
        compiler_error_at(compiler, &binary->op,
                          "the C backend only supports operators with built-in runtime helpers",
                          "binary operator '%.*s' is not supported by the C backend",
                          binary->op.length, binary->op.start);
        free(left);
        free(right);
        return str_dup("sage_nil()");
    }

    StringBuffer sb;
    sb_init(&sb);
    sb_appendf(&sb, "%s(%s, %s)", helper, left, right);
    free(left);
    free(right);
    return sb_take(&sb);
}

static char* emit_call_expr(Compiler* compiler, CallExpr* call) {
    /* Method call: obj.method(args) */
    if (call->callee->type == EXPR_GET) {
        char* obj = emit_expr(compiler, call->callee->as.get.object);
        char* method = token_to_string(call->callee->as.get.property);
        StringBuffer msb;
        sb_init(&msb);
        if (call->arg_count == 0) {
            sb_appendf(&msb, "sage_call_method(%s, \"%s\", 0, NULL)", obj, method);
        } else {
            sb_appendf(&msb, "sage_call_method(%s, \"%s\", %d, (SageValue[]){",
                       obj, method, call->arg_count);
            for (int i = 0; i < call->arg_count; i++) {
                if (i > 0) sb_append(&msb, ", ");
                char* arg = emit_expr(compiler, call->args[i]);
                sb_append(&msb, arg);
                free(arg);
            }
            sb_append(&msb, "})");
        }
        free(obj);
        free(method);
        return sb_take(&msb);
    }

    if (call->callee->type != EXPR_VARIABLE) {
        compiler_error_at(compiler, expr_token(call->callee),
                          "call a named procedure, class constructor, or builtin directly",
                          "only direct function calls are supported by the C backend");
        return str_dup("sage_nil()");
    }

    char* callee_name = token_to_string(call->callee->as.variable.name);
    StringBuffer sb;
    sb_init(&sb);

    if (strcmp(callee_name, "str") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "str", "usage: str(value)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_str(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "len") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "len", "usage: len(value)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_len(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "push") == 0) {
        if (call->arg_count != 2) {
            compiler_builtin_arity_error(compiler, call, "push", "usage: push(array, value)", "2");
            sb_append(&sb, "sage_nil()");
        } else {
            char* array_arg = emit_expr(compiler, call->args[0]);
            char* value_arg = emit_expr(compiler, call->args[1]);
            sb_appendf(&sb, "sage_push(%s, %s)", array_arg, value_arg);
            free(array_arg);
            free(value_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "pop") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "pop", "usage: pop(array)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_pop(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "range") == 0) {
        if (call->arg_count == 1) {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_range1(%s)", arg);
            free(arg);
        } else if (call->arg_count == 2) {
            char* start_arg = emit_expr(compiler, call->args[0]);
            char* end_arg = emit_expr(compiler, call->args[1]);
            sb_appendf(&sb, "sage_range2(%s, %s)", start_arg, end_arg);
            free(start_arg);
            free(end_arg);
        } else {
            compiler_builtin_arity_error(compiler, call, "range",
                                         "usage: range(stop) or range(start, stop)",
                                         "1 or 2");
            sb_append(&sb, "sage_nil()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "tonumber") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "tonumber", "usage: tonumber(value)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_tonumber(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "dict_keys") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "dict_keys", "usage: dict_keys(dict_value)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_dict_keys_fn(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "dict_values") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "dict_values", "usage: dict_values(dict_value)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_dict_values_fn(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "dict_has") == 0) {
        if (call->arg_count != 2) {
            compiler_builtin_arity_error(compiler, call, "dict_has", "usage: dict_has(dict_value, key)", "2");
            sb_append(&sb, "sage_nil()");
        } else {
            char* dict_arg = emit_expr(compiler, call->args[0]);
            char* key_arg = emit_expr(compiler, call->args[1]);
            sb_appendf(&sb, "sage_dict_has_fn(%s, %s)", dict_arg, key_arg);
            free(dict_arg);
            free(key_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "dict_delete") == 0) {
        if (call->arg_count != 2) {
            compiler_builtin_arity_error(compiler, call, "dict_delete",
                                         "usage: dict_delete(dict_value, key)", "2");
            sb_append(&sb, "sage_nil()");
        } else {
            char* dict_arg = emit_expr(compiler, call->args[0]);
            char* key_arg = emit_expr(compiler, call->args[1]);
            sb_appendf(&sb, "sage_dict_delete_fn(%s, %s)", dict_arg, key_arg);
            free(dict_arg);
            free(key_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "gc_collect") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "gc_collect", "usage: gc_collect()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_gc_collect_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "gc_stats") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "gc_stats", "usage: gc_stats()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_gc_stats_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "gc_collections") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "gc_collections", "usage: gc_collections()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_gc_collections_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "gc_enable") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "gc_enable", "usage: gc_enable()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_gc_enable_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "gc_disable") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "gc_disable", "usage: gc_disable()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_gc_disable_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "upper") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "upper", "usage: upper(text)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_upper(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "lower") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "lower", "usage: lower(text)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_lower(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "strip") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "strip", "usage: strip(text)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_strip_fn(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "split") == 0) {
        if (call->arg_count != 2) {
            compiler_builtin_arity_error(compiler, call, "split", "usage: split(text, separator)", "2");
            sb_append(&sb, "sage_nil()");
        } else {
            char* str_arg = emit_expr(compiler, call->args[0]);
            char* delim_arg = emit_expr(compiler, call->args[1]);
            sb_appendf(&sb, "sage_split_fn(%s, %s)", str_arg, delim_arg);
            free(str_arg);
            free(delim_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "join") == 0) {
        if (call->arg_count != 2) {
            compiler_builtin_arity_error(compiler, call, "join", "usage: join(parts, separator)", "2");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arr_arg = emit_expr(compiler, call->args[0]);
            char* delim_arg = emit_expr(compiler, call->args[1]);
            sb_appendf(&sb, "sage_join_fn(%s, %s)", arr_arg, delim_arg);
            free(arr_arg);
            free(delim_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "replace") == 0) {
        if (call->arg_count != 3) {
            compiler_builtin_arity_error(compiler, call, "replace", "usage: replace(text, old, new)", "3");
            sb_append(&sb, "sage_nil()");
        } else {
            char* str_arg = emit_expr(compiler, call->args[0]);
            char* old_arg = emit_expr(compiler, call->args[1]);
            char* new_arg = emit_expr(compiler, call->args[2]);
            sb_appendf(&sb, "sage_replace_fn(%s, %s, %s)", str_arg, old_arg, new_arg);
            free(str_arg);
            free(old_arg);
            free(new_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "mem_alloc") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "mem_alloc", "usage: mem_alloc(size)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_mem_alloc(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "mem_free") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "mem_free", "usage: mem_free(pointer)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_mem_free(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "mem_read") == 0) {
        if (call->arg_count != 3) {
            compiler_builtin_arity_error(compiler, call, "mem_read",
                                         "usage: mem_read(pointer, offset, type_name)", "3");
            sb_append(&sb, "sage_nil()");
        } else {
            char* ptr = emit_expr(compiler, call->args[0]);
            char* off = emit_expr(compiler, call->args[1]);
            char* type = emit_expr(compiler, call->args[2]);
            sb_appendf(&sb, "sage_mem_read(%s, %s, %s)", ptr, off, type);
            free(ptr); free(off); free(type);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "mem_write") == 0) {
        if (call->arg_count != 4) {
            compiler_builtin_arity_error(compiler, call, "mem_write",
                                         "usage: mem_write(pointer, offset, type_name, value)", "4");
            sb_append(&sb, "sage_nil()");
        } else {
            char* ptr = emit_expr(compiler, call->args[0]);
            char* off = emit_expr(compiler, call->args[1]);
            char* type = emit_expr(compiler, call->args[2]);
            char* val = emit_expr(compiler, call->args[3]);
            sb_appendf(&sb, "sage_mem_write(%s, %s, %s, %s)", ptr, off, type, val);
            free(ptr); free(off); free(type); free(val);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "mem_size") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "mem_size", "usage: mem_size(pointer)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_mem_size(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "struct_def") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "struct_def", "usage: struct_def(fields)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_struct_def(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "struct_new") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "struct_new", "usage: struct_new(definition)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_struct_new(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "struct_get") == 0) {
        if (call->arg_count != 3) {
            compiler_builtin_arity_error(compiler, call, "struct_get",
                                         "usage: struct_get(pointer, definition, field_name)", "3");
            sb_append(&sb, "sage_nil()");
        } else {
            char* ptr = emit_expr(compiler, call->args[0]);
            char* def = emit_expr(compiler, call->args[1]);
            char* field = emit_expr(compiler, call->args[2]);
            sb_appendf(&sb, "sage_struct_get(%s, %s, %s)", ptr, def, field);
            free(ptr); free(def); free(field);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "struct_set") == 0) {
        if (call->arg_count != 4) {
            compiler_builtin_arity_error(compiler, call, "struct_set",
                                         "usage: struct_set(pointer, definition, field_name, value)", "4");
            sb_append(&sb, "sage_nil()");
        } else {
            char* ptr = emit_expr(compiler, call->args[0]);
            char* def = emit_expr(compiler, call->args[1]);
            char* field = emit_expr(compiler, call->args[2]);
            char* val = emit_expr(compiler, call->args[3]);
            sb_appendf(&sb, "sage_struct_set(%s, %s, %s, %s)", ptr, def, field, val);
            free(ptr); free(def); free(field); free(val);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "struct_size") == 0) {
        if (call->arg_count != 1) {
            compiler_builtin_arity_error(compiler, call, "struct_size", "usage: struct_size(definition)", "1");
            sb_append(&sb, "sage_nil()");
        } else {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_struct_size(%s)", arg);
            free(arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "clock") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "clock", "usage: clock()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_clock_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "input") == 0) {
        if (call->arg_count == 0) {
            sb_append(&sb, "sage_input_fn(sage_nil())");
        } else if (call->arg_count == 1) {
            char* arg = emit_expr(compiler, call->args[0]);
            sb_appendf(&sb, "sage_input_fn(%s)", arg);
            free(arg);
        } else {
            compiler_builtin_arity_error(compiler, call, "input", "usage: input() or input(prompt)", "0 or 1");
            sb_append(&sb, "sage_nil()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "slice") == 0) {
        if (call->arg_count != 3) {
            compiler_builtin_arity_error(compiler, call, "slice", "usage: slice(value, start, end)", "3");
            sb_append(&sb, "sage_nil()");
        } else {
            char* array_arg = emit_expr(compiler, call->args[0]);
            char* start_arg = emit_expr(compiler, call->args[1]);
            char* end_arg = emit_expr(compiler, call->args[2]);
            sb_appendf(&sb, "sage_slice(%s, %s, %s)", array_arg, start_arg, end_arg);
            free(array_arg);
            free(start_arg);
            free(end_arg);
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "asm_arch") == 0) {
        if (call->arg_count != 0) {
            compiler_builtin_arity_error(compiler, call, "asm_arch", "usage: asm_arch()", "0");
            sb_append(&sb, "sage_nil()");
        } else {
            sb_append(&sb, "sage_arch_fn()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    /* Class constructor call: ClassName(args) */
    ClassInfo* cls = find_class_info(compiler->classes, callee_name);
    if (cls != NULL) {
        sb_appendf(&sb, "sage_construct(\"%s\", ", cls->class_name);
        if (cls->parent_name) {
            sb_appendf(&sb, "\"%s\"", cls->parent_name);
        } else {
            sb_append(&sb, "NULL");
        }
        sb_appendf(&sb, ", %d, ", call->arg_count);
        if (call->arg_count == 0) {
            sb_append(&sb, "NULL)");
        } else {
            sb_append(&sb, "(SageValue[]){");
            for (int i = 0; i < call->arg_count; i++) {
                if (i > 0) sb_append(&sb, ", ");
                char* arg = emit_expr(compiler, call->args[i]);
                sb_append(&sb, arg);
                free(arg);
            }
            sb_append(&sb, "})");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    ProcEntry* proc = find_proc_entry(compiler->procs, callee_name);
    if (proc == NULL) {
        char help[256];
        compiler_error_at(compiler, expr_token(call->callee),
                          compiler_unknown_name_help(
                              compiler, callee_name,
                              "only known procedures, class constructors, and builtins can be compiled",
                              help, sizeof(help)),
                          "unknown call target '%s' in compiled code", callee_name);
        free(callee_name);
        return str_dup("sage_nil()");
    }

    if (proc->param_count != call->arg_count) {
        char help[256];
        snprintf(help, sizeof(help), "change this call to pass %d argument%s",
                 proc->param_count, proc->param_count == 1 ? "" : "s");
        compiler_error_at(compiler, expr_token(call->callee), help,
                          "call to '%s' passes %d argument%s, but the procedure expects %d",
                          callee_name, call->arg_count, call->arg_count == 1 ? "" : "s",
                          proc->param_count);
        free(callee_name);
        return str_dup("sage_nil()");
    }

    sb_appendf(&sb, "%s(", proc->c_name);
    for (int i = 0; i < call->arg_count; i++) {
        char* arg = emit_expr(compiler, call->args[i]);
        if (i > 0) {
            sb_append(&sb, ", ");
        }
        sb_append(&sb, arg);
        free(arg);
    }
    sb_append(&sb, ")");
    free(callee_name);
    return sb_take(&sb);
}

static char* emit_set_expr(Compiler* compiler, SetExpr* set) {
    if (set->object != NULL) {
        /* Property assignment: obj.prop = value */
        char* obj = emit_expr(compiler, set->object);
        char* prop = token_to_string(set->property);
        char* escaped = escape_c_string(prop);
        char* val = emit_expr(compiler, set->value);
        StringBuffer sb;
        sb_init(&sb);
        sb_appendf(&sb, "({SageValue _obj = %s; SageValue _val = %s; "
                   "sage_dict_set(_obj.as.dict, \"%s\", _val); _val;})",
                   obj, val, escaped);
        free(obj);
        free(prop);
        free(escaped);
        free(val);
        return sb_take(&sb);
    }

    char* name = token_to_string(set->property);
    const char* slot_name = resolve_slot_name(compiler, name);
    if (slot_name == NULL) {
        char help[256];
        compiler_error_at(compiler, &set->property,
                          compiler_unknown_name_help(
                              compiler, name,
                              "declare the variable first with let or var before assigning to it",
                              help, sizeof(help)),
                          "cannot assign to unknown name '%s' in compiled code", name);
        free(name);
        return str_dup("sage_nil()");
    }

    char* value = emit_expr(compiler, set->value);
    StringBuffer sb;
    sb_init(&sb);
    sb_appendf(&sb, "sage_assign_slot(&%s, \"%s\", %s)", slot_name, name, value);
    free(name);
    free(value);
    return sb_take(&sb);
}

static char* emit_expr(Compiler* compiler, Expr* expr) {
    switch (expr->type) {
        case EXPR_NUMBER: {
            StringBuffer sb;
            sb_init(&sb);
            sb_appendf(&sb, "sage_number(%.17g)", expr->as.number.value);
            return sb_take(&sb);
        }
        case EXPR_STRING: {
            char* escaped = escape_c_string(expr->as.string.value);
            StringBuffer sb;
            sb_init(&sb);
            sb_appendf(&sb, "sage_string(\"%s\")", escaped);
            free(escaped);
            return sb_take(&sb);
        }
        case EXPR_BOOL:
            return str_dup(expr->as.boolean.value ? "sage_bool(1)" : "sage_bool(0)");
        case EXPR_NIL:
            return str_dup("sage_nil()");
        case EXPR_BINARY:
            return emit_binary_expr(compiler, &expr->as.binary);
        case EXPR_VARIABLE: {
            char* name = token_to_string(expr->as.variable.name);
            const char* slot_name = resolve_slot_name(compiler, name);
            if (slot_name == NULL) {
                char help[256];
                compiler_error_at(compiler, &expr->as.variable.name,
                                  compiler_unknown_name_help(
                                      compiler, name,
                                      "declare the value first or spell the name exactly as it was defined",
                                      help, sizeof(help)),
                                  "unknown name '%s' in compiled code", name);
                free(name);
                return str_dup("sage_nil()");
            }

            StringBuffer sb;
            sb_init(&sb);
            sb_appendf(&sb, "sage_load_slot(&%s, \"%s\")", slot_name, name);
            free(name);
            return sb_take(&sb);
        }
        case EXPR_CALL:
            return emit_call_expr(compiler, &expr->as.call);
        case EXPR_ARRAY:
            return emit_array_expr(compiler, &expr->as.array);
        case EXPR_INDEX:
            return emit_index_expr(compiler, &expr->as.index);
        case EXPR_INDEX_SET: {
            char* arr = emit_expr(compiler, expr->as.index_set.array);
            char* idx = emit_expr(compiler, expr->as.index_set.index);
            char* val = emit_expr(compiler, expr->as.index_set.value);
            StringBuffer sb;
            sb_init(&sb);
            sb_appendf(&sb, "sage_index_set(%s, %s, %s)", arr, idx, val);
            free(arr);
            free(idx);
            free(val);
            return sb_take(&sb);
        }
        case EXPR_SLICE:
            return emit_slice_expr(compiler, &expr->as.slice);
        case EXPR_SET:
            return emit_set_expr(compiler, &expr->as.set);
        case EXPR_AWAIT:
            // TODO: async/await not supported in C backend
            compiler_error_at(compiler, expr_token(expr),
                              "async code currently runs only in the interpreter",
                              "await expressions are not yet supported in the C backend");
            return str_dup("sage_nil()");
        case EXPR_DICT:
            return emit_dict_expr(compiler, &expr->as.dict);
        case EXPR_TUPLE:
            return emit_tuple_expr(compiler, &expr->as.tuple);
        case EXPR_GET: {
            /* property access: object.property — emit as dict get for now */
            char* object = emit_expr(compiler, expr->as.get.object);
            char* prop = token_to_string(expr->as.get.property);
            char* escaped = escape_c_string(prop);
            StringBuffer sb;
            sb_init(&sb);
            sb_appendf(&sb, "sage_index(%s, sage_string(\"%s\"))", object, escaped);
            free(object);
            free(prop);
            free(escaped);
            return sb_take(&sb);
        }
    }

    compiler_error_at(compiler, expr_token(expr), NULL,
                      "internal compiler error: unknown expression kind");
    return str_dup("sage_nil()");
}

static void emit_stmt_list(Compiler* compiler, Stmt* stmt);

static void emit_embedded_block(Compiler* compiler, Stmt* stmt) {
    compiler->indent++;
    if (stmt != NULL && stmt->type == STMT_BLOCK) {
        emit_stmt_list(compiler, stmt->as.block.statements);
    } else {
        emit_stmt_list(compiler, stmt);
    }
    compiler->indent--;
}

static void emit_stmt(Compiler* compiler, Stmt* stmt) {
    switch (stmt->type) {
        case STMT_PRINT: {
            char* expr = emit_expr(compiler, stmt->as.print.expression);
            emit_line(compiler, "sage_print_ln(%s);", expr);
            free(expr);
            break;
        }
        case STMT_EXPRESSION: {
            char* expr = emit_expr(compiler, stmt->as.expression);
            emit_line(compiler, "(void)%s;", expr);
            free(expr);
            break;
        }
        case STMT_LET: {
            char* name = token_to_string(stmt->as.let.name);
            const char* slot_name = resolve_slot_name(compiler, name);
            if (slot_name == NULL) {
                compiler_error_at(compiler, &stmt->as.let.name, NULL,
                                  "internal compiler error: let target '%s' was not collected for code generation",
                                  name);
                free(name);
                break;
            }

            char* expr = stmt->as.let.initializer != NULL
                ? emit_expr(compiler, stmt->as.let.initializer)
                : str_dup("sage_nil()");
            emit_line(compiler, "sage_define_slot(&%s, %s);", slot_name, expr);
            free(name);
            free(expr);
            break;
        }
        case STMT_IF: {
            char* condition = emit_expr(compiler, stmt->as.if_stmt.condition);
            emit_line(compiler, "if (sage_truthy(%s)) {", condition);
            free(condition);
            emit_embedded_block(compiler, stmt->as.if_stmt.then_branch);
            emit_line(compiler, "}");
            if (stmt->as.if_stmt.else_branch != NULL) {
                emit_line(compiler, "else {");
                emit_embedded_block(compiler, stmt->as.if_stmt.else_branch);
                emit_line(compiler, "}");
            }
            break;
        }
        case STMT_BLOCK:
            emit_stmt_list(compiler, stmt->as.block.statements);
            break;
        case STMT_WHILE: {
            char* condition = emit_expr(compiler, stmt->as.while_stmt.condition);
            emit_line(compiler, "while (sage_truthy(%s)) {", condition);
            free(condition);
            emit_embedded_block(compiler, stmt->as.while_stmt.body);
            emit_line(compiler, "}");
            break;
        }
        case STMT_RETURN: {
            char* expr = stmt->as.ret.value != NULL
                ? emit_expr(compiler, stmt->as.ret.value)
                : str_dup("sage_nil()");
            if (compiler->in_function_body) {
                emit_line(compiler, "return sage_gc_return(&sage_gc_frame, %s);", expr);
            } else {
                emit_line(compiler, "return %s;", expr);
            }
            free(expr);
            break;
        }
        case STMT_BREAK:
            emit_line(compiler, "break;");
            break;
        case STMT_CONTINUE:
            emit_line(compiler, "continue;");
            break;
        case STMT_PROC:
            break;
        case STMT_FOR: {
            char* iterable = emit_expr(compiler, stmt->as.for_stmt.iterable);
            char* var_name = token_to_string(stmt->as.for_stmt.variable);
            const char* slot_name = resolve_slot_name(compiler, var_name);
            if (slot_name == NULL) {
                compiler_error_at(compiler, &stmt->as.for_stmt.variable, NULL,
                                  "internal compiler error: for-loop variable '%s' was not collected",
                                  var_name);
                free(var_name);
                free(iterable);
                break;
            }
            char* iter_var = make_unique_name(compiler, "sage_iter", var_name);
            char* idx_var = make_unique_name(compiler, "sage_idx", var_name);
            emit_line(compiler, "{");
            compiler->indent++;
            emit_line(compiler, "SageValue %s = %s;", iter_var, iterable);
            emit_line(compiler, "if (%s.type == SAGE_TAG_ARRAY) {", iter_var);
            compiler->indent++;
            emit_line(compiler, "for (int %s = 0; %s < %s.as.array->count; %s++) {",
                       idx_var, idx_var, iter_var, idx_var);
            compiler->indent++;
            emit_line(compiler, "sage_define_slot(&%s, %s.as.array->elements[%s]);",
                       slot_name, iter_var, idx_var);
            emit_embedded_block(compiler, stmt->as.for_stmt.body);
            compiler->indent--;
            emit_line(compiler, "}");
            compiler->indent--;
            emit_line(compiler, "} else if (%s.type == SAGE_TAG_STRING) {", iter_var);
            compiler->indent++;
            emit_line(compiler, "int _len = (int)strlen(%s.as.string);", iter_var);
            emit_line(compiler, "for (int %s = 0; %s < _len; %s++) {",
                       idx_var, idx_var, idx_var);
            compiler->indent++;
            emit_line(compiler, "char _ch[2] = {%s.as.string[%s], '\\0'};",
                       iter_var, idx_var);
            emit_line(compiler, "sage_define_slot(&%s, sage_string(_ch));",
                     slot_name);
            emit_embedded_block(compiler, stmt->as.for_stmt.body);
            compiler->indent--;
            emit_line(compiler, "}");
            compiler->indent--;
            emit_line(compiler, "}");
            compiler->indent--;
            emit_line(compiler, "}");
            free(var_name);
            free(iterable);
            free(iter_var);
            free(idx_var);
            break;
        }
        case STMT_TRY: {
            TryStmt* try_stmt = &stmt->as.try_stmt;
            emit_line(compiler, "{");
            compiler->indent++;
            emit_line(compiler, "if (sage_try_depth >= SAGE_MAX_TRY_DEPTH) sage_fail(\"Runtime Error: try nesting too deep\");");
            emit_line(compiler, "int _caught = 0;");
            emit_line(compiler, "sage_try_depth++;");
            emit_line(compiler, "if (setjmp(sage_try_stack[sage_try_depth - 1]) == 0) {");
            emit_embedded_block(compiler, try_stmt->try_block);
            emit_line(compiler, "} else {");
            compiler->indent++;
            emit_line(compiler, "_caught = 1;");
            if (try_stmt->catch_count > 0) {
                char* catch_var = token_to_string(try_stmt->catches[0]->exception_var);
                const char* catch_slot = resolve_slot_name(compiler, catch_var);
                if (catch_slot != NULL) {
                    emit_line(compiler, "sage_define_slot(&%s, sage_exception_value);", catch_slot);
                }
                free(catch_var);
            }
            compiler->indent--;
            emit_line(compiler, "}");
            emit_line(compiler, "sage_try_depth--;");
            if (try_stmt->catch_count > 0) {
                emit_line(compiler, "if (_caught) {");
                emit_embedded_block(compiler, try_stmt->catches[0]->body);
                emit_line(compiler, "}");
            }
            if (try_stmt->finally_block != NULL) {
                emit_embedded_block(compiler, try_stmt->finally_block);
            }
            compiler->indent--;
            emit_line(compiler, "}");
            break;
        }
        case STMT_RAISE: {
            char* expr = stmt->as.raise.exception != NULL
                ? emit_expr(compiler, stmt->as.raise.exception)
                : str_dup("sage_string(\"exception\")");
            emit_line(compiler, "sage_raise(%s);", expr);
            free(expr);
            break;
        }
        case STMT_CLASS:
            break;  /* Methods emitted as top-level functions; registration at main start */
        case STMT_IMPORT: {
            /* Emit module-level code inline at import site */
            ImportStmt* imp = &stmt->as.import;
            for (ImportedModule* m = compiler->modules; m != NULL; m = m->next) {
                if (strcmp(m->name, imp->module_name) == 0) {
                    for (Stmt* s = m->ast; s != NULL; s = s->next) {
                        if (s->type != STMT_PROC && s->type != STMT_CLASS) {
                            emit_stmt(compiler, s);
                            if (compiler->failed) return;
                        }
                    }
                    break;
                }
            }
            break;
        }
        case STMT_MATCH:
        case STMT_DEFER:
        case STMT_YIELD:
            compiler_error_at(compiler, stmt_token(stmt),
                              "try the interpreter for this program, or stay within the currently compiled subset",
                              "this statement kind is not yet supported by the C backend");
            break;
        case STMT_ASYNC_PROC:
            // TODO: async/await not supported in C backend
            compiler_error_at(compiler, &stmt->as.async_proc.name,
                              "async code currently runs only in the interpreter",
                              "async procedures are not yet supported in the C backend");
            break;
    }
}

static void emit_stmt_list(Compiler* compiler, Stmt* stmt) {
    for (Stmt* current = stmt; current != NULL; current = current->next) {
        emit_stmt(compiler, current);
        if (compiler->failed) {
            return;
        }
    }
}

static void emit_runtime_prelude(FILE* out, CompilerTarget target) {
    fputs(
        "#include <setjmp.h>\n"
        "#include <stdarg.h>\n"
        "#include <stdio.h>\n"
        "#include <stdlib.h>\n"
        "#include <string.h>\n"
        ,
        out
    );

    if (target == COMPILER_TARGET_PICO) {
        fputs("#include \"pico/stdlib.h\"\n", out);
    }

    fputs(
        "\n"
        "typedef struct SageValue SageValue;\n"
        "typedef struct SageGcHeader SageGcHeader;\n"
        "typedef struct SageGcFrame SageGcFrame;\n"
        "\n"
        "typedef struct {\n"
        "    int count;\n"
        "    int capacity;\n"
        "    SageValue* elements;\n"
        "} SageArray;\n"
        "\n"
        "typedef struct {\n"
        "    char** keys;\n"
        "    SageValue* values;\n"
        "    int count;\n"
        "    int capacity;\n"
        "} SageDict;\n"
        "\n"
        "typedef struct {\n"
        "    SageValue* elements;\n"
        "    int count;\n"
        "} SageTuple;\n"
        "\n"
        "typedef enum {\n"
        "    SAGE_TAG_NIL,\n"
        "    SAGE_TAG_NUMBER,\n"
        "    SAGE_TAG_BOOL,\n"
        "    SAGE_TAG_STRING,\n"
        "    SAGE_TAG_ARRAY,\n"
        "    SAGE_TAG_DICT,\n"
        "    SAGE_TAG_TUPLE\n"
        "} SageTag;\n"
        "\n"
        "struct SageValue {\n"
        "    SageTag type;\n"
        "    union {\n"
        "        double number;\n"
        "        int boolean;\n"
        "        const char* string;\n"
        "        SageArray* array;\n"
        "        SageDict* dict;\n"
        "        SageTuple* tuple;\n"
        "    } as;\n"
        "};\n"
        "\n"
        "typedef struct {\n"
        "    int defined;\n"
        "    SageValue value;\n"
        "} SageSlot;\n"
        "\n"
        "typedef enum {\n"
        "    SAGE_GC_STRING,\n"
        "    SAGE_GC_ARRAY,\n"
        "    SAGE_GC_DICT,\n"
        "    SAGE_GC_TUPLE\n"
        "} SageGcKind;\n"
        "\n"
        "struct SageGcHeader {\n"
        "    unsigned char marked;\n"
        "    unsigned char kind;\n"
        "    size_t size;\n"
        "    SageGcHeader* next;\n"
        "};\n"
        "\n"
        "struct SageGcFrame {\n"
        "    SageGcFrame* prev;\n"
        "    SageSlot** slots;\n"
        "    int slot_count;\n"
        "};\n"
        "\n"
        "typedef struct {\n"
        "    SageGcHeader* objects;\n"
        "    SageGcFrame* frames;\n"
        "    int object_count;\n"
        "    int collections;\n"
        "    int pin_count;\n"
        "    unsigned long bytes_allocated;\n"
        "    unsigned long bytes_freed;\n"
        "    unsigned long next_gc_bytes;\n"
        "    int next_gc_objects;\n"
        "    int enabled;\n"
        "} SageGcState;\n"
        "\n"
        "#define SAGE_GC_MIN_TRIGGER_BYTES 65536UL\n"
        "#define SAGE_GC_MIN_TRIGGER_OBJECTS 128\n"
        "static SageGcState sage_gc = {NULL, NULL, 0, 0, 0, 0, 0, SAGE_GC_MIN_TRIGGER_BYTES, SAGE_GC_MIN_TRIGGER_OBJECTS, 1};\n"
        "\n"
        "/* Exception handling via setjmp/longjmp */\n"
        "#define SAGE_MAX_TRY_DEPTH 64\n"
        "static jmp_buf sage_try_stack[SAGE_MAX_TRY_DEPTH];\n"
        "static SageValue sage_exception_value;\n"
        "static int sage_try_depth = 0;\n"
        "\n"
        "static void sage_fail(const char* message) {\n"
        "    fputs(message, stderr);\n"
        "    fputc('\\n', stderr);\n"
        "    exit(1);\n"
        "}\n"
        "\n"
        "static unsigned long sage_gc_live_bytes(void) {\n"
        "    return sage_gc.bytes_allocated - sage_gc.bytes_freed;\n"
        "}\n"
        "\n"
        "static void sage_gc_recompute_thresholds(unsigned long reclaimed_bytes, int reclaimed_objects) {\n"
        "    unsigned long live_bytes = sage_gc_live_bytes();\n"
        "    int live_objects = sage_gc.object_count;\n"
        "    unsigned long byte_padding = live_bytes / 2;\n"
        "    int object_padding = live_objects / 2;\n"
        "    if (byte_padding < (SAGE_GC_MIN_TRIGGER_BYTES / 2)) byte_padding = SAGE_GC_MIN_TRIGGER_BYTES / 2;\n"
        "    if (object_padding < (SAGE_GC_MIN_TRIGGER_OBJECTS / 2)) object_padding = SAGE_GC_MIN_TRIGGER_OBJECTS / 2;\n"
        "    if (reclaimed_bytes <= live_bytes / 8) {\n"
        "        byte_padding /= 2;\n"
        "        if (byte_padding < (SAGE_GC_MIN_TRIGGER_BYTES / 2)) byte_padding = SAGE_GC_MIN_TRIGGER_BYTES / 2;\n"
        "    } else if (reclaimed_bytes >= live_bytes) {\n"
        "        byte_padding *= 2;\n"
        "    }\n"
        "    if (reclaimed_objects <= live_objects / 8) {\n"
        "        object_padding /= 2;\n"
        "        if (object_padding < (SAGE_GC_MIN_TRIGGER_OBJECTS / 2)) object_padding = SAGE_GC_MIN_TRIGGER_OBJECTS / 2;\n"
        "    } else if (reclaimed_objects >= live_objects) {\n"
        "        object_padding *= 2;\n"
        "    }\n"
        "    sage_gc.next_gc_bytes = live_bytes + byte_padding;\n"
        "    if (sage_gc.next_gc_bytes < SAGE_GC_MIN_TRIGGER_BYTES) sage_gc.next_gc_bytes = SAGE_GC_MIN_TRIGGER_BYTES;\n"
        "    sage_gc.next_gc_objects = live_objects + object_padding;\n"
        "    if (sage_gc.next_gc_objects < SAGE_GC_MIN_TRIGGER_OBJECTS) sage_gc.next_gc_objects = SAGE_GC_MIN_TRIGGER_OBJECTS;\n"
        "}\n"
        "\n"
        "static int sage_gc_try_mark(void* object) {\n"
        "    if (object == NULL) return 0;\n"
        "    SageGcHeader* header = ((SageGcHeader*)object) - 1;\n"
        "    if (header->marked) return 0;\n"
        "    header->marked = 1;\n"
        "    return 1;\n"
        "}\n"
        "\n"
        "static void sage_gc_mark_value(SageValue value);\n"
        "\n"
        "static void sage_gc_mark_roots(void) {\n"
        "    for (SageGcFrame* frame = sage_gc.frames; frame != NULL; frame = frame->prev) {\n"
        "        if (frame->slots == NULL) continue;\n"
        "        for (int i = 0; i < frame->slot_count; i++) {\n"
        "            if (frame->slots[i] != NULL && frame->slots[i]->defined) {\n"
        "                sage_gc_mark_value(frame->slots[i]->value);\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    if (sage_try_depth > 0) sage_gc_mark_value(sage_exception_value);\n"
        "}\n"
        "\n"
        "static size_t sage_gc_release_object(SageGcHeader* header) {\n"
        "    void* object = (void*)(header + 1);\n"
        "    size_t freed = sizeof(SageGcHeader) + header->size;\n"
        "    switch ((SageGcKind)header->kind) {\n"
        "        case SAGE_GC_STRING:\n"
        "            break;\n"
        "        case SAGE_GC_ARRAY: {\n"
        "            SageArray* array = (SageArray*)object;\n"
        "            freed += sizeof(SageValue) * (size_t)array->capacity;\n"
        "            free(array->elements);\n"
        "            break;\n"
        "        }\n"
        "        case SAGE_GC_DICT: {\n"
        "            SageDict* dict = (SageDict*)object;\n"
        "            freed += sizeof(char*) * (size_t)dict->capacity;\n"
        "            freed += sizeof(SageValue) * (size_t)dict->capacity;\n"
        "            for (int i = 0; i < dict->count; i++) {\n"
        "                if (dict->keys[i] != NULL) {\n"
        "                    freed += strlen(dict->keys[i]) + 1;\n"
        "                    free(dict->keys[i]);\n"
        "                }\n"
        "            }\n"
        "            free(dict->keys);\n"
        "            free(dict->values);\n"
        "            break;\n"
        "        }\n"
        "        case SAGE_GC_TUPLE: {\n"
        "            SageTuple* tuple = (SageTuple*)object;\n"
        "            freed += sizeof(SageValue) * (size_t)tuple->count;\n"
        "            free(tuple->elements);\n"
        "            break;\n"
        "        }\n"
        "    }\n"
        "    return freed;\n"
        "}\n"
        "\n"
        "static void sage_gc_collect(void) {\n"
        "    if (!sage_gc.enabled) return;\n"
        "    unsigned long before_bytes = sage_gc_live_bytes();\n"
        "    int before_objects = sage_gc.object_count;\n"
        "    sage_gc_mark_roots();\n"
        "    SageGcHeader** current = &sage_gc.objects;\n"
        "    while (*current != NULL) {\n"
        "        SageGcHeader* header = *current;\n"
        "        if (!header->marked) {\n"
        "            *current = header->next;\n"
        "            sage_gc.object_count--;\n"
        "            sage_gc.bytes_freed += sage_gc_release_object(header);\n"
        "            free(header);\n"
        "        } else {\n"
        "            header->marked = 0;\n"
        "            current = &header->next;\n"
        "        }\n"
        "    }\n"
        "    sage_gc.collections++;\n"
        "    sage_gc_recompute_thresholds(before_bytes - sage_gc_live_bytes(), before_objects - sage_gc.object_count);\n"
        "}\n"
        "\n"
        "static int sage_gc_should_collect(size_t incoming_size) {\n"
        "    if (!sage_gc.enabled || sage_gc.pin_count > 0) return 0;\n"
        "    if ((sage_gc.object_count + 1) >= sage_gc.next_gc_objects) return 1;\n"
        "    return sage_gc_live_bytes() + (unsigned long)sizeof(SageGcHeader) + (unsigned long)incoming_size >= sage_gc.next_gc_bytes;\n"
        "}\n"
        "\n"
        "static void* sage_gc_alloc(SageGcKind kind, size_t size) {\n"
        "    if (sage_gc.frames != NULL && sage_gc_should_collect(size)) sage_gc_collect();\n"
        "    size_t total = sizeof(SageGcHeader) + size;\n"
        "    SageGcHeader* header = (SageGcHeader*)malloc(total);\n"
        "    if (header == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    header->marked = 0;\n"
        "    header->kind = (unsigned char)kind;\n"
        "    header->size = size;\n"
        "    header->next = sage_gc.objects;\n"
        "    sage_gc.objects = header;\n"
        "    sage_gc.object_count++;\n"
        "    sage_gc.bytes_allocated += (unsigned long)total;\n"
        "    return (void*)(header + 1);\n"
        "}\n"
        "\n"
        "static void sage_gc_push_frame(SageGcFrame* frame, SageSlot** slots, int slot_count) {\n"
        "    frame->prev = sage_gc.frames;\n"
        "    frame->slots = slots;\n"
        "    frame->slot_count = slot_count;\n"
        "    sage_gc.frames = frame;\n"
        "}\n"
        "\n"
        "static void sage_gc_pop_frame(SageGcFrame* frame) {\n"
        "    if (sage_gc.frames == frame) sage_gc.frames = frame->prev;\n"
        "}\n"
        "\n"
        "static void sage_gc_pin(void) { sage_gc.pin_count++; }\n"
        "static void sage_gc_unpin(void) { if (sage_gc.pin_count > 0) sage_gc.pin_count--; }\n"
        "\n"
        "static SageValue sage_gc_return(SageGcFrame* frame, SageValue value) {\n"
        "    sage_gc_pop_frame(frame);\n"
        "    return value;\n"
        "}\n"
        "\n"
        "static void sage_gc_shutdown(void) {\n"
        "    SageGcHeader* object = sage_gc.objects;\n"
        "    while (object != NULL) {\n"
        "        SageGcHeader* next = object->next;\n"
        "        sage_gc.bytes_freed += sage_gc_release_object(object);\n"
        "        free(object);\n"
        "        object = next;\n"
        "    }\n"
        "    sage_gc.objects = NULL;\n"
        "    sage_gc.object_count = 0;\n"
        "}\n"
        "\n"
        "static void sage_gc_mark_value(SageValue value) {\n"
        "    switch (value.type) {\n"
        "        case SAGE_TAG_STRING:\n"
        "            (void)sage_gc_try_mark((void*)value.as.string);\n"
        "            return;\n"
        "        case SAGE_TAG_ARRAY:\n"
        "            if (sage_gc_try_mark(value.as.array)) {\n"
        "                for (int i = 0; i < value.as.array->count; i++) sage_gc_mark_value(value.as.array->elements[i]);\n"
        "            }\n"
        "            return;\n"
        "        case SAGE_TAG_DICT:\n"
        "            if (sage_gc_try_mark(value.as.dict)) {\n"
        "                for (int i = 0; i < value.as.dict->count; i++) sage_gc_mark_value(value.as.dict->values[i]);\n"
        "            }\n"
        "            return;\n"
        "        case SAGE_TAG_TUPLE:\n"
        "            if (sage_gc_try_mark(value.as.tuple)) {\n"
        "                for (int i = 0; i < value.as.tuple->count; i++) sage_gc_mark_value(value.as.tuple->elements[i]);\n"
        "            }\n"
        "            return;\n"
        "        default:\n"
        "            return;\n"
        "    }\n"
        "}\n"
        "\n"
        "static char* sage_dup_string(const char* text) {\n"
            "    size_t len = strlen(text);\n"
            "    char* copy = (char*)malloc(len + 1);\n"
            "    if (copy == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
            "    memcpy(copy, text, len + 1);\n"
            "    return copy;\n"
        "}\n"
        "\n"
        "static char* sage_gc_copy_string(const char* text) {\n"
        "    size_t len = strlen(text);\n"
        "    char* copy = (char*)sage_gc_alloc(SAGE_GC_STRING, len + 1);\n"
        "    memcpy(copy, text, len + 1);\n"
        "    return copy;\n"
        "}\n"
        "\n"
        "static SageArray* sage_new_array(void) {\n"
        "    SageArray* array = (SageArray*)sage_gc_alloc(SAGE_GC_ARRAY, sizeof(SageArray));\n"
        "    array->count = 0;\n"
        "    array->capacity = 0;\n"
        "    array->elements = NULL;\n"
        "    return array;\n"
        "}\n"
        "\n"
        "static SageValue sage_nil(void) { SageValue v; v.type = SAGE_TAG_NIL; v.as.number = 0; return v; }\n"
        "static SageValue sage_number(double value) { SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = value; return v; }\n"
        "static SageValue sage_bool(int value) { SageValue v; v.type = SAGE_TAG_BOOL; v.as.boolean = value ? 1 : 0; return v; }\n"
        "static SageValue sage_string(const char* value) { SageValue v; v.type = SAGE_TAG_STRING; v.as.string = sage_gc_copy_string(value == NULL ? \"\" : value); return v; }\n"
        "static SageValue sage_string_take(char* value) { SageValue v = sage_string(value == NULL ? \"\" : value); free(value); return v; }\n"
        "static SageValue sage_array(void) { SageValue v; v.type = SAGE_TAG_ARRAY; v.as.array = sage_new_array(); return v; }\n"
        "static SageSlot sage_slot_undefined(void) { SageSlot slot; slot.defined = 0; slot.value = sage_nil(); return slot; }\n"
        "\n"
        ,
        out
    );

    fputs(
        "static SageValue sage_make_dict(void) {\n"
        "    SageDict* dict = (SageDict*)sage_gc_alloc(SAGE_GC_DICT, sizeof(SageDict));\n"
        "    dict->keys = NULL;\n"
        "    dict->values = NULL;\n"
        "    dict->count = 0;\n"
        "    dict->capacity = 0;\n"
        "    SageValue v; v.type = SAGE_TAG_DICT; v.as.dict = dict;\n"
        "    return v;\n"
        "}\n"
        "\n"
        "static void sage_dict_set(SageDict* dict, const char* key, SageValue value) {\n"
        "    for (int i = 0; i < dict->count; i++) {\n"
        "        if (strcmp(dict->keys[i], key) == 0) {\n"
        "            dict->values[i] = value;\n"
        "            return;\n"
        "        }\n"
        "    }\n"
        "    if (dict->count >= dict->capacity) {\n"
        "        int cap = dict->capacity == 0 ? 4 : dict->capacity * 2;\n"
        "        dict->keys = (char**)realloc(dict->keys, sizeof(char*) * (size_t)cap);\n"
        "        dict->values = (SageValue*)realloc(dict->values, sizeof(SageValue) * (size_t)cap);\n"
        "        if (dict->keys == NULL || dict->values == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "        dict->capacity = cap;\n"
        "    }\n"
        "    dict->keys[dict->count] = sage_dup_string(key);\n"
        "    dict->values[dict->count] = value;\n"
        "    dict->count++;\n"
        "}\n"
        "\n"
        "static SageValue sage_make_dict_from_entries(int count, const char** keys, const SageValue* values) {\n"
        "    sage_gc_pin();\n"
        "    SageValue dict = sage_make_dict();\n"
        "    for (int i = 0; i < count; i++) {\n"
        "        sage_dict_set(dict.as.dict, keys[i], values[i]);\n"
        "    }\n"
        "    sage_gc_unpin();\n"
        "    return dict;\n"
        "}\n"
        "\n"
        "static SageValue sage_dict_get(SageDict* dict, const char* key) {\n"
        "    for (int i = 0; i < dict->count; i++) {\n"
        "        if (strcmp(dict->keys[i], key) == 0) return dict->values[i];\n"
        "    }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_make_tuple(int count, const SageValue* values) {\n"
        "    sage_gc_pin();\n"
        "    SageTuple* tuple = (SageTuple*)sage_gc_alloc(SAGE_GC_TUPLE, sizeof(SageTuple));\n"
        "    tuple->count = count;\n"
        "    tuple->elements = (SageValue*)malloc(sizeof(SageValue) * (size_t)count);\n"
        "    if (tuple->elements == NULL && count > 0) sage_fail(\"Runtime Error: out of memory\");\n"
        "    for (int i = 0; i < count; i++) tuple->elements[i] = values[i];\n"
        "    SageValue v; v.type = SAGE_TAG_TUPLE; v.as.tuple = tuple;\n"
        "    sage_gc_unpin();\n"
        "    return v;\n"
        "}\n"
        "\n"
        "static void sage_raise(SageValue value) {\n"
        "    if (sage_try_depth > 0) {\n"
        "        sage_exception_value = value;\n"
        "        longjmp(sage_try_stack[sage_try_depth - 1], 1);\n"
        "    }\n"
        "    fputs(\"Unhandled exception: \", stderr);\n"
        "    if (value.type == SAGE_TAG_STRING) fputs(value.as.string, stderr);\n"
        "    else fputs(\"(unknown)\", stderr);\n"
        "    fputc('\\n', stderr);\n"
        "    exit(1);\n"
        "}\n"
        "\n"
        "static void sage_array_reserve(SageArray* array, int needed) {\n"
        "    if (array->capacity >= needed) return;\n"
        "    int capacity = array->capacity == 0 ? 4 : array->capacity;\n"
        "    while (capacity < needed) capacity *= 2;\n"
        "    SageValue* elements = (SageValue*)realloc(array->elements, sizeof(SageValue) * (size_t)capacity);\n"
        "    if (elements == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    array->elements = elements;\n"
        "    array->capacity = capacity;\n"
        "}\n"
        "\n"
        "static void sage_array_push_raw(SageArray* array, SageValue value) {\n"
        "    sage_array_reserve(array, array->count + 1);\n"
        "    array->elements[array->count++] = value;\n"
        "}\n"
        "\n"
        "static SageValue sage_make_array(int count, const SageValue* values) {\n"
        "    sage_gc_pin();\n"
        "    SageValue array = sage_array();\n"
        "    for (int i = 0; i < count; i++) {\n"
        "        sage_array_push_raw(array.as.array, values[i]);\n"
        "    }\n"
        "    sage_gc_unpin();\n"
        "    return array;\n"
        "}\n"
        "\n"
        ,
        out
    );

    fputs(
        "static int sage_truthy(SageValue value) {\n"
        "    if (value.type == SAGE_TAG_NIL) return 0;\n"
        "    if (value.type == SAGE_TAG_BOOL) return value.as.boolean;\n"
        "    return 1;\n"
        "}\n"
        "\n"
        "static SageValue sage_load_slot(const SageSlot* slot, const char* name) {\n"
        "    if (!slot->defined) {\n"
        "        fprintf(stderr, \"Runtime Error: Undefined variable '%s'.\\n\", name);\n"
        "        exit(1);\n"
        "    }\n"
        "    return slot->value;\n"
        "}\n"
        "\n"
        "static void sage_define_slot(SageSlot* slot, SageValue value) {\n"
        "    slot->defined = 1;\n"
        "    slot->value = value;\n"
        "}\n"
        "\n"
        "static SageValue sage_assign_slot(SageSlot* slot, const char* name, SageValue value) {\n"
        "    if (!slot->defined) {\n"
        "        fprintf(stderr, \"Runtime Error: Undefined variable '%s'.\\n\", name);\n"
        "        exit(1);\n"
        "    }\n"
        "    slot->value = value;\n"
        "    return value;\n"
        "}\n"
        "\n"
        "static int sage_values_equal(SageValue left, SageValue right) {\n"
        "    if (left.type != right.type) return 0;\n"
        "    switch (left.type) {\n"
        "        case SAGE_TAG_NIL: return 1;\n"
        "        case SAGE_TAG_NUMBER: return left.as.number == right.as.number;\n"
        "        case SAGE_TAG_BOOL: return left.as.boolean == right.as.boolean;\n"
        "        case SAGE_TAG_STRING: return strcmp(left.as.string, right.as.string) == 0;\n"
        "        case SAGE_TAG_ARRAY: return left.as.array == right.as.array;\n"
        "        case SAGE_TAG_DICT: return left.as.dict == right.as.dict;\n"
        "        case SAGE_TAG_TUPLE: return left.as.tuple == right.as.tuple;\n"
        "    }\n"
        "    return 0;\n"
        "}\n"
        "\n"
        "static void sage_print_value(SageValue value) {\n"
        "    switch (value.type) {\n"
        "        case SAGE_TAG_NUMBER: printf(\"%g\", value.as.number); break;\n"
        "        case SAGE_TAG_BOOL: fputs(value.as.boolean ? \"true\" : \"false\", stdout); break;\n"
        "        case SAGE_TAG_STRING: fputs(value.as.string, stdout); break;\n"
        "        case SAGE_TAG_ARRAY:\n"
        "            fputc('[', stdout);\n"
        "            for (int i = 0; i < value.as.array->count; i++) {\n"
        "                if (i > 0) fputs(\", \", stdout);\n"
        "                sage_print_value(value.as.array->elements[i]);\n"
        "            }\n"
        "            fputc(']', stdout);\n"
        "            break;\n"
        "        case SAGE_TAG_DICT:\n"
        "            fputc('{', stdout);\n"
        "            for (int i = 0; i < value.as.dict->count; i++) {\n"
        "                if (i > 0) fputs(\", \", stdout);\n"
        "                printf(\"\\\"%s\\\": \", value.as.dict->keys[i]);\n"
        "                sage_print_value(value.as.dict->values[i]);\n"
        "            }\n"
        "            fputc('}', stdout);\n"
        "            break;\n"
        "        case SAGE_TAG_TUPLE:\n"
        "            fputc('(', stdout);\n"
        "            for (int i = 0; i < value.as.tuple->count; i++) {\n"
        "                if (i > 0) fputs(\", \", stdout);\n"
        "                sage_print_value(value.as.tuple->elements[i]);\n"
        "            }\n"
        "            fputc(')', stdout);\n"
        "            break;\n"
        "        case SAGE_TAG_NIL: fputs(\"nil\", stdout); break;\n"
        "    }\n"
        "}\n"
        "\n"
        "static void sage_print_ln(SageValue value) {\n"
        "    sage_print_value(value);\n"
        "    fputc('\\n', stdout);\n"
        "}\n"
        "\n"
        "static SageValue sage_str(SageValue value) {\n"
        "    char buffer[64];\n"
        "    switch (value.type) {\n"
        "        case SAGE_TAG_STRING: return value;\n"
        "        case SAGE_TAG_NUMBER:\n"
        "            snprintf(buffer, sizeof(buffer), \"%g\", value.as.number);\n"
        "            return sage_string(buffer);\n"
        "        case SAGE_TAG_BOOL:\n"
        "            return sage_string(value.as.boolean ? \"true\" : \"false\");\n"
        "        case SAGE_TAG_NIL:\n"
        "            return sage_string(\"nil\");\n"
        "        case SAGE_TAG_ARRAY:\n"
        "            return sage_string(\"<array>\");\n"
        "        case SAGE_TAG_DICT:\n"
        "            return sage_string(\"<dict>\");\n"
        "        case SAGE_TAG_TUPLE:\n"
        "            return sage_string(\"<tuple>\");\n"
        "    }\n"
        "    return sage_string(\"nil\");\n"
        "}\n"
        "\n"
        ,
        out
    );

    fputs(
        "static SageValue sage_len(SageValue value) {\n"
        "    if (value.type == SAGE_TAG_STRING) return sage_number((double)strlen(value.as.string));\n"
        "    if (value.type == SAGE_TAG_ARRAY) return sage_number((double)value.as.array->count);\n"
        "    if (value.type == SAGE_TAG_DICT) return sage_number((double)value.as.dict->count);\n"
        "    if (value.type == SAGE_TAG_TUPLE) return sage_number((double)value.as.tuple->count);\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_index(SageValue collection, SageValue index) {\n"
        "    if (collection.type == SAGE_TAG_ARRAY && index.type == SAGE_TAG_NUMBER) {\n"
        "        int idx = (int)index.as.number;\n"
        "        if (idx < 0 || idx >= collection.as.array->count) return sage_nil();\n"
        "        return collection.as.array->elements[idx];\n"
        "    }\n"
        "    if (collection.type == SAGE_TAG_DICT && index.type == SAGE_TAG_STRING) {\n"
        "        return sage_dict_get(collection.as.dict, index.as.string);\n"
        "    }\n"
        "    if (collection.type == SAGE_TAG_TUPLE && index.type == SAGE_TAG_NUMBER) {\n"
        "        int idx = (int)index.as.number;\n"
        "        if (idx < 0 || idx >= collection.as.tuple->count) return sage_nil();\n"
        "        return collection.as.tuple->elements[idx];\n"
        "    }\n"
        "    if (collection.type == SAGE_TAG_STRING && index.type == SAGE_TAG_NUMBER) {\n"
        "        int idx = (int)index.as.number;\n"
        "        int len = (int)strlen(collection.as.string);\n"
        "        if (idx < 0 || idx >= len) return sage_nil();\n"
        "        char buf[2] = {collection.as.string[idx], '\\0'};\n"
        "        return sage_string(buf);\n"
        "    }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_slice(SageValue array, SageValue start, SageValue end) {\n"
        "    if (array.type != SAGE_TAG_ARRAY) return sage_nil();\n"
        "    sage_gc_pin();\n"
        "    int start_index = 0;\n"
        "    int end_index = array.as.array->count;\n"
        "    if (start.type == SAGE_TAG_NUMBER) start_index = (int)start.as.number;\n"
        "    else if (start.type != SAGE_TAG_NIL) { sage_gc_unpin(); return sage_nil(); }\n"
        "    if (end.type == SAGE_TAG_NUMBER) end_index = (int)end.as.number;\n"
        "    else if (end.type != SAGE_TAG_NIL) { sage_gc_unpin(); return sage_nil(); }\n"
        "    if (start_index < 0) start_index = array.as.array->count + start_index;\n"
        "    if (end_index < 0) end_index = array.as.array->count + end_index;\n"
        "    if (start_index < 0) start_index = 0;\n"
        "    if (end_index > array.as.array->count) end_index = array.as.array->count;\n"
        "    if (start_index >= end_index) { SageValue empty = sage_array(); sage_gc_unpin(); return empty; }\n"
        "    SageValue result = sage_array();\n"
        "    for (int i = start_index; i < end_index; i++) {\n"
        "        sage_array_push_raw(result.as.array, array.as.array->elements[i]);\n"
        "    }\n"
        "    sage_gc_unpin();\n"
        "    return result;\n"
        "}\n"
        "\n"
        "static SageValue sage_push(SageValue array, SageValue value) {\n"
        "    if (array.type != SAGE_TAG_ARRAY) return sage_nil();\n"
        "    sage_array_push_raw(array.as.array, value);\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_pop(SageValue array) {\n"
        "    if (array.type != SAGE_TAG_ARRAY || array.as.array->count == 0) return sage_nil();\n"
        "    return array.as.array->elements[--array.as.array->count];\n"
        "}\n"
        "\n"
        ,
        out
    );

    fputs(
        "static SageValue sage_range2(SageValue start, SageValue end) {\n"
        "    if (start.type != SAGE_TAG_NUMBER || end.type != SAGE_TAG_NUMBER) return sage_nil();\n"
        "    sage_gc_pin();\n"
        "    SageValue result = sage_array();\n"
        "    for (int i = (int)start.as.number; i < (int)end.as.number; i++) {\n"
        "        sage_array_push_raw(result.as.array, sage_number((double)i));\n"
        "    }\n"
        "    sage_gc_unpin();\n"
        "    return result;\n"
        "}\n"
        "\n"
        "static SageValue sage_range1(SageValue end) {\n"
        "    return sage_range2(sage_number(0), end);\n"
        "}\n"
        "\n"
        "static SageValue sage_add(SageValue left, SageValue right) {\n"
        "    if (left.type == SAGE_TAG_NUMBER && right.type == SAGE_TAG_NUMBER) {\n"
        "        return sage_number(left.as.number + right.as.number);\n"
        "    }\n"
        "    if (left.type == SAGE_TAG_STRING && right.type == SAGE_TAG_STRING) {\n"
        "        size_t len1 = strlen(left.as.string);\n"
        "        size_t len2 = strlen(right.as.string);\n"
        "        char* result = (char*)malloc(len1 + len2 + 1);\n"
        "        if (result == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "        memcpy(result, left.as.string, len1);\n"
        "        memcpy(result + len1, right.as.string, len2 + 1);\n"
        "        return sage_string_take(result);\n"
        "    }\n"
        "    sage_fail(\"Runtime Error: Operands must be numbers or strings.\");\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        ,
        out
    );

    fputs(
        "static SageValue sage_sub(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number(left.as.number - right.as.number);\n"
        "}\n"
        "static SageValue sage_mul(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number(left.as.number * right.as.number);\n"
        "}\n"
        "static SageValue sage_div(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    if (right.as.number == 0) return sage_nil();\n"
        "    return sage_number(left.as.number / right.as.number);\n"
        "}\n"
        "static SageValue sage_mod(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    if ((int)right.as.number == 0) return sage_nil();\n"
        "    return sage_number((double)((int)left.as.number % (int)right.as.number));\n"
        "}\n"
        "static SageValue sage_eq(SageValue left, SageValue right) { return sage_bool(sage_values_equal(left, right)); }\n"
        "static SageValue sage_neq(SageValue left, SageValue right) { return sage_bool(!sage_values_equal(left, right)); }\n"
        "static SageValue sage_gt(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_bool(left.as.number > right.as.number);\n"
        "}\n"
        "static SageValue sage_lt(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_bool(left.as.number < right.as.number);\n"
        "}\n"
        "static SageValue sage_gte(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_bool(left.as.number >= right.as.number);\n"
        "}\n"
        "static SageValue sage_lte(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_bool(left.as.number <= right.as.number);\n"
        "}\n"
        "static SageValue sage_not(SageValue value) { return sage_bool(!sage_truthy(value)); }\n"
        "static SageValue sage_and(SageValue left, SageValue right) { return sage_bool(sage_truthy(left) && sage_truthy(right)); }\n"
        "static SageValue sage_or(SageValue left, SageValue right) { return sage_bool(sage_truthy(left) || sage_truthy(right)); }\n"
        "static SageValue sage_bit_not(SageValue value) {\n"
        "    if (value.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Bitwise NOT operand must be a number.\");\n"
        "    return sage_number((double)(~(long long)value.as.number));\n"
        "}\n"
        ,
        out
    );

    fputs(
        "static SageValue sage_bit_and(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number((double)(((long long)left.as.number) & ((long long)right.as.number)));\n"
        "}\n"
        "static SageValue sage_bit_or(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number((double)(((long long)left.as.number) | ((long long)right.as.number)));\n"
        "}\n"
        "static SageValue sage_bit_xor(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number((double)(((long long)left.as.number) ^ ((long long)right.as.number)));\n"
        "}\n"
        "static SageValue sage_lshift(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number((double)(((long long)left.as.number) << ((long long)right.as.number)));\n"
        "}\n"
        "static SageValue sage_rshift(SageValue left, SageValue right) {\n"
        "    if (left.type != SAGE_TAG_NUMBER || right.type != SAGE_TAG_NUMBER) sage_fail(\"Runtime Error: Operands must be numbers.\");\n"
        "    return sage_number((double)(((long long)left.as.number) >> ((long long)right.as.number)));\n"
        "}\n"
        "\n"
        "static SageValue sage_tonumber(SageValue value) {\n"
        "    if (value.type == SAGE_TAG_NUMBER) return value;\n"
        "    if (value.type == SAGE_TAG_STRING) {\n"
        "        char* end;\n"
        "        double result = strtod(value.as.string, &end);\n"
        "        if (end != value.as.string && *end == '\\0') return sage_number(result);\n"
        "    }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_dict_keys_fn(SageValue dict_val) {\n"
        "    if (dict_val.type != SAGE_TAG_DICT) return sage_array();\n"
        "    sage_gc_pin();\n"
        "    SageValue result = sage_array();\n"
        "    for (int i = 0; i < dict_val.as.dict->count; i++) {\n"
        "        sage_array_push_raw(result.as.array, sage_string(dict_val.as.dict->keys[i]));\n"
        "    }\n"
        "    sage_gc_unpin();\n"
        "    return result;\n"
        "}\n"
        "\n"
        "static SageValue sage_dict_values_fn(SageValue dict_val) {\n"
        "    if (dict_val.type != SAGE_TAG_DICT) return sage_array();\n"
        "    sage_gc_pin();\n"
        "    SageValue result = sage_array();\n"
        "    for (int i = 0; i < dict_val.as.dict->count; i++) {\n"
        "        sage_array_push_raw(result.as.array, dict_val.as.dict->values[i]);\n"
        "    }\n"
        "    sage_gc_unpin();\n"
        "    return result;\n"
        "}\n"
        "\n"
        "static SageValue sage_dict_has_fn(SageValue dict_val, SageValue key) {\n"
        "    if (dict_val.type != SAGE_TAG_DICT || key.type != SAGE_TAG_STRING) return sage_bool(0);\n"
        "    for (int i = 0; i < dict_val.as.dict->count; i++) {\n"
        "        if (strcmp(dict_val.as.dict->keys[i], key.as.string) == 0) return sage_bool(1);\n"
        "    }\n"
        "    return sage_bool(0);\n"
        "}\n"
        "\n"
        "static SageValue sage_dict_delete_fn(SageValue dict_val, SageValue key) {\n"
        "    if (dict_val.type != SAGE_TAG_DICT || key.type != SAGE_TAG_STRING) return sage_nil();\n"
        "    SageDict* dict = dict_val.as.dict;\n"
        "    for (int i = 0; i < dict->count; i++) {\n"
        "        if (strcmp(dict->keys[i], key.as.string) == 0) {\n"
        "            free(dict->keys[i]);\n"
        "            for (int j = i; j < dict->count - 1; j++) {\n"
        "                dict->keys[j] = dict->keys[j + 1];\n"
        "                dict->values[j] = dict->values[j + 1];\n"
        "            }\n"
        "            dict->count--;\n"
        "            return sage_bool(1);\n"
        "        }\n"
        "    }\n"
        "    return sage_bool(0);\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_gc_collect_fn(void) {\n"
        "    sage_gc_collect();\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_gc_enable_fn(void) {\n"
        "    sage_gc.enabled = 1;\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_gc_disable_fn(void) {\n"
        "    sage_gc.enabled = 0;\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_gc_stats_fn(void) {\n"
        "    int next_gc = sage_gc.next_gc_objects - sage_gc.object_count;\n"
        "    if (next_gc < 0) next_gc = 0;\n"
        "    return sage_make_dict_from_entries(7,\n"
        "        (const char*[]){\"bytes_allocated\", \"current_bytes\", \"num_objects\", \"collections\", \"objects_freed\", \"next_gc\", \"next_gc_bytes\"},\n"
        "        (SageValue[]){\n"
        "            sage_number((double)sage_gc.bytes_allocated),\n"
        "            sage_number((double)sage_gc_live_bytes()),\n"
        "            sage_number((double)sage_gc.object_count),\n"
        "            sage_number((double)sage_gc.collections),\n"
        "            sage_number(0),\n"
        "            sage_number((double)next_gc),\n"
        "            sage_number((double)sage_gc.next_gc_bytes)\n"
        "        });\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_gc_collections_fn(void) {\n"
        "    return sage_number((double)sage_gc.collections);\n"
        "}\n"
        "\n",
        out
    );

    /* String builtins */
    fputs(
        "#include <ctype.h>\n"
        "static SageValue sage_upper(SageValue value) {\n"
        "    if (value.type != SAGE_TAG_STRING) return sage_nil();\n"
        "    size_t len = strlen(value.as.string);\n"
        "    char* result = (char*)malloc(len + 1);\n"
        "    if (result == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    for (size_t i = 0; i < len; i++) result[i] = (char)toupper((unsigned char)value.as.string[i]);\n"
        "    result[len] = '\\0';\n"
        "    return sage_string_take(result);\n"
        "}\n"
        "static SageValue sage_lower(SageValue value) {\n"
        "    if (value.type != SAGE_TAG_STRING) return sage_nil();\n"
        "    size_t len = strlen(value.as.string);\n"
        "    char* result = (char*)malloc(len + 1);\n"
        "    if (result == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    for (size_t i = 0; i < len; i++) result[i] = (char)tolower((unsigned char)value.as.string[i]);\n"
        "    result[len] = '\\0';\n"
        "    return sage_string_take(result);\n"
        "}\n"
        "static SageValue sage_strip_fn(SageValue value) {\n"
        "    if (value.type != SAGE_TAG_STRING) return sage_nil();\n"
        "    const char* s = value.as.string;\n"
        "    while (*s && isspace((unsigned char)*s)) s++;\n"
        "    const char* end = s + strlen(s);\n"
        "    while (end > s && isspace((unsigned char)*(end - 1))) end--;\n"
        "    size_t len = (size_t)(end - s);\n"
        "    char* result = (char*)malloc(len + 1);\n"
        "    if (result == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    memcpy(result, s, len);\n"
        "    result[len] = '\\0';\n"
        "    return sage_string_take(result);\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_split_fn(SageValue str_val, SageValue delim_val) {\n"
        "    if (str_val.type != SAGE_TAG_STRING || delim_val.type != SAGE_TAG_STRING) return sage_array();\n"
        "    sage_gc_pin();\n"
        "    const char* s = str_val.as.string;\n"
        "    const char* delim = delim_val.as.string;\n"
        "    size_t dlen = strlen(delim);\n"
        "    SageValue result = sage_array();\n"
        "    if (dlen == 0) {\n"
        "        for (size_t i = 0; s[i]; i++) {\n"
        "            char buf[2] = {s[i], '\\0'};\n"
        "            sage_array_push_raw(result.as.array, sage_string(buf));\n"
        "        }\n"
        "        sage_gc_unpin();\n"
        "        return result;\n"
        "    }\n"
        "    const char* start = s;\n"
        "    const char* found;\n"
        "    while ((found = strstr(start, delim)) != NULL) {\n"
        "        size_t len = (size_t)(found - start);\n"
        "        char* part = (char*)malloc(len + 1);\n"
        "        if (part == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "        memcpy(part, start, len);\n"
        "        part[len] = '\\0';\n"
        "        sage_array_push_raw(result.as.array, sage_string_take(part));\n"
        "        start = found + dlen;\n"
        "    }\n"
        "    sage_array_push_raw(result.as.array, sage_string(start));\n"
        "    sage_gc_unpin();\n"
        "    return result;\n"
        "}\n"
        "\n"
        "static SageValue sage_join_fn(SageValue arr_val, SageValue delim_val) {\n"
        "    if (arr_val.type != SAGE_TAG_ARRAY || delim_val.type != SAGE_TAG_STRING) return sage_nil();\n"
        "    SageArray* arr = arr_val.as.array;\n"
        "    const char* delim = delim_val.as.string;\n"
        "    size_t dlen = strlen(delim);\n"
        "    if (arr->count == 0) return sage_string(\"\");\n"
        "    size_t total = 0;\n"
        "    for (int i = 0; i < arr->count; i++) {\n"
        "        if (arr->elements[i].type == SAGE_TAG_STRING) total += strlen(arr->elements[i].as.string);\n"
        "        if (i > 0) total += dlen;\n"
        "    }\n"
        "    char* result = (char*)malloc(total + 1);\n"
        "    if (result == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    char* p = result;\n"
        "    for (int i = 0; i < arr->count; i++) {\n"
        "        if (i > 0) { memcpy(p, delim, dlen); p += dlen; }\n"
        "        if (arr->elements[i].type == SAGE_TAG_STRING) {\n"
        "            size_t len = strlen(arr->elements[i].as.string);\n"
        "            memcpy(p, arr->elements[i].as.string, len);\n"
        "            p += len;\n"
        "        }\n"
        "    }\n"
        "    *p = '\\0';\n"
        "    return sage_string_take(result);\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_replace_fn(SageValue str_val, SageValue old_val, SageValue new_val) {\n"
        "    if (str_val.type != SAGE_TAG_STRING || old_val.type != SAGE_TAG_STRING || new_val.type != SAGE_TAG_STRING)\n"
        "        return sage_nil();\n"
        "    const char* s = str_val.as.string;\n"
        "    const char* old_s = old_val.as.string;\n"
        "    const char* new_s = new_val.as.string;\n"
        "    size_t old_len = strlen(old_s);\n"
        "    size_t new_len = strlen(new_s);\n"
        "    if (old_len == 0) return sage_string(s);\n"
        "    size_t count = 0;\n"
        "    const char* tmp = s;\n"
        "    while ((tmp = strstr(tmp, old_s)) != NULL) { count++; tmp += old_len; }\n"
        "    size_t result_len = strlen(s) + count * (new_len - old_len);\n"
        "    char* result = (char*)malloc(result_len + 1);\n"
        "    if (result == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    char* p = result;\n"
        "    while (*s) {\n"
        "        if (strncmp(s, old_s, old_len) == 0) {\n"
        "            memcpy(p, new_s, new_len);\n"
        "            p += new_len;\n"
        "            s += old_len;\n"
        "        } else {\n"
        "            *p++ = *s++;\n"
        "        }\n"
        "    }\n"
        "    *p = '\\0';\n"
        "    return sage_string_take(result);\n"
        "}\n"
        "\n",
        out
    );

    /* Memory builtins */
    fputs(
        "#include <stdint.h>\n"
        "\n"
        "typedef struct {\n"
        "    void* ptr;\n"
        "    size_t size;\n"
        "    int owned;\n"
        "} SagePointer;\n"
        "\n"
        "static SageValue sage_mem_alloc(SageValue size_val) {\n"
        "    if (size_val.type != SAGE_TAG_NUMBER) { fputs(\"mem_alloc(): expects number\\n\", stderr); return sage_nil(); }\n"
        "    size_t size = (size_t)size_val.as.number;\n"
        "    if (size == 0 || size > 1024*1024*64) { fputs(\"mem_alloc(): invalid size\\n\", stderr); return sage_nil(); }\n"
        "    SagePointer* sp = (SagePointer*)malloc(sizeof(SagePointer));\n"
        "    if (sp == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    sp->ptr = calloc(1, size);\n"
        "    if (sp->ptr == NULL) { free(sp); sage_fail(\"Runtime Error: out of memory\"); }\n"
        "    sp->size = size;\n"
        "    sp->owned = 1;\n"
        "    SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = (double)(uintptr_t)sp;\n"
        "    return v;\n"
        "}\n"
        "\n"
        "static SagePointer* sage_as_pointer(SageValue v) {\n"
        "    if (v.type != SAGE_TAG_NUMBER) return NULL;\n"
        "    return (SagePointer*)(uintptr_t)v.as.number;\n"
        "}\n"
        "\n"
        "static SageValue sage_mem_free(SageValue ptr_val) {\n"
        "    SagePointer* sp = sage_as_pointer(ptr_val);\n"
        "    if (sp == NULL) { fputs(\"mem_free(): expects pointer\\n\", stderr); return sage_nil(); }\n"
        "    if (sp->ptr && sp->owned) { free(sp->ptr); sp->ptr = NULL; sp->size = 0; }\n"
        "    free(sp);\n"
        "    return sage_nil();\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_mem_read(SageValue ptr_val, SageValue off_val, SageValue type_val) {\n"
        "    SagePointer* sp = sage_as_pointer(ptr_val);\n"
        "    if (sp == NULL || sp->ptr == NULL || off_val.type != SAGE_TAG_NUMBER || type_val.type != SAGE_TAG_STRING)\n"
        "        return sage_nil();\n"
        "    size_t offset = (size_t)off_val.as.number;\n"
        "    const char* type = type_val.as.string;\n"
        "    unsigned char* base = (unsigned char*)sp->ptr + offset;\n"
        "    if (strcmp(type, \"byte\") == 0) { return sage_number((double)*base); }\n"
        "    if (strcmp(type, \"int\") == 0) { int v; memcpy(&v, base, sizeof(int)); return sage_number((double)v); }\n"
        "    if (strcmp(type, \"double\") == 0) { double v; memcpy(&v, base, sizeof(double)); return sage_number(v); }\n"
        "    if (strcmp(type, \"string\") == 0) { return sage_string((const char*)base); }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_mem_write(SageValue ptr_val, SageValue off_val, SageValue type_val, SageValue val) {\n"
        "    SagePointer* sp = sage_as_pointer(ptr_val);\n"
        "    if (sp == NULL || sp->ptr == NULL || off_val.type != SAGE_TAG_NUMBER || type_val.type != SAGE_TAG_STRING)\n"
        "        return sage_nil();\n"
        "    size_t offset = (size_t)off_val.as.number;\n"
        "    const char* type = type_val.as.string;\n"
        "    unsigned char* base = (unsigned char*)sp->ptr + offset;\n"
        "    if (strcmp(type, \"byte\") == 0 && val.type == SAGE_TAG_NUMBER) { *base = (unsigned char)val.as.number; }\n"
        "    else if (strcmp(type, \"int\") == 0 && val.type == SAGE_TAG_NUMBER) { int v = (int)val.as.number; memcpy(base, &v, sizeof(int)); }\n"
        "    else if (strcmp(type, \"double\") == 0 && val.type == SAGE_TAG_NUMBER) { double v = val.as.number; memcpy(base, &v, sizeof(double)); }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_mem_size(SageValue ptr_val) {\n"
        "    SagePointer* sp = sage_as_pointer(ptr_val);\n"
        "    if (sp == NULL) return sage_nil();\n"
        "    return sage_number((double)sp->size);\n"
        "}\n"
        "\n",
        out
    );

    /* Struct builtins */
    fputs(
        "static int sage_struct_type_info(const char* type, size_t* out_size, size_t* out_align) {\n"
        "    if (strcmp(type,\"char\")==0||strcmp(type,\"byte\")==0) { *out_size=1; *out_align=1; return 0; }\n"
        "    if (strcmp(type,\"short\")==0) { *out_size=sizeof(short); *out_align=sizeof(short); return 0; }\n"
        "    if (strcmp(type,\"int\")==0) { *out_size=sizeof(int); *out_align=sizeof(int); return 0; }\n"
        "    if (strcmp(type,\"long\")==0) { *out_size=sizeof(long); *out_align=sizeof(long); return 0; }\n"
        "    if (strcmp(type,\"float\")==0) { *out_size=sizeof(float); *out_align=sizeof(float); return 0; }\n"
        "    if (strcmp(type,\"double\")==0) { *out_size=sizeof(double); *out_align=sizeof(double); return 0; }\n"
        "    if (strcmp(type,\"ptr\")==0) { *out_size=sizeof(void*); *out_align=sizeof(void*); return 0; }\n"
        "    return -1;\n"
        "}\n"
        "\n"
        "static SageValue sage_struct_def(SageValue fields) {\n"
        "    if (fields.type != SAGE_TAG_ARRAY) return sage_nil();\n"
        "    sage_gc_pin();\n"
        "    SageValue def = sage_make_dict();\n"
        "    size_t offset = 0, max_align = 1;\n"
        "    for (int i = 0; i < fields.as.array->count; i++) {\n"
        "        SageValue pair = fields.as.array->elements[i];\n"
        "        if (pair.type != SAGE_TAG_ARRAY || pair.as.array->count < 2) continue;\n"
        "        if (pair.as.array->elements[0].type != SAGE_TAG_STRING ||\n"
        "            pair.as.array->elements[1].type != SAGE_TAG_STRING) continue;\n"
        "        const char* name = pair.as.array->elements[0].as.string;\n"
        "        const char* type = pair.as.array->elements[1].as.string;\n"
        "        size_t fsize, falign;\n"
        "        if (sage_struct_type_info(type, &fsize, &falign) != 0) continue;\n"
        "        if (falign > max_align) max_align = falign;\n"
        "        size_t rem = offset % falign;\n"
        "        if (rem != 0) offset += falign - rem;\n"
        ,
        out
    );

    fputs(
        "        /* store field: \"name\" -> [offset, type] */\n"
        "        SageValue field_info = sage_make_array(2, (SageValue[]){\n"
        "            sage_number((double)offset), sage_string(type)\n"
        "        });\n"
        "        sage_dict_set(def.as.dict, name, field_info);\n"
        "        offset += fsize;\n"
        "    }\n"
        "    size_t rem = offset % max_align;\n"
        "    if (rem != 0) offset += max_align - rem;\n"
        "    sage_dict_set(def.as.dict, \"__size__\", sage_number((double)offset));\n"
        "    sage_dict_set(def.as.dict, \"__align__\", sage_number((double)max_align));\n"
        "    sage_gc_unpin();\n"
        "    return def;\n"
        "}\n"
        "\n"
        "static SageValue sage_struct_new(SageValue def) {\n"
        "    if (def.type != SAGE_TAG_DICT) return sage_nil();\n"
        "    SageValue size_val = sage_dict_get(def.as.dict, \"__size__\");\n"
        "    if (size_val.type != SAGE_TAG_NUMBER) return sage_nil();\n"
        "    size_t size = (size_t)size_val.as.number;\n"
        "    SagePointer* sp = (SagePointer*)malloc(sizeof(SagePointer));\n"
        "    if (sp == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    sp->ptr = calloc(1, size);\n"
        "    if (sp->ptr == NULL) { free(sp); sage_fail(\"Runtime Error: out of memory\"); }\n"
        "    sp->size = size;\n"
        "    sp->owned = 1;\n"
        "    SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = (double)(uintptr_t)sp;\n"
        "    return v;\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_struct_get(SageValue ptr_val, SageValue def, SageValue field_name) {\n"
        "    SagePointer* sp = sage_as_pointer(ptr_val);\n"
        "    if (sp == NULL || sp->ptr == NULL || def.type != SAGE_TAG_DICT || field_name.type != SAGE_TAG_STRING)\n"
        "        return sage_nil();\n"
        "    SageValue info = sage_dict_get(def.as.dict, field_name.as.string);\n"
        "    if (info.type != SAGE_TAG_ARRAY || info.as.array->count < 2) return sage_nil();\n"
        "    size_t offset = (size_t)info.as.array->elements[0].as.number;\n"
        "    const char* type = info.as.array->elements[1].as.string;\n"
        "    unsigned char* base = (unsigned char*)sp->ptr + offset;\n"
        "    if (strcmp(type,\"char\")==0||strcmp(type,\"byte\")==0) return sage_number((double)*base);\n"
        "    if (strcmp(type,\"short\")==0) { short v; memcpy(&v,base,sizeof(short)); return sage_number((double)v); }\n"
        "    if (strcmp(type,\"int\")==0) { int v; memcpy(&v,base,sizeof(int)); return sage_number((double)v); }\n"
        "    if (strcmp(type,\"long\")==0) { long v; memcpy(&v,base,sizeof(long)); return sage_number((double)v); }\n"
        "    if (strcmp(type,\"float\")==0) { float v; memcpy(&v,base,sizeof(float)); return sage_number((double)v); }\n"
        "    if (strcmp(type,\"double\")==0) { double v; memcpy(&v,base,sizeof(double)); return sage_number(v); }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_struct_set(SageValue ptr_val, SageValue def, SageValue field_name, SageValue val) {\n"
        "    SagePointer* sp = sage_as_pointer(ptr_val);\n"
        "    if (sp == NULL || sp->ptr == NULL || def.type != SAGE_TAG_DICT || field_name.type != SAGE_TAG_STRING)\n"
        "        return sage_nil();\n"
        "    SageValue info = sage_dict_get(def.as.dict, field_name.as.string);\n"
        "    if (info.type != SAGE_TAG_ARRAY || info.as.array->count < 2) return sage_nil();\n"
        "    size_t offset = (size_t)info.as.array->elements[0].as.number;\n"
        "    const char* type = info.as.array->elements[1].as.string;\n"
        "    unsigned char* base = (unsigned char*)sp->ptr + offset;\n"
        "    if (val.type != SAGE_TAG_NUMBER) return sage_nil();\n"
        "    if (strcmp(type,\"char\")==0||strcmp(type,\"byte\")==0) { *base = (unsigned char)val.as.number; }\n"
        "    else if (strcmp(type,\"short\")==0) { short v=(short)val.as.number; memcpy(base,&v,sizeof(short)); }\n"
        "    else if (strcmp(type,\"int\")==0) { int v=(int)val.as.number; memcpy(base,&v,sizeof(int)); }\n"
        "    else if (strcmp(type,\"long\")==0) { long v=(long)val.as.number; memcpy(base,&v,sizeof(long)); }\n"
        "    else if (strcmp(type,\"float\")==0) { float v=(float)val.as.number; memcpy(base,&v,sizeof(float)); }\n"
        "    else if (strcmp(type,\"double\")==0) { double v=val.as.number; memcpy(base,&v,sizeof(double)); }\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_struct_size(SageValue def) {\n"
        "    if (def.type != SAGE_TAG_DICT) return sage_nil();\n"
        "    return sage_dict_get(def.as.dict, \"__size__\");\n"
        "}\n"
        "\n",
        out
    );

    /* Class/object system */
    fputs(
        "typedef SageValue (*SageMethodFn)(SageValue, int, SageValue*);\n"
        "typedef struct { const char* class_name; const char* method_name; SageMethodFn fn; } SageMethodEntry;\n"
        "typedef struct { const char* name; const char* parent; } SageClassEntry;\n"
        "#define SAGE_MAX_METHODS 256\n"
        "#define SAGE_MAX_CLASSES 64\n"
        "static SageMethodEntry sage_method_table[SAGE_MAX_METHODS];\n"
        "static int sage_method_count = 0;\n"
        "static SageClassEntry sage_class_registry[SAGE_MAX_CLASSES];\n"
        "static int sage_class_count = 0;\n"
        "\n"
        "static void sage_register_class(const char* name, const char* parent) {\n"
        "    if (sage_class_count >= SAGE_MAX_CLASSES) sage_fail(\"too many classes\");\n"
        "    sage_class_registry[sage_class_count].name = name;\n"
        "    sage_class_registry[sage_class_count].parent = parent;\n"
        "    sage_class_count++;\n"
        "}\n"
        "\n"
        "static void sage_register_method(const char* cls, const char* name, SageMethodFn fn) {\n"
        "    if (sage_method_count >= SAGE_MAX_METHODS) sage_fail(\"too many methods\");\n"
        "    sage_method_table[sage_method_count].class_name = cls;\n"
        "    sage_method_table[sage_method_count].method_name = name;\n"
        "    sage_method_table[sage_method_count].fn = fn;\n"
        "    sage_method_count++;\n"
        "}\n"
        "\n",
        out
    );

    fputs(
        "static SageValue sage_call_method(SageValue obj, const char* method, int argc, SageValue* argv) {\n"
        "    if (obj.type != SAGE_TAG_DICT) {\n"
        "        fprintf(stderr, \"Runtime Error: method call on non-instance.\\n\");\n"
        "        exit(1);\n"
        "    }\n"
        "    SageValue class_val = sage_dict_get(obj.as.dict, \"__class__\");\n"
        "    if (class_val.type != SAGE_TAG_STRING) {\n"
        "        fprintf(stderr, \"Runtime Error: no __class__ on instance.\\n\");\n"
        "        exit(1);\n"
        "    }\n"
        "    const char* current = class_val.as.string;\n"
        "    while (current != NULL) {\n"
        "        for (int i = 0; i < sage_method_count; i++) {\n"
        "            if (strcmp(sage_method_table[i].class_name, current) == 0 &&\n"
        "                strcmp(sage_method_table[i].method_name, method) == 0) {\n"
        "                return sage_method_table[i].fn(obj, argc, argv);\n"
        "            }\n"
        "        }\n"
        "        const char* parent = NULL;\n"
        "        for (int j = 0; j < sage_class_count; j++) {\n"
        "            if (strcmp(sage_class_registry[j].name, current) == 0) {\n"
        "                parent = sage_class_registry[j].parent;\n"
        "                break;\n"
        "            }\n"
        "        }\n"
        "        current = parent;\n"
        "    }\n"
        "    fprintf(stderr, \"Runtime Error: Undefined method '%s'.\\n\", method);\n"
        "    exit(1);\n"
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_construct(const char* class_name, const char* parent_name, int argc, SageValue* argv) {\n"
        "    sage_gc_pin();\n"
        "    SageValue inst = sage_make_dict();\n"
        "    sage_dict_set(inst.as.dict, \"__class__\", sage_string(class_name));\n"
        "    if (parent_name != NULL) sage_dict_set(inst.as.dict, \"__parent__\", sage_string(parent_name));\n"
        "    sage_gc_unpin();\n"
        "    const char* current = class_name;\n"
        "    while (current != NULL) {\n"
        "        for (int i = 0; i < sage_method_count; i++) {\n"
        "            if (strcmp(sage_method_table[i].class_name, current) == 0 &&\n"
        "                strcmp(sage_method_table[i].method_name, \"init\") == 0) {\n"
        "                sage_method_table[i].fn(inst, argc, argv);\n"
        "                return inst;\n"
        "            }\n"
        "        }\n"
        "        const char* parent = NULL;\n"
        "        for (int j = 0; j < sage_class_count; j++) {\n"
        "            if (strcmp(sage_class_registry[j].name, current) == 0) {\n"
        "                parent = sage_class_registry[j].parent;\n"
        "                break;\n"
        "            }\n"
        "        }\n"
        "        current = parent;\n"
        "    }\n"
        "    return inst;\n"
        "}\n"
        "\n",
        out
    );

    /* Architecture detection */
    fputs(
        "static SageValue sage_arch_fn(void) {\n"
        "#if defined(__x86_64__) || defined(_M_X64)\n"
        "    return sage_string(\"x86_64\");\n"
        "#elif defined(__aarch64__) || defined(_M_ARM64)\n"
        "    return sage_string(\"aarch64\");\n"
        "#elif defined(__riscv) && __riscv_xlen == 64\n"
        "    return sage_string(\"rv64\");\n"
        "#else\n"
        "    return sage_string(\"unknown\");\n"
        "#endif\n"
        "}\n"
        "\n",
        out
    );

    /* clock() and input() */
    if (target != COMPILER_TARGET_PICO) {
        fputs(
            "#include <time.h>\n"
            "static SageValue sage_clock_fn(void) {\n"
            "    return sage_number((double)clock() / CLOCKS_PER_SEC);\n"
            "}\n"
            "static SageValue sage_input_fn(SageValue prompt) {\n"
            "    if (prompt.type == SAGE_TAG_STRING) fputs(prompt.as.string, stdout);\n"
            "    char buf[4096];\n"
            "    if (fgets(buf, sizeof(buf), stdin) == NULL) return sage_nil();\n"
            "    size_t len = strlen(buf);\n"
            "    if (len > 0 && buf[len-1] == '\\n') buf[--len] = '\\0';\n"
            "    return sage_string(buf);\n"
            "}\n"
            "\n",
            out
        );
    }
}

static void emit_proc_prototypes(Compiler* compiler) {
    for (ProcEntry* proc = compiler->procs; proc != NULL; proc = proc->next) {
        emit_indent(compiler);
        fprintf(compiler->out, "static SageValue %s(", proc->c_name);
        for (int i = 0; i < proc->param_count; i++) {
            if (i > 0) {
                fputs(", ", compiler->out);
            }
            fprintf(compiler->out, "SageValue arg%d", i);
        }
        fputs(");\n", compiler->out);
    }
}

static void emit_global_slots(Compiler* compiler) {
    for (NameEntry* global = compiler->globals; global != NULL; global = global->next) {
        emit_line(compiler, "static SageSlot %s;", global->c_name);
    }
}

static int count_name_entries(NameEntry* entries) {
    int count = 0;
    for (NameEntry* entry = entries; entry != NULL; entry = entry->next) {
        count++;
    }
    return count;
}

static void emit_slot_declarations(Compiler* compiler, NameEntry* locals) {
    for (NameEntry* local = locals; local != NULL; local = local->next) {
        emit_line(compiler, "SageSlot %s = sage_slot_undefined();", local->c_name);
    }
}

static void emit_slot_frame_setup(Compiler* compiler, NameEntry* locals,
                                  const char* roots_name, const char* frame_name) {
    int count = count_name_entries(locals);

    if (count == 0) {
        emit_line(compiler, "SageGcFrame %s;", frame_name);
        emit_line(compiler, "sage_gc_push_frame(&%s, NULL, 0);", frame_name);
        return;
    }

    emit_indent(compiler);
    fprintf(compiler->out, "SageSlot* %s[%d] = {", roots_name, count);
    int index = 0;
    for (NameEntry* local = locals; local != NULL; local = local->next, index++) {
        if (index > 0) {
            fputs(", ", compiler->out);
        }
        fprintf(compiler->out, "&%s", local->c_name);
    }
    fputs("};\n", compiler->out);
    emit_line(compiler, "SageGcFrame %s;", frame_name);
    emit_line(compiler, "sage_gc_push_frame(&%s, %s, %d);", frame_name, roots_name, count);
}

static void emit_function_definition(Compiler* compiler, Stmt* stmt) {
    ProcStmt* proc_stmt = &stmt->as.proc;
    char* proc_name = token_to_string(proc_stmt->name);
    ProcEntry* proc = find_proc_entry(compiler->procs, proc_name);
    free(proc_name);
    if (proc == NULL) {
        compiler_error_at(compiler, &proc_stmt->name, NULL,
                          "internal compiler error: missing procedure metadata during code generation");
        return;
    }

    NameEntry* params = NULL;
    for (int i = 0; i < proc_stmt->param_count; i++) {
        char* param_name = token_to_string(proc_stmt->params[i]);
        if (find_name_entry(params, param_name) != NULL) {
            compiler_error_at(compiler, &proc_stmt->params[i],
                              "rename one of the parameters so every parameter name is unique",
                              "duplicate parameter '%s' in procedure '%.*s'",
                              param_name, proc_stmt->name.length, proc_stmt->name.start);
            free(param_name);
            return;
        }
        add_name_entry(compiler, &params, param_name, "sage_param");
        free(param_name);
    }

    NameEntry* previous_locals = compiler->locals;
    compiler->locals = params;
    collect_local_lets(compiler, proc_stmt->body, &compiler->locals);
    if (compiler->failed) {
        free_name_entries(compiler->locals);
        compiler->locals = previous_locals;
        return;
    }

    emit_indent(compiler);
    fprintf(compiler->out, "static SageValue %s(", proc->c_name);
    for (int i = 0; i < proc_stmt->param_count; i++) {
        if (i > 0) {
            fputs(", ", compiler->out);
        }
        fprintf(compiler->out, "SageValue arg%d", i);
    }
    fputs(") {\n", compiler->out);
    compiler->indent++;

    emit_slot_declarations(compiler, compiler->locals);
    emit_slot_frame_setup(compiler, compiler->locals, "sage_gc_roots", "sage_gc_frame");
    for (int i = 0; i < proc_stmt->param_count; i++) {
        char* param_name = token_to_string(proc_stmt->params[i]);
        NameEntry* param = find_name_entry(compiler->locals, param_name);
        free(param_name);
        emit_line(compiler, "sage_define_slot(&%s, arg%d);", param->c_name, i);
    }

    compiler->in_function_body = 1;
    emit_stmt_list(compiler, proc_stmt->body);
    compiler->in_function_body = 0;
    emit_line(compiler, "return sage_gc_return(&sage_gc_frame, sage_nil());");

    compiler->indent--;
    emit_line(compiler, "}");
    fputc('\n', compiler->out);

    free_name_entries(compiler->locals);
    compiler->locals = previous_locals;
}

static void emit_method_definition(Compiler* compiler, ClassInfo* cls, Stmt* method) {
    ProcStmt* proc = &method->as.proc;
    char* method_name = token_to_string(proc->name);

    int has_self = (proc->param_count > 0 &&
                    proc->params[0].length == 4 &&
                    strncmp(proc->params[0].start, "self", 4) == 0);
    int param_start = has_self ? 1 : 0;

    NameEntry* previous_locals = compiler->locals;
    compiler->locals = NULL;

    /* Add self as a local */
    add_name_entry(compiler, &compiler->locals, "self", "sage_local");

    /* Add non-self params as locals */
    for (int i = param_start; i < proc->param_count; i++) {
        char* pname = token_to_string(proc->params[i]);
        if (find_name_entry(compiler->locals, pname) == NULL) {
            add_name_entry(compiler, &compiler->locals, pname, "sage_local");
        }
        free(pname);
    }

    collect_local_lets(compiler, proc->body, &compiler->locals);
    if (compiler->failed) {
        free_name_entries(compiler->locals);
        compiler->locals = previous_locals;
        free(method_name);
        return;
    }

    emit_indent(compiler);
    fprintf(compiler->out, "static SageValue sage_method_%s_%s(SageValue _self, int _argc, SageValue* _argv) {\n",
            cls->class_name, method_name);
    compiler->indent++;

    emit_slot_declarations(compiler, compiler->locals);
    emit_slot_frame_setup(compiler, compiler->locals, "sage_gc_roots", "sage_gc_frame");

    /* Bind self */
    NameEntry* self_entry = find_name_entry(compiler->locals, "self");
    emit_line(compiler, "sage_define_slot(&%s, _self);", self_entry->c_name);

    /* Bind params from argv */
    int argv_idx = 0;
    for (int i = param_start; i < proc->param_count; i++) {
        char* pname = token_to_string(proc->params[i]);
        NameEntry* entry = find_name_entry(compiler->locals, pname);
        emit_line(compiler, "sage_define_slot(&%s, _argv[%d]);", entry->c_name, argv_idx++);
        free(pname);
    }

    emit_line(compiler, "(void)_argc;");

    compiler->in_function_body = 1;
    emit_stmt_list(compiler, proc->body);
    compiler->in_function_body = 0;
    emit_line(compiler, "return sage_gc_return(&sage_gc_frame, sage_nil());");

    compiler->indent--;
    emit_line(compiler, "}");
    fputc('\n', compiler->out);

    free_name_entries(compiler->locals);
    compiler->locals = previous_locals;
    free(method_name);
}

static void emit_method_prototypes(Compiler* compiler) {
    for (ClassInfo* cls = compiler->classes; cls != NULL; cls = cls->next) {
        for (Stmt* method = cls->methods; method != NULL; method = method->next) {
            if (method->type == STMT_PROC) {
                char* method_name = token_to_string(method->as.proc.name);
                emit_indent(compiler);
                fprintf(compiler->out,
                        "static SageValue sage_method_%s_%s(SageValue _self, int _argc, SageValue* _argv);\n",
                        cls->class_name, method_name);
                free(method_name);
            }
        }
    }
}

static void emit_function_definitions(Compiler* compiler, Stmt* program) {
    /* Emit module functions first */
    for (ImportedModule* m = compiler->modules; m != NULL; m = m->next) {
        for (Stmt* stmt = m->ast; stmt != NULL; stmt = stmt->next) {
            if (stmt->type == STMT_PROC) {
                emit_function_definition(compiler, stmt);
                if (compiler->failed) return;
            }
        }
    }

    /* Emit class methods */
    for (ClassInfo* cls = compiler->classes; cls != NULL; cls = cls->next) {
        for (Stmt* method = cls->methods; method != NULL; method = method->next) {
            if (method->type == STMT_PROC) {
                emit_method_definition(compiler, cls, method);
                if (compiler->failed) return;
            }
        }
    }

    /* Emit main program functions */
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_PROC) {
            emit_function_definition(compiler, stmt);
            if (compiler->failed) {
                return;
            }
        }
    }
}

static void emit_main_function(Compiler* compiler, Stmt* program, CompilerTarget target) {
    emit_line(compiler, "int main(void) {");
    compiler->indent++;

    if (target == COMPILER_TARGET_PICO) {
        emit_line(compiler, "stdio_init_all();");
        emit_line(compiler, "sleep_ms(2000);");
    }

    for (NameEntry* global = compiler->globals; global != NULL; global = global->next) {
        emit_line(compiler, "%s = sage_slot_undefined();", global->c_name);
    }
    emit_slot_frame_setup(compiler, compiler->globals, "sage_gc_global_roots", "sage_gc_main_frame");

    /* Register classes and methods */
    for (ClassInfo* cls = compiler->classes; cls != NULL; cls = cls->next) {
        if (cls->parent_name) {
            emit_line(compiler, "sage_register_class(\"%s\", \"%s\");", cls->class_name, cls->parent_name);
        } else {
            emit_line(compiler, "sage_register_class(\"%s\", NULL);", cls->class_name);
        }
        for (Stmt* method = cls->methods; method != NULL; method = method->next) {
            if (method->type == STMT_PROC) {
                char* mname = token_to_string(method->as.proc.name);
                emit_line(compiler, "sage_register_method(\"%s\", \"%s\", sage_method_%s_%s);",
                         cls->class_name, mname, cls->class_name, mname);
                free(mname);
            }
        }
    }

    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type != STMT_PROC && stmt->type != STMT_CLASS) {
            emit_stmt(compiler, stmt);
            if (compiler->failed) {
                compiler->indent--;
                emit_line(compiler, "return 1;");
                emit_line(compiler, "}");
                return;
            }
        }
    }

    emit_line(compiler, "sage_gc_pop_frame(&sage_gc_main_frame);");
    emit_line(compiler, "sage_gc_shutdown();");
    emit_line(compiler, "return 0;");
    compiler->indent--;
    emit_line(compiler, "}");
}

Stmt* parse_program(const char* source, const char* input_path) {
    init_lexer(source, input_path);
    parser_init();

    Stmt* head = NULL;
    Stmt* tail = NULL;

    while (1) {
        Stmt* stmt = parse();
        if (stmt == NULL) {
            break;
        }

        if (head == NULL) {
            head = stmt;
        } else {
            tail->next = stmt;
        }
        tail = stmt;
    }

    return head;
}

static int path_exists(const char* path) {
    return access(path, F_OK) == 0;
}

static int ensure_directory(const char* path) {
    char buffer[PATH_MAX];
    size_t len = strlen(path);
    if (len == 0 || len >= sizeof(buffer)) {
        fprintf(stderr, "Compiler error: invalid output directory path.\n");
        return 0;
    }

    memcpy(buffer, path, len + 1);
    if (len > 1 && buffer[len - 1] == '/') {
        buffer[len - 1] = '\0';
    }

    for (char* cursor = buffer + 1; *cursor != '\0'; cursor++) {
        if (*cursor == '/') {
            *cursor = '\0';
            if (mkdir(buffer, 0777) != 0 && errno != EEXIST) {
                fprintf(stderr, "Compiler error: could not create directory \"%s\": %s\n",
                        buffer, strerror(errno));
                return 0;
            }
            *cursor = '/';
        }
    }

    if (mkdir(buffer, 0777) != 0 && errno != EEXIST) {
        fprintf(stderr, "Compiler error: could not create directory \"%s\": %s\n",
                buffer, strerror(errno));
        return 0;
    }

    return 1;
}

static char* path_join(const char* left, const char* right) {
    size_t left_len = strlen(left);
    size_t right_len = strlen(right);
    int needs_sep = left_len > 0 && left[left_len - 1] != '/';
    char* joined = malloc(left_len + right_len + (needs_sep ? 2 : 1));
    if (joined == NULL) {
        fprintf(stderr, "Out of memory joining compiler paths.\n");
        exit(1);
    }

    memcpy(joined, left, left_len);
    if (needs_sep) {
        joined[left_len++] = '/';
    }
    memcpy(joined + left_len, right, right_len + 1);
    return joined;
}

static char* derive_program_name(const char* input_path) {
    const char* basename = strrchr(input_path, '/');
    basename = basename == NULL ? input_path : basename + 1;

    size_t len = strlen(basename);
    const char* last_dot = strrchr(basename, '.');
    if (last_dot != NULL) {
        len = (size_t)(last_dot - basename);
    }

    char* raw_name = malloc(len + 1);
    if (raw_name == NULL) {
        fprintf(stderr, "Out of memory deriving Pico program name.\n");
        exit(1);
    }
    memcpy(raw_name, basename, len);
    raw_name[len] = '\0';

    char* sanitized = sanitize_identifier(raw_name);
    free(raw_name);
    if (sanitized[0] == '\0') {
        free(sanitized);
        return str_dup("sage_program");
    }
    return sanitized;
}

static char* escape_cmake_string(const char* text) {
    StringBuffer sb;
    sb_init(&sb);

    for (size_t i = 0; text[i] != '\0'; i++) {
        if (text[i] == '\\' || text[i] == '"' || text[i] == ';') {
            sb_append_char(&sb, '\\');
        }
        sb_append_char(&sb, text[i]);
    }

    return sb_take(&sb);
}

static char* find_repo_root(void) {
    char cwd[PATH_MAX];
    if (getcwd(cwd, sizeof(cwd)) == NULL) {
        return NULL;
    }

    char current[PATH_MAX];
    memcpy(current, cwd, sizeof(current));

    while (1) {
        char* candidate = path_join(current, "pico_sdk_import.cmake");
        int found = path_exists(candidate);
        free(candidate);
        if (found) {
            return str_dup(current);
        }

        char* slash = strrchr(current, '/');
        if (slash == NULL) {
            break;
        }
        if (slash == current) {
            current[1] = '\0';
        } else {
            *slash = '\0';
        }

        candidate = path_join(current, "pico_sdk_import.cmake");
        found = path_exists(candidate);
        free(candidate);
        if (found) {
            return str_dup(current);
        }

        if (strcmp(current, "/") == 0) {
            break;
        }
    }

    return NULL;
}

static int write_pico_cmake_lists(const char* cmake_path, const char* import_path,
                                  const char* source_path, const char* program_name,
                                  const char* pico_board) {
    FILE* out = fopen(cmake_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "Compiler error: could not open \"%s\": %s\n",
                cmake_path, strerror(errno));
        return 0;
    }

    char* escaped_import = escape_cmake_string(import_path);
    char* escaped_source = escape_cmake_string(source_path);
    char* escaped_program = escape_cmake_string(program_name);
    char* escaped_board = escape_cmake_string(pico_board);

    fprintf(out,
            "cmake_minimum_required(VERSION 3.13)\n"
            "set(PICO_BOARD \"%s\" CACHE STRING \"RP2040 board\")\n"
            "include(\"%s\")\n"
            "project(%s LANGUAGES C CXX ASM)\n"
            "set(CMAKE_C_STANDARD 11)\n"
            "set(CMAKE_CXX_STANDARD 17)\n"
            "pico_sdk_init()\n"
            "add_executable(%s \"%s\")\n"
            "target_link_libraries(%s pico_stdlib)\n"
            "pico_enable_stdio_usb(%s 1)\n"
            "pico_enable_stdio_uart(%s 0)\n"
            "pico_add_extra_outputs(%s)\n",
            escaped_board, escaped_import, escaped_program, escaped_program,
            escaped_source, escaped_program, escaped_program, escaped_program,
            escaped_program);

    free(escaped_import);
    free(escaped_source);
    free(escaped_program);
    free(escaped_board);

    fclose(out);
    return 1;
}

static int run_command_with_sdk(char* const argv[], const char* pico_sdk_path) {
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Compiler error: could not fork %s.\n", argv[0]);
        return 0;
    }

    if (pid == 0) {
        if (pico_sdk_path != NULL && pico_sdk_path[0] != '\0') {
            setenv("PICO_SDK_PATH", pico_sdk_path, 1);
        }
        execvp(argv[0], argv);
        fprintf(stderr, "Compiler error: could not execute %s: %s\n", argv[0], strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Compiler error: could not wait for %s.\n", argv[0]);
        return 0;
    }

    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int write_c_output_internal(const char* source, const char* input_path, const char* output_path,
                                   CompilerTarget target, int opt_level, int debug_info) {
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "Could not open compiler output \"%s\": %s\n", output_path, strerror(errno));
        return 0;
    }

    Compiler compiler;
    memset(&compiler, 0, sizeof(compiler));
    compiler.out = out;
    compiler.input_path = input_path;
    compiler.next_unique_id = 1;

    Stmt* program = parse_program(source, input_path);

    // Run optimization passes if requested
    if (opt_level > 0) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        program = run_passes(program, &pass_ctx);
    }

    collect_top_level_symbols(&compiler, program);

    if (!compiler.failed) {
        emit_runtime_prelude(out, target);
        compiler.indent = 0;
        emit_proc_prototypes(&compiler);
        emit_method_prototypes(&compiler);
        if (compiler.procs != NULL || compiler.classes != NULL) {
            fputc('\n', out);
        }
        emit_global_slots(&compiler);
        if (compiler.globals != NULL) {
            fputc('\n', out);
        }
        emit_function_definitions(&compiler, program);
        if (!compiler.failed) {
            emit_main_function(&compiler, program, target);
        }
    }

    fclose(out);
    free_stmt(program);
    free_name_entries(compiler.globals);
    free_proc_entries(compiler.procs);
    free_class_info(compiler.classes);
    free_imported_modules(compiler.modules);
    return compiler.failed ? 0 : 1;
}

int compile_source_to_c(const char* source, const char* input_path, const char* output_path) {
    return write_c_output_internal(source, input_path, output_path, COMPILER_TARGET_HOST, 0, 0);
}

int compile_source_to_c_opt(const char* source, const char* input_path, const char* output_path,
                            int opt_level, int debug_info) {
    return write_c_output_internal(source, input_path, output_path, COMPILER_TARGET_HOST, opt_level, debug_info);
}

int compile_source_to_executable(const char* source, const char* input_path,
                                 const char* c_output_path, const char* exe_output_path,
                                 const char* cc_command) {
    if (!write_c_output_internal(source, input_path, c_output_path, COMPILER_TARGET_HOST, 0, 0)) {
        return 0;
    }

    const char* cc = (cc_command != NULL && cc_command[0] != '\0') ? cc_command : "cc";
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Could not fork compiler process.\n");
        return 0;
    }

    if (pid == 0) {
        execlp(cc, cc, "-std=c11", c_output_path, "-o", exe_output_path, (char*)NULL);
        fprintf(stderr, "Could not execute C compiler \"%s\": %s\n", cc, strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Could not wait for C compiler \"%s\".\n", cc);
        return 0;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "C compiler \"%s\" failed while building \"%s\".\n", cc, exe_output_path);
        return 0;
    }

    return 1;
}

int compile_source_to_executable_opt(const char* source, const char* input_path,
                                     const char* c_output_path, const char* exe_output_path,
                                     const char* cc_command, int opt_level, int debug_info) {
    if (!write_c_output_internal(source, input_path, c_output_path, COMPILER_TARGET_HOST, opt_level, debug_info)) {
        return 0;
    }

    const char* cc = (cc_command != NULL && cc_command[0] != '\0') ? cc_command : "cc";
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Could not fork compiler process.\n");
        return 0;
    }

    if (pid == 0) {
        if (debug_info) {
            execlp(cc, cc, "-std=c11", "-g", c_output_path, "-o", exe_output_path, (char*)NULL);
        } else {
            execlp(cc, cc, "-std=c11", c_output_path, "-o", exe_output_path, (char*)NULL);
        }
        fprintf(stderr, "Could not execute C compiler \"%s\": %s\n", cc, strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Could not wait for C compiler \"%s\".\n", cc);
        return 0;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "C compiler \"%s\" failed while building \"%s\".\n", cc, exe_output_path);
        return 0;
    }

    return 1;
}

int compile_source_to_pico_c(const char* source, const char* input_path, const char* output_path) {
    return write_c_output_internal(source, input_path, output_path, COMPILER_TARGET_PICO, 0, 0);
}

int compile_source_to_pico_uf2(const char* source, const char* input_path,
                               const char* output_dir, const char* program_name,
                               const char* pico_board, const char* pico_sdk_path,
                               char* uf2_path_out, size_t uf2_path_out_size) {
    const char* sdk_path = pico_sdk_path;
    if (sdk_path == NULL || sdk_path[0] == '\0') {
        sdk_path = getenv("PICO_SDK_PATH");
    }
    if (sdk_path == NULL || sdk_path[0] == '\0') {
        fprintf(stderr, "Compiler error: PICO_SDK_PATH is not set. Use --sdk or set the environment variable.\n");
        return 0;
    }

    const char* board = (pico_board != NULL && pico_board[0] != '\0') ? pico_board : "pico";
    char* effective_program_name = (program_name != NULL && program_name[0] != '\0')
        ? sanitize_identifier(program_name)
        : derive_program_name(input_path);

    char* effective_output_dir = NULL;
    if (output_dir != NULL && output_dir[0] != '\0') {
        effective_output_dir = str_dup(output_dir);
    } else {
        effective_output_dir = path_join(".tmp", effective_program_name);
    }

    if (!ensure_directory(effective_output_dir)) {
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    char resolved_output_dir[PATH_MAX];
    if (realpath(effective_output_dir, resolved_output_dir) == NULL) {
        fprintf(stderr, "Compiler error: could not resolve output directory \"%s\": %s\n",
                effective_output_dir, strerror(errno));
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }
    free(effective_output_dir);
    effective_output_dir = str_dup(resolved_output_dir);

    char* repo_root = find_repo_root();
    if (repo_root == NULL) {
        fprintf(stderr, "Compiler error: could not locate repo root containing pico_sdk_import.cmake.\n");
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    char* import_path = path_join(repo_root, "pico_sdk_import.cmake");
    char* build_dir = path_join(effective_output_dir, "build");
    char* cmake_path = path_join(effective_output_dir, "CMakeLists.txt");

    char source_file_name[PATH_MAX];
    snprintf(source_file_name, sizeof(source_file_name), "%s.c", effective_program_name);
    char* source_path = path_join(effective_output_dir, source_file_name);

    if (!write_c_output_internal(source, input_path, source_path, COMPILER_TARGET_PICO, 0, 0)) {
        free(repo_root);
        free(import_path);
        free(build_dir);
        free(cmake_path);
        free(source_path);
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    if (!write_pico_cmake_lists(cmake_path, import_path, source_path, effective_program_name, board)) {
        free(repo_root);
        free(import_path);
        free(build_dir);
        free(cmake_path);
        free(source_path);
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    char* cmake_argv[] = { "cmake", "-S", effective_output_dir, "-B", build_dir, NULL };
    if (!run_command_with_sdk(cmake_argv, sdk_path)) {
        fprintf(stderr, "Compiler error: Pico CMake configure failed.\n");
        free(repo_root);
        free(import_path);
        free(build_dir);
        free(cmake_path);
        free(source_path);
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    char* build_argv[] = { "cmake", "--build", build_dir, NULL };
    if (!run_command_with_sdk(build_argv, sdk_path)) {
        fprintf(stderr, "Compiler error: Pico build failed.\n");
        free(repo_root);
        free(import_path);
        free(build_dir);
        free(cmake_path);
        free(source_path);
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    char uf2_name[PATH_MAX];
    snprintf(uf2_name, sizeof(uf2_name), "%s.uf2", effective_program_name);
    char* uf2_path = path_join(build_dir, uf2_name);
    if (!path_exists(uf2_path)) {
        fprintf(stderr, "Compiler error: expected UF2 was not produced at \"%s\".\n", uf2_path);
        free(uf2_path);
        free(repo_root);
        free(import_path);
        free(build_dir);
        free(cmake_path);
        free(source_path);
        free(effective_program_name);
        free(effective_output_dir);
        return 0;
    }

    if (uf2_path_out != NULL && uf2_path_out_size > 0) {
        snprintf(uf2_path_out, uf2_path_out_size, "%s", uf2_path);
    }

    free(uf2_path);
    free(repo_root);
    free(import_path);
    free(build_dir);
    free(cmake_path);
    free(source_path);
    free(effective_program_name);
    free(effective_output_dir);
    return 1;
}
