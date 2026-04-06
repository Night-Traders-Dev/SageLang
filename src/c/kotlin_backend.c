#define _DEFAULT_SOURCE
#include "kotlin_backend.h"

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

extern Stmt* parse_program(const char* source, const char* input_path);

// ============================================================================
// Kotlin Backend — Transpile Sage AST to Kotlin targeting Android / JVM
// ============================================================================

// --- Compiler state ---

typedef enum {
    KT_TYPE_DYNAMIC,    // SageVal — default dynamic type
    KT_TYPE_NUMBER,     // Double — specialized for numeric vars
    KT_TYPE_STRING,     // String — specialized for string vars
    KT_TYPE_BOOLEAN,    // Boolean — specialized for boolean vars
} KtSpecType;

typedef struct KtNameEntry {
    char* sage_name;
    char* kt_name;
    int is_mutable;           // 0 = val, 1 = var
    KtSpecType spec_type;     // type specialization for -O2+
    struct KtNameEntry* next;
} KtNameEntry;

typedef struct KtProcEntry {
    char* sage_name;
    char* kt_name;
    int param_count;
    int is_method;
    int is_async;
    struct KtProcEntry* next;
} KtProcEntry;

typedef struct KtClassInfo {
    char* class_name;
    char* parent_name;
    Stmt* methods;
    struct KtClassInfo* next;
} KtClassInfo;

typedef struct KtImportedModule {
    char* name;
    char* path;
    char* source;
    Stmt* ast;
    struct KtImportedModule* next;
} KtImportedModule;

typedef struct {
    char* data;
    size_t len;
    size_t cap;
} KtStringBuffer;

typedef struct {
    FILE* out;
    const char* input_path;
    int failed;
    int in_function_body;
    int indent;
    int next_unique_id;
    int in_class;
    char* current_class;
    int in_generator;         // 1 when emitting a proc that contains yield
    int in_method;            // 1 when emitting a class method body
    int opt_level;            // optimization level (0-3), -O2+ enables type specialization
    KtNameEntry* globals;
    KtProcEntry* procs;
    KtNameEntry* locals;
    KtClassInfo* classes;
    KtImportedModule* modules;
} KtCompiler;

// --- AST scanning helpers ---

// Check if a statement tree contains any yield statements
static int kt_body_has_yield(Stmt* stmt) {
    while (stmt != NULL) {
        if (stmt->type == STMT_YIELD) return 1;
        if (stmt->type == STMT_BLOCK) {
            if (kt_body_has_yield(stmt->as.block.statements)) return 1;
        } else if (stmt->type == STMT_IF) {
            if (stmt->as.if_stmt.then_branch && kt_body_has_yield(stmt->as.if_stmt.then_branch)) return 1;
            if (stmt->as.if_stmt.else_branch && kt_body_has_yield(stmt->as.if_stmt.else_branch)) return 1;
        } else if (stmt->type == STMT_WHILE) {
            if (stmt->as.while_stmt.body && kt_body_has_yield(stmt->as.while_stmt.body)) return 1;
        } else if (stmt->type == STMT_FOR) {
            if (stmt->as.for_stmt.body && kt_body_has_yield(stmt->as.for_stmt.body)) return 1;
        } else if (stmt->type == STMT_TRY) {
            if (stmt->as.try_stmt.try_block && kt_body_has_yield(stmt->as.try_stmt.try_block)) return 1;
        }
        stmt = stmt->next;
    }
    return 0;
}

// --- String buffer helpers ---

static void kt_sb_init(KtStringBuffer* sb) {
    sb->cap = 128;
    sb->len = 0;
    sb->data = malloc(sb->cap);
    if (sb->data == NULL) {
        fprintf(stderr, "Out of memory in Kotlin compiler string buffer.\n");
        exit(1);
    }
    sb->data[0] = '\0';
}

static void kt_sb_reserve(KtStringBuffer* sb, size_t extra) {
    size_t needed = sb->len + extra + 1;
    if (needed <= sb->cap) return;
    while (sb->cap < needed) sb->cap *= 2;
    char* next = realloc(sb->data, sb->cap);
    if (next == NULL) {
        fprintf(stderr, "Out of memory growing Kotlin compiler string buffer.\n");
        exit(1);
    }
    sb->data = next;
}

static void kt_sb_append(KtStringBuffer* sb, const char* text) {
    size_t len = strlen(text);
    kt_sb_reserve(sb, len);
    memcpy(sb->data + sb->len, text, len + 1);
    sb->len += len;
}

static void kt_sb_append_char(KtStringBuffer* sb, char ch) {
    kt_sb_reserve(sb, 1);
    sb->data[sb->len++] = ch;
    sb->data[sb->len] = '\0';
}

static void kt_sb_appendf(KtStringBuffer* sb, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    va_list args_copy;
    va_copy(args_copy, args);
    int needed = vsnprintf(NULL, 0, fmt, args_copy);
    va_end(args_copy);
    if (needed < 0) {
        fprintf(stderr, "Kotlin compiler formatting error.\n");
        exit(1);
    }
    kt_sb_reserve(sb, (size_t)needed);
    vsnprintf(sb->data + sb->len, sb->cap - sb->len, fmt, args);
    sb->len += (size_t)needed;
    va_end(args);
}

static char* kt_sb_take(KtStringBuffer* sb) {
    char* result = sb->data;
    sb->data = NULL;
    sb->len = 0;
    sb->cap = 0;
    return result;
}

static char* kt_str_dup(const char* text) {
    size_t len = strlen(text);
    char* copy = malloc(len + 1);
    if (copy == NULL) {
        fprintf(stderr, "Out of memory duplicating Kotlin compiler string.\n");
        exit(1);
    }
    memcpy(copy, text, len + 1);
    return copy;
}

static char* kt_token_to_string(Token token) {
    char* text = malloc((size_t)token.length + 1);
    if (text == NULL) {
        fprintf(stderr, "Out of memory duplicating token.\n");
        exit(1);
    }
    memcpy(text, token.start, (size_t)token.length);
    text[token.length] = '\0';
    return text;
}

// Sanitize Sage identifier to valid Kotlin identifier
static char* kt_sanitize_identifier(const char* text) {
    size_t len = strlen(text);
    KtStringBuffer sb;
    kt_sb_init(&sb);

    // Kotlin reserved words that need backtick escaping
    static const char* kotlin_reserved[] = {
        "as", "break", "class", "continue", "do", "else", "false", "for",
        "fun", "if", "in", "interface", "is", "null", "object", "package",
        "return", "super", "this", "throw", "true", "try", "typealias",
        "typeof", "val", "var", "when", "while", "by", "catch", "constructor",
        "delegate", "dynamic", "field", "file", "finally", "get", "import",
        "init", "param", "property", "receiver", "set", "setparam", "where",
        "actual", "abstract", "annotation", "companion", "const", "crossinline",
        "data", "enum", "expect", "external", "final", "infix", "inline",
        "inner", "internal", "lateinit", "noinline", "open", "operator", "out",
        "override", "private", "protected", "public", "reified", "sealed",
        "suspend", "tailrec", "vararg", NULL
    };

    int is_reserved = 0;
    for (const char** kw = kotlin_reserved; *kw != NULL; kw++) {
        if (strcmp(text, *kw) == 0) {
            is_reserved = 1;
            break;
        }
    }

    if (is_reserved) {
        kt_sb_append_char(&sb, '`');
    }

    if (len == 0 || isdigit((unsigned char)text[0])) {
        kt_sb_append_char(&sb, '_');
    }

    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)text[i];
        if (isalnum(ch) || ch == '_') {
            kt_sb_append_char(&sb, (char)ch);
        } else {
            kt_sb_append_char(&sb, '_');
        }
    }

    if (is_reserved) {
        kt_sb_append_char(&sb, '`');
    }

    return kt_sb_take(&sb);
}

static char* kt_escape_string(const char* text) {
    KtStringBuffer sb;
    kt_sb_init(&sb);
    for (size_t i = 0; text[i] != '\0'; i++) {
        switch (text[i]) {
            case '\\': kt_sb_append(&sb, "\\\\"); break;
            case '"':  kt_sb_append(&sb, "\\\""); break;
            case '\n': kt_sb_append(&sb, "\\n"); break;
            case '\r': kt_sb_append(&sb, "\\r"); break;
            case '\t': kt_sb_append(&sb, "\\t"); break;
            case '$':  kt_sb_append(&sb, "\\$"); break;
            default:   kt_sb_append_char(&sb, text[i]); break;
        }
    }
    return kt_sb_take(&sb);
}

// --- Memory management ---

static void kt_free_name_entries(KtNameEntry* entry) {
    while (entry != NULL) {
        KtNameEntry* next = entry->next;
        free(entry->sage_name);
        free(entry->kt_name);
        free(entry);
        entry = next;
    }
}

static void kt_free_proc_entries(KtProcEntry* entry) {
    while (entry != NULL) {
        KtProcEntry* next = entry->next;
        free(entry->sage_name);
        free(entry->kt_name);
        free(entry);
        entry = next;
    }
}

static void kt_free_class_info(KtClassInfo* info) {
    while (info != NULL) {
        KtClassInfo* next = info->next;
        free(info->class_name);
        free(info->parent_name);
        free(info);
        info = next;
    }
}

static void kt_free_imported_modules(KtImportedModule* mod) {
    while (mod != NULL) {
        KtImportedModule* next = mod->next;
        free(mod->name);
        free(mod->path);
        free(mod->source);
        if (mod->ast) free_stmt(mod->ast);
        free(mod);
        mod = next;
    }
}

// --- Lookups ---

static KtNameEntry* kt_find_name(KtNameEntry* list, const char* sage_name) {
    while (list != NULL) {
        if (strcmp(list->sage_name, sage_name) == 0) return list;
        list = list->next;
    }
    return NULL;
}

static KtProcEntry* kt_find_proc(KtProcEntry* list, const char* sage_name) {
    while (list != NULL) {
        if (strcmp(list->sage_name, sage_name) == 0) return list;
        list = list->next;
    }
    return NULL;
}

static KtClassInfo* kt_find_class(KtClassInfo* list, const char* name) {
    while (list != NULL) {
        if (strcmp(list->class_name, name) == 0) return list;
        list = list->next;
    }
    return NULL;
}

static const char* kt_resolve_name(KtCompiler* compiler, const char* sage_name) {
    KtNameEntry* local = kt_find_name(compiler->locals, sage_name);
    if (local != NULL) return local->kt_name;
    KtNameEntry* global = kt_find_name(compiler->globals, sage_name);
    if (global != NULL) return global->kt_name;
    return NULL;
}

// --- Registration ---

static void kt_add_name(KtCompiler* compiler, KtNameEntry** list,
                         const char* sage_name, const char* prefix, int is_mutable) {
    char* sanitized = kt_sanitize_identifier(sage_name);
    KtNameEntry* entry = malloc(sizeof(KtNameEntry));
    entry->sage_name = kt_str_dup(sage_name);

    // Check for collisions and make unique
    if (kt_find_name(*list, sage_name) != NULL) {
        KtStringBuffer sb;
        kt_sb_init(&sb);
        kt_sb_appendf(&sb, "%s_%s_%d", prefix, sanitized, compiler->next_unique_id++);
        entry->kt_name = kt_sb_take(&sb);
    } else {
        entry->kt_name = sanitized;
        sanitized = NULL;
    }

    entry->is_mutable = is_mutable;
    entry->next = *list;
    *list = entry;
    free(sanitized);
}

static void kt_add_proc(KtCompiler* compiler, const char* sage_name,
                         int param_count, int is_method, int is_async) {
    char* sanitized = kt_sanitize_identifier(sage_name);
    KtProcEntry* entry = malloc(sizeof(KtProcEntry));
    entry->sage_name = kt_str_dup(sage_name);
    entry->kt_name = sanitized;
    entry->param_count = param_count;
    entry->is_method = is_method;
    entry->is_async = is_async;
    entry->next = compiler->procs;
    compiler->procs = entry;
}

static void kt_add_class(KtCompiler* compiler, const char* class_name,
                          const char* parent_name, Stmt* methods) {
    KtClassInfo* info = malloc(sizeof(KtClassInfo));
    info->class_name = kt_str_dup(class_name);
    info->parent_name = parent_name ? kt_str_dup(parent_name) : NULL;
    info->methods = methods;
    info->next = compiler->classes;
    compiler->classes = info;
}

static char* kt_make_unique_name(KtCompiler* compiler, const char* prefix) {
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_appendf(&sb, "%s_%d", prefix, compiler->next_unique_id++);
    return kt_sb_take(&sb);
}

// --- Error reporting ---

static int kt_token_span(const Token* token) {
    return (token != NULL && token->length > 0) ? token->length : 1;
}

static void kt_verror(KtCompiler* compiler, const Token* token,
                       const char* help, const char* fmt, va_list args) {
    if (token != NULL) {
        sage_vprint_token_diagnosticf("error", token, compiler->input_path,
                                      kt_token_span(token), help, fmt, args);
    } else {
        fprintf(stderr, "error");
        if (compiler->input_path != NULL)
            fprintf(stderr, " in %s", compiler->input_path);
        fprintf(stderr, ": ");
        vfprintf(stderr, fmt, args);
        fprintf(stderr, "\n");
        if (help != NULL && help[0] != '\0')
            fprintf(stderr, "  = help: %s\n", help);
    }
    compiler->failed = 1;
}

static void kt_error_at(KtCompiler* compiler, const Token* token,
                         const char* help, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    kt_verror(compiler, token, help, fmt, args);
    va_end(args);
}

static void kt_error(KtCompiler* compiler, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    kt_verror(compiler, NULL, NULL, fmt, args);
    va_end(args);
}

// --- Token to AST helpers ---

static const Token* kt_expr_token(const Expr* expr) {
    if (expr == NULL) return NULL;
    switch (expr->type) {
        case EXPR_BINARY:   return &expr->as.binary.op;
        case EXPR_VARIABLE: return &expr->as.variable.name;
        case EXPR_CALL:     return kt_expr_token(expr->as.call.callee);
        case EXPR_INDEX:    return kt_expr_token(expr->as.index.array);
        case EXPR_INDEX_SET:return kt_expr_token(expr->as.index_set.array);
        case EXPR_SLICE:    return kt_expr_token(expr->as.slice.array);
        case EXPR_GET:      return &expr->as.get.property;
        case EXPR_SET:      return &expr->as.set.property;
        case EXPR_AWAIT:    return kt_expr_token(expr->as.await.expression);
        case EXPR_COMPTIME: return kt_expr_token(expr->as.comptime.expression);
        default: return NULL;
    }
}

// Forward declaration for type specialization
static char* kt_emit_expr(KtCompiler* compiler, Expr* expr);

// --- Type specialization helpers ---

// Infer a concrete type from an expression (for -O2+ type specialization)
static KtSpecType kt_infer_expr_type(Expr* expr) {
    if (expr == NULL) return KT_TYPE_DYNAMIC;
    switch (expr->type) {
        case EXPR_NUMBER: return KT_TYPE_NUMBER;
        case EXPR_STRING: return KT_TYPE_STRING;
        case EXPR_BOOL: return KT_TYPE_BOOLEAN;
        case EXPR_BINARY: {
            // Arithmetic on numbers stays number
            switch (expr->as.binary.op.type) {
                case TOKEN_PLUS: case TOKEN_MINUS: case TOKEN_STAR:
                case TOKEN_SLASH: case TOKEN_PERCENT:
                    if (kt_infer_expr_type(expr->as.binary.left) == KT_TYPE_NUMBER &&
                        kt_infer_expr_type(expr->as.binary.right) == KT_TYPE_NUMBER)
                        return KT_TYPE_NUMBER;
                    break;
                case TOKEN_EQ: case TOKEN_NEQ: case TOKEN_GT: case TOKEN_LT:
                case TOKEN_GTE: case TOKEN_LTE: case TOKEN_AND: case TOKEN_OR:
                case TOKEN_NOT:
                    return KT_TYPE_BOOLEAN;
                default: break;
            }
            return KT_TYPE_DYNAMIC;
        }
        default: return KT_TYPE_DYNAMIC;
    }
}

// Emit a specialized expression (native Kotlin type, no SageVal wrapping)
static char* kt_emit_spec_number(KtCompiler* compiler, Expr* expr);
static char* kt_emit_spec_number(KtCompiler* compiler, Expr* expr) {
    if (expr == NULL) return kt_str_dup("0.0");
    switch (expr->type) {
        case EXPR_NUMBER: {
            KtStringBuffer sb; kt_sb_init(&sb);
            double val = expr->as.number.value;
            if (val == (long long)val && val >= -1e15 && val <= 1e15)
                kt_sb_appendf(&sb, "%lld.0", (long long)val);
            else
                kt_sb_appendf(&sb, "%.17g", val);
            return kt_sb_take(&sb);
        }
        case EXPR_BINARY: {
            char* left = kt_emit_spec_number(compiler, expr->as.binary.left);
            char* right = kt_emit_spec_number(compiler, expr->as.binary.right);
            const char* op = NULL;
            switch (expr->as.binary.op.type) {
                case TOKEN_PLUS: op = "+"; break;
                case TOKEN_MINUS: op = "-"; break;
                case TOKEN_STAR: op = "*"; break;
                case TOKEN_SLASH: op = "/"; break;
                case TOKEN_PERCENT: op = "%"; break;
                default: break;
            }
            if (op) {
                KtStringBuffer sb; kt_sb_init(&sb);
                kt_sb_appendf(&sb, "(%s %s %s)", left, op, right);
                free(left); free(right);
                return kt_sb_take(&sb);
            }
            free(left); free(right);
            return kt_str_dup("0.0");
        }
        case EXPR_VARIABLE: {
            char* name = kt_token_to_string(expr->as.variable.name);
            const char* kt_name = kt_resolve_name(compiler, name);
            // Check if this variable is also specialized as number
            KtNameEntry* local = kt_find_name(compiler->locals, name);
            if (!local) local = kt_find_name(compiler->globals, name);
            free(name);
            if (local && local->spec_type == KT_TYPE_NUMBER && kt_name)
                return kt_str_dup(kt_name);
            // Fall back to S.toDouble()
            char* general = kt_emit_expr(compiler, expr);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.toDouble(%s)", general);
            free(general);
            return kt_sb_take(&sb);
        }
        default: {
            char* general = kt_emit_expr(compiler, expr);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.toDouble(%s)", general);
            free(general);
            return kt_sb_take(&sb);
        }
    }
}

// --- Output helpers ---

static void kt_emit_indent(KtCompiler* compiler) {
    for (int i = 0; i < compiler->indent; i++)
        fputs("    ", compiler->out);
}

static void kt_emit_line(KtCompiler* compiler, const char* fmt, ...) {
    kt_emit_indent(compiler);
    va_list args;
    va_start(args, fmt);
    vfprintf(compiler->out, fmt, args);
    va_end(args);
    fputc('\n', compiler->out);
}

static void kt_emit_raw(KtCompiler* compiler, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(compiler->out, fmt, args);
    va_end(args);
}

// ============================================================================
// Expression Emission — returns Kotlin expression strings
// ============================================================================

static char* kt_emit_expr(KtCompiler* compiler, Expr* expr);

static char* kt_emit_array_expr(KtCompiler* compiler, ArrayExpr* array) {
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_append(&sb, "S.array(");
    for (int i = 0; i < array->count; i++) {
        if (i > 0) kt_sb_append(&sb, ", ");
        char* elem = kt_emit_expr(compiler, array->elements[i]);
        kt_sb_append(&sb, elem);
        free(elem);
    }
    kt_sb_append(&sb, ")");
    return kt_sb_take(&sb);
}

static char* kt_emit_index_expr(KtCompiler* compiler, IndexExpr* index) {
    char* arr = kt_emit_expr(compiler, index->array);
    char* idx = kt_emit_expr(compiler, index->index);
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_appendf(&sb, "S.index(%s, %s)", arr, idx);
    free(arr);
    free(idx);
    return kt_sb_take(&sb);
}

static char* kt_emit_slice_expr(KtCompiler* compiler, SliceExpr* slice) {
    char* arr = kt_emit_expr(compiler, slice->array);
    char* start = slice->start ? kt_emit_expr(compiler, slice->start) : kt_str_dup("S.nil");
    char* end = slice->end ? kt_emit_expr(compiler, slice->end) : kt_str_dup("S.nil");
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_appendf(&sb, "S.slice(%s, %s, %s)", arr, start, end);
    free(arr);
    free(start);
    free(end);
    return kt_sb_take(&sb);
}

static char* kt_emit_dict_expr(KtCompiler* compiler, DictExpr* dict) {
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_append(&sb, "S.dict(");
    for (int i = 0; i < dict->count; i++) {
        if (i > 0) kt_sb_append(&sb, ", ");
        char* escaped = kt_escape_string(dict->keys[i]);
        char* val = kt_emit_expr(compiler, dict->values[i]);
        kt_sb_appendf(&sb, "\"%s\" to %s", escaped, val);
        free(escaped);
        free(val);
    }
    kt_sb_append(&sb, ")");
    return kt_sb_take(&sb);
}

static char* kt_emit_tuple_expr(KtCompiler* compiler, TupleExpr* tuple) {
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_append(&sb, "S.tuple(");
    for (int i = 0; i < tuple->count; i++) {
        if (i > 0) kt_sb_append(&sb, ", ");
        char* elem = kt_emit_expr(compiler, tuple->elements[i]);
        kt_sb_append(&sb, elem);
        free(elem);
    }
    kt_sb_append(&sb, ")");
    return kt_sb_take(&sb);
}

static char* kt_emit_binary_expr(KtCompiler* compiler, BinaryExpr* binary) {
    // Assignment: x = expr → x = expr (Kotlin assignment)
    if (binary->op.type == TOKEN_ASSIGN) {
        if (binary->left->type == EXPR_VARIABLE) {
            char* name = kt_token_to_string(binary->left->as.variable.name);
            const char* kt_name = kt_resolve_name(compiler, name);
            char* rhs = kt_emit_expr(compiler, binary->right);
            KtStringBuffer sb; kt_sb_init(&sb);
            if (kt_name != NULL) {
                kt_sb_appendf(&sb, "%s = %s", kt_name, rhs);
            } else {
                char* sanitized = kt_sanitize_identifier(name);
                kt_sb_appendf(&sb, "%s = %s", sanitized, rhs);
                free(sanitized);
            }
            free(name); free(rhs);
            return kt_sb_take(&sb);
        } else if (binary->left->type == EXPR_GET) {
            char* obj = kt_emit_expr(compiler, binary->left->as.get.object);
            char* prop = kt_token_to_string(binary->left->as.get.property);
            char* rhs = kt_emit_expr(compiler, binary->right);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.setProperty(%s, \"%s\", %s)", obj, prop, rhs);
            free(obj); free(prop); free(rhs);
            return kt_sb_take(&sb);
        } else if (binary->left->type == EXPR_INDEX) {
            char* arr = kt_emit_expr(compiler, binary->left->as.index.array);
            char* idx = kt_emit_expr(compiler, binary->left->as.index.index);
            char* rhs = kt_emit_expr(compiler, binary->right);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.indexSet(%s, %s, %s)", arr, idx, rhs);
            free(arr); free(idx); free(rhs);
            return kt_sb_take(&sb);
        }
    }

    char* left = kt_emit_expr(compiler, binary->left);
    if (compiler->failed) { free(left); return kt_str_dup("S.nil"); }

    // Unary not / bitwise not
    if (binary->op.type == TOKEN_NOT) {
        KtStringBuffer sb; kt_sb_init(&sb);
        kt_sb_appendf(&sb, "S.not(%s)", left);
        free(left);
        return kt_sb_take(&sb);
    }
    if (binary->op.type == TOKEN_TILDE) {
        KtStringBuffer sb; kt_sb_init(&sb);
        kt_sb_appendf(&sb, "S.bitNot(%s)", left);
        free(left);
        return kt_sb_take(&sb);
    }

    char* right = kt_emit_expr(compiler, binary->right);
    if (compiler->failed) { free(left); free(right); return kt_str_dup("S.nil"); }

    const char* helper = NULL;
    switch (binary->op.type) {
        case TOKEN_PLUS:   helper = "S.add"; break;
        case TOKEN_MINUS:  helper = "S.sub"; break;
        case TOKEN_STAR:   helper = "S.mul"; break;
        case TOKEN_SLASH:  helper = "S.div"; break;
        case TOKEN_PERCENT:helper = "S.mod"; break;
        case TOKEN_EQ:     helper = "S.eq"; break;
        case TOKEN_NEQ:    helper = "S.neq"; break;
        case TOKEN_GT:     helper = "S.gt"; break;
        case TOKEN_LT:     helper = "S.lt"; break;
        case TOKEN_GTE:    helper = "S.gte"; break;
        case TOKEN_LTE:    helper = "S.lte"; break;
        case TOKEN_AMP:    helper = "S.bitAnd"; break;
        case TOKEN_PIPE:   helper = "S.bitOr"; break;
        case TOKEN_CARET:  helper = "S.bitXor"; break;
        case TOKEN_LSHIFT: helper = "S.shl"; break;
        case TOKEN_RSHIFT: helper = "S.shr"; break;
        case TOKEN_AND:    helper = "S.and"; break;
        case TOKEN_OR:     helper = "S.or"; break;
        default: break;
    }

    if (helper == NULL) {
        kt_error_at(compiler, &binary->op, NULL,
                     "binary operator '%.*s' is not supported by the Kotlin backend",
                     binary->op.length, binary->op.start);
        free(left); free(right);
        return kt_str_dup("S.nil");
    }

    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_appendf(&sb, "%s(%s, %s)", helper, left, right);
    free(left);
    free(right);
    return kt_sb_take(&sb);
}

// --- Built-in function call emission ---

static char* kt_emit_call_expr(KtCompiler* compiler, CallExpr* call) {
    // Super method call: super.method(args) → super.method(args) in Kotlin
    if (call->callee->type == EXPR_SUPER) {
        char* method = kt_token_to_string(call->callee->as.super_expr.method);
        KtStringBuffer sb;
        kt_sb_init(&sb);
        // init → sageInit (our constructor convention)
        if (strcmp(method, "init") == 0 || strcmp(method, "__init__") == 0) {
            kt_sb_append(&sb, "super.sageInit(");
        } else {
            kt_sb_appendf(&sb, "super.%s(", method);
        }
        for (int i = 0; i < call->arg_count; i++) {
            if (i > 0) kt_sb_append(&sb, ", ");
            char* arg = kt_emit_expr(compiler, call->args[i]);
            kt_sb_append(&sb, arg);
            free(arg);
        }
        kt_sb_append(&sb, ")");
        free(method);
        return kt_sb_take(&sb);
    }

    // Method call: obj.method(args)
    if (call->callee->type == EXPR_GET) {
        char* obj = kt_emit_expr(compiler, call->callee->as.get.object);
        char* method = kt_token_to_string(call->callee->as.get.property);
        KtStringBuffer sb;
        kt_sb_init(&sb);

        kt_sb_appendf(&sb, "S.callMethod(%s, \"%s\"", obj, method);
        for (int i = 0; i < call->arg_count; i++) {
            kt_sb_append(&sb, ", ");
            char* arg = kt_emit_expr(compiler, call->args[i]);
            kt_sb_append(&sb, arg);
            free(arg);
        }
        kt_sb_append(&sb, ")");
        free(obj);
        free(method);
        return kt_sb_take(&sb);
    }

    if (call->callee->type != EXPR_VARIABLE) {
        kt_error_at(compiler, kt_expr_token(call->callee), NULL,
                     "only direct function/constructor calls are supported by the Kotlin backend");
        return kt_str_dup("S.nil");
    }

    char* callee_name = kt_token_to_string(call->callee->as.variable.name);
    KtStringBuffer sb;
    kt_sb_init(&sb);

    // Map Sage built-in functions to Kotlin runtime helpers
    // ---- Type conversion ----
    if (strcmp(callee_name, "str") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.str(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "tonumber") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.toNumber(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "type") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.typeOf(%s)", a); free(a);
    }
    // ---- Collections ----
    else if (strcmp(callee_name, "len") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.len(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "push") == 0 && call->arg_count == 2) {
        char* arr = kt_emit_expr(compiler, call->args[0]);
        char* val = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.push(%s, %s)", arr, val);
        free(arr); free(val);
    }
    else if (strcmp(callee_name, "pop") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.pop(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "range") == 0 && call->arg_count >= 1 && call->arg_count <= 2) {
        if (call->arg_count == 1) {
            char* a = kt_emit_expr(compiler, call->args[0]);
            kt_sb_appendf(&sb, "S.range(%s)", a); free(a);
        } else {
            char* a = kt_emit_expr(compiler, call->args[0]);
            char* b = kt_emit_expr(compiler, call->args[1]);
            kt_sb_appendf(&sb, "S.range(%s, %s)", a, b);
            free(a); free(b);
        }
    }
    // ---- Dict operations ----
    else if (strcmp(callee_name, "dict_keys") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.dictKeys(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "dict_values") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.dictValues(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "dict_has") == 0 && call->arg_count == 2) {
        char* d = kt_emit_expr(compiler, call->args[0]);
        char* k = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.dictHas(%s, %s)", d, k);
        free(d); free(k);
    }
    else if (strcmp(callee_name, "dict_delete") == 0 && call->arg_count == 2) {
        char* d = kt_emit_expr(compiler, call->args[0]);
        char* k = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.dictDelete(%s, %s)", d, k);
        free(d); free(k);
    }
    else if (strcmp(callee_name, "dict_set") == 0 && call->arg_count == 3) {
        char* d = kt_emit_expr(compiler, call->args[0]);
        char* k = kt_emit_expr(compiler, call->args[1]);
        char* v = kt_emit_expr(compiler, call->args[2]);
        kt_sb_appendf(&sb, "S.dictSet(%s, %s, %s)", d, k, v);
        free(d); free(k); free(v);
    }
    else if (strcmp(callee_name, "dict_get") == 0 && call->arg_count == 2) {
        char* d = kt_emit_expr(compiler, call->args[0]);
        char* k = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.dictGet(%s, %s)", d, k);
        free(d); free(k);
    }
    // ---- GC (no-op on JVM, but available for API compat) ----
    else if (strcmp(callee_name, "gc_collect") == 0) {
        kt_sb_append(&sb, "S.gcCollect()");
    }
    else if (strcmp(callee_name, "gc_stats") == 0) {
        kt_sb_append(&sb, "S.gcStats()");
    }
    else if (strcmp(callee_name, "gc_enable") == 0) {
        kt_sb_append(&sb, "S.nil /* gc_enable: JVM manages GC */");
    }
    else if (strcmp(callee_name, "gc_disable") == 0) {
        kt_sb_append(&sb, "S.nil /* gc_disable: JVM manages GC */");
    }
    // ---- FFI (JNI bridge) ----
    else if (strcmp(callee_name, "ffi_open") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.ffiOpen(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "ffi_call") == 0 && call->arg_count >= 3) {
        char* lib = kt_emit_expr(compiler, call->args[0]);
        char* func = kt_emit_expr(compiler, call->args[1]);
        char* ret_type = kt_emit_expr(compiler, call->args[2]);
        kt_sb_appendf(&sb, "S.ffiCall(%s, %s, %s", lib, func, ret_type);
        if (call->arg_count > 3) {
            kt_sb_append(&sb, ", ");
            char* args_arr = kt_emit_expr(compiler, call->args[3]);
            kt_sb_append(&sb, args_arr);
            free(args_arr);
        }
        kt_sb_append(&sb, ")");
        free(lib); free(func); free(ret_type);
    }
    else if (strcmp(callee_name, "ffi_close") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.ffiClose(%s)", a); free(a);
    }
    // ---- Memory operations (ByteBuffer) ----
    else if (strcmp(callee_name, "mem_alloc") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.memAlloc(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "mem_free") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.memFree(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "mem_read") == 0 && call->arg_count == 3) {
        char* ptr = kt_emit_expr(compiler, call->args[0]);
        char* off = kt_emit_expr(compiler, call->args[1]);
        char* typ = kt_emit_expr(compiler, call->args[2]);
        kt_sb_appendf(&sb, "S.memRead(%s, %s, %s)", ptr, off, typ);
        free(ptr); free(off); free(typ);
    }
    else if (strcmp(callee_name, "mem_write") == 0 && call->arg_count == 4) {
        char* ptr = kt_emit_expr(compiler, call->args[0]);
        char* off = kt_emit_expr(compiler, call->args[1]);
        char* typ = kt_emit_expr(compiler, call->args[2]);
        char* val = kt_emit_expr(compiler, call->args[3]);
        kt_sb_appendf(&sb, "S.memWrite(%s, %s, %s, %s)", ptr, off, typ, val);
        free(ptr); free(off); free(typ); free(val);
    }
    // ---- Assembly (stub on JVM) ----
    else if (strcmp(callee_name, "asm_arch") == 0) {
        kt_sb_append(&sb, "S.str(\"jvm\")");
    }
    else if (strcmp(callee_name, "asm_exec") == 0 || strcmp(callee_name, "asm_compile") == 0) {
        kt_sb_append(&sb, "S.nil /* assembly not available on JVM */");
    }
    // ---- Thread operations ----
    else if (strcmp(callee_name, "cpu_count") == 0) {
        kt_sb_append(&sb, "S.num(Runtime.getRuntime().availableProcessors().toDouble())");
    }
    else if (strcmp(callee_name, "cpu_physical_cores") == 0) {
        kt_sb_append(&sb, "S.num(Runtime.getRuntime().availableProcessors().toDouble())");
    }
    else if (strcmp(callee_name, "cpu_has_hyperthreading") == 0) {
        kt_sb_append(&sb, "S.bool(false) /* JVM cannot detect HT */");
    }
    else if (strcmp(callee_name, "thread_get_core") == 0) {
        kt_sb_append(&sb, "S.num(-1.0) /* JVM does not expose core ID */");
    }
    // ---- Atomic operations (map to java.util.concurrent.atomic) ----
    else if (strcmp(callee_name, "atomic_new") == 0 && call->arg_count >= 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.atomicNew(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "atomic_load") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.atomicLoad(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "atomic_store") == 0 && call->arg_count == 2) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* v = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.atomicStore(%s, %s)", a, v); free(a); free(v);
    }
    else if (strcmp(callee_name, "atomic_add") == 0 && call->arg_count == 2) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* v = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.atomicAdd(%s, %s)", a, v); free(a); free(v);
    }
    else if (strcmp(callee_name, "atomic_cas") == 0 && call->arg_count == 3) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* e = kt_emit_expr(compiler, call->args[1]);
        char* d = kt_emit_expr(compiler, call->args[2]);
        kt_sb_appendf(&sb, "S.atomicCas(%s, %s, %s)", a, e, d); free(a); free(e); free(d);
    }
    // ---- Semaphore operations (map to java.util.concurrent.Semaphore) ----
    else if (strcmp(callee_name, "sem_new") == 0 && call->arg_count >= 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.semNew(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "sem_wait") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.semWait(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "sem_post") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.semPost(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "sem_trywait") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.semTryWait(%s)", a); free(a);
    }
    // ---- Path utilities ----
    else if (strcmp(callee_name, "path_join") == 0 && call->arg_count == 2) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* b = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.pathJoin(%s, %s)", a, b); free(a); free(b);
    }
    else if (strcmp(callee_name, "path_exists") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.pathExists(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "path_basename") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.pathBasename(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "path_dirname") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.pathDirname(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "path_ext") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.pathExt(%s)", a); free(a);
    }
    // ---- Hash/sizeof ----
    else if (strcmp(callee_name, "hash") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.hash(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "sizeof") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.sizeOf(%s)", a); free(a);
    }
    // ---- String operations (missing from original) ----
    else if (strcmp(callee_name, "upper") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.upper(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "lower") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.lower(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "strip") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.strip(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "split") == 0 && call->arg_count == 2) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* b = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.split(%s, %s)", a, b); free(a); free(b);
    }
    else if (strcmp(callee_name, "join") == 0 && call->arg_count == 2) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* b = kt_emit_expr(compiler, call->args[1]);
        kt_sb_appendf(&sb, "S.join(%s, %s)", a, b); free(a); free(b);
    }
    else if (strcmp(callee_name, "replace") == 0 && call->arg_count == 3) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        char* b = kt_emit_expr(compiler, call->args[1]);
        char* c = kt_emit_expr(compiler, call->args[2]);
        kt_sb_appendf(&sb, "S.replace(%s, %s, %s)", a, b, c); free(a); free(b); free(c);
    }
    else if (strcmp(callee_name, "chr") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.chr(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "ord") == 0 && call->arg_count == 1) {
        char* a = kt_emit_expr(compiler, call->args[0]);
        kt_sb_appendf(&sb, "S.ord(%s)", a); free(a);
    }
    else if (strcmp(callee_name, "clock") == 0) {
        kt_sb_append(&sb, "S.clock()");
    }
    // ---- I/O ----
    else if (strcmp(callee_name, "input") == 0) {
        if (call->arg_count == 1) {
            char* a = kt_emit_expr(compiler, call->args[0]);
            kt_sb_appendf(&sb, "S.input(%s)", a); free(a);
        } else {
            kt_sb_append(&sb, "S.input()");
        }
    }
    // ---- Class constructor ----
    else if (kt_find_class(compiler->classes, callee_name) != NULL) {
        kt_sb_appendf(&sb, "S.newInstance(\"%s\"", callee_name);
        for (int i = 0; i < call->arg_count; i++) {
            kt_sb_append(&sb, ", ");
            char* arg = kt_emit_expr(compiler, call->args[i]);
            kt_sb_append(&sb, arg);
            free(arg);
        }
        kt_sb_append(&sb, ")");
    }
    // ---- User-defined function call ----
    else {
        KtProcEntry* proc = kt_find_proc(compiler->procs, callee_name);
        const char* kt_name = proc ? proc->kt_name : callee_name;
        kt_sb_appendf(&sb, "%s(", kt_name);
        for (int i = 0; i < call->arg_count; i++) {
            if (i > 0) kt_sb_append(&sb, ", ");
            char* arg = kt_emit_expr(compiler, call->args[i]);
            kt_sb_append(&sb, arg);
            free(arg);
        }
        kt_sb_append(&sb, ")");
    }

    free(callee_name);
    return kt_sb_take(&sb);
}

static char* kt_emit_set_expr(KtCompiler* compiler, SetExpr* set) {
    // Simple variable reassignment: x = expr (object is NULL)
    if (set->object == NULL) {
        char* name = kt_token_to_string(set->property);
        const char* kt_name = kt_resolve_name(compiler, name);
        char* val = kt_emit_expr(compiler, set->value);
        KtStringBuffer sb;
        kt_sb_init(&sb);
        if (kt_name != NULL) {
            kt_sb_appendf(&sb, "%s = %s", kt_name, val);
        } else {
            char* sanitized = kt_sanitize_identifier(name);
            kt_sb_appendf(&sb, "%s = %s", sanitized, val);
            free(sanitized);
        }
        free(name); free(val);
        return kt_sb_take(&sb);
    }

    // Property assignment: obj.prop = value
    char* obj = kt_emit_expr(compiler, set->object);
    char* prop = kt_token_to_string(set->property);
    char* escaped = kt_escape_string(prop);
    char* val = kt_emit_expr(compiler, set->value);
    KtStringBuffer sb;
    kt_sb_init(&sb);
    kt_sb_appendf(&sb, "S.setProperty(%s, \"%s\", %s)", obj, escaped, val);
    free(obj); free(prop); free(escaped); free(val);
    return kt_sb_take(&sb);
}

// --- Main expression dispatch ---

static char* kt_emit_expr(KtCompiler* compiler, Expr* expr) {
    switch (expr->type) {
        case EXPR_NUMBER: {
            KtStringBuffer sb; kt_sb_init(&sb);
            double val = expr->as.number.value;
            if (val == (long long)val && val >= -1e15 && val <= 1e15) {
                kt_sb_appendf(&sb, "S.num(%lld.0)", (long long)val);
            } else {
                kt_sb_appendf(&sb, "S.num(%.17g)", val);
            }
            return kt_sb_take(&sb);
        }
        case EXPR_STRING: {
            char* escaped = kt_escape_string(expr->as.string.value);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.str(\"%s\")", escaped);
            free(escaped);
            return kt_sb_take(&sb);
        }
        case EXPR_BOOL:
            return kt_str_dup(expr->as.boolean.value ? "S.bool(true)" : "S.bool(false)");
        case EXPR_NIL:
            return kt_str_dup("S.nil");
        case EXPR_BINARY:
            return kt_emit_binary_expr(compiler, &expr->as.binary);
        case EXPR_VARIABLE: {
            char* name = kt_token_to_string(expr->as.variable.name);

            // Check for well-known Sage constants
            if (strcmp(name, "true") == 0) { free(name); return kt_str_dup("S.bool(true)"); }
            if (strcmp(name, "false") == 0) { free(name); return kt_str_dup("S.bool(false)"); }
            if (strcmp(name, "nil") == 0) { free(name); return kt_str_dup("S.nil"); }

            const char* kt_name = kt_resolve_name(compiler, name);
            if (kt_name == NULL) {
                // Could be a proc name used as a value reference
                KtProcEntry* proc = kt_find_proc(compiler->procs, name);
                if (proc != NULL) {
                    free(name);
                    return kt_str_dup(proc->kt_name);
                }
                // Unknown name — emit as-is (might be a global from imported module)
                char* sanitized = kt_sanitize_identifier(name);
                free(name);
                return sanitized;
            }

            // If variable is type-specialized, wrap it back to SageVal for dynamic contexts
            KtNameEntry* entry = kt_find_name(compiler->locals, name);
            if (!entry) entry = kt_find_name(compiler->globals, name);
            free(name);
            if (entry && entry->spec_type != KT_TYPE_DYNAMIC) {
                KtStringBuffer sb; kt_sb_init(&sb);
                switch (entry->spec_type) {
                    case KT_TYPE_NUMBER: kt_sb_appendf(&sb, "S.num(%s)", kt_name); break;
                    case KT_TYPE_STRING: kt_sb_appendf(&sb, "S.str(%s)", kt_name); break;
                    case KT_TYPE_BOOLEAN: kt_sb_appendf(&sb, "S.bool(%s)", kt_name); break;
                    default: kt_sb_append(&sb, kt_name); break;
                }
                return kt_sb_take(&sb);
            }
            return kt_str_dup(kt_name);
        }
        case EXPR_CALL:
            return kt_emit_call_expr(compiler, &expr->as.call);
        case EXPR_ARRAY:
            return kt_emit_array_expr(compiler, &expr->as.array);
        case EXPR_INDEX:
            return kt_emit_index_expr(compiler, &expr->as.index);
        case EXPR_INDEX_SET: {
            char* arr = kt_emit_expr(compiler, expr->as.index_set.array);
            char* idx = kt_emit_expr(compiler, expr->as.index_set.index);
            char* val = kt_emit_expr(compiler, expr->as.index_set.value);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.indexSet(%s, %s, %s)", arr, idx, val);
            free(arr); free(idx); free(val);
            return kt_sb_take(&sb);
        }
        case EXPR_SLICE:
            return kt_emit_slice_expr(compiler, &expr->as.slice);
        case EXPR_SET:
            return kt_emit_set_expr(compiler, &expr->as.set);
        case EXPR_AWAIT: {
            // Emit runBlocking { suspendExpr } to actually await the coroutine
            char* inner = kt_emit_expr(compiler, expr->as.await.expression);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "kotlinx.coroutines.runBlocking { %s }", inner);
            free(inner);
            return kt_sb_take(&sb);
        }
        case EXPR_SUPER: {
            // Standalone super reference (rare — usually handled by EXPR_CALL above)
            char* method = kt_token_to_string(expr->as.super_expr.method);
            KtStringBuffer sb; kt_sb_init(&sb);
            if (strcmp(method, "init") == 0 || strcmp(method, "__init__") == 0)
                kt_sb_append(&sb, "super.sageInit()");
            else
                kt_sb_appendf(&sb, "super.%s()", method);
            free(method);
            return kt_sb_take(&sb);
        }
        case EXPR_COMPTIME:
            return kt_emit_expr(compiler, expr->as.comptime.expression);
        case EXPR_DICT:
            return kt_emit_dict_expr(compiler, &expr->as.dict);
        case EXPR_TUPLE:
            return kt_emit_tuple_expr(compiler, &expr->as.tuple);
        case EXPR_GET: {
            char* object = kt_emit_expr(compiler, expr->as.get.object);
            char* prop = kt_token_to_string(expr->as.get.property);
            char* escaped = kt_escape_string(prop);
            KtStringBuffer sb; kt_sb_init(&sb);
            kt_sb_appendf(&sb, "S.getProperty(%s, \"%s\")", object, escaped);
            free(object); free(prop); free(escaped);
            return kt_sb_take(&sb);
        }
    }
    kt_error_at(compiler, kt_expr_token(expr), NULL,
                 "internal compiler error: unknown expression kind");
    return kt_str_dup("S.nil");
}

// ============================================================================
// Statement Emission
// ============================================================================

static void kt_emit_stmt_list(KtCompiler* compiler, Stmt* stmt);

static void kt_emit_embedded_block(KtCompiler* compiler, Stmt* stmt) {
    compiler->indent++;
    if (stmt != NULL && stmt->type == STMT_BLOCK)
        kt_emit_stmt_list(compiler, stmt->as.block.statements);
    else
        kt_emit_stmt_list(compiler, stmt);
    compiler->indent--;
}

static void kt_emit_stmt(KtCompiler* compiler, Stmt* stmt) {
    switch (stmt->type) {
        case STMT_PRINT: {
            char* expr = kt_emit_expr(compiler, stmt->as.print.expression);
            kt_emit_line(compiler, "S.printLn(%s)", expr);
            free(expr);
            break;
        }
        case STMT_EXPRESSION: {
            char* expr = kt_emit_expr(compiler, stmt->as.expression);
            kt_emit_line(compiler, "%s", expr);
            free(expr);
            break;
        }
        case STMT_LET: {
            char* name = kt_token_to_string(stmt->as.let.name);
            const char* kt_name = kt_resolve_name(compiler, name);
            if (kt_name == NULL) {
                kt_error_at(compiler, &stmt->as.let.name, NULL,
                            "internal error: let target '%s' was not collected", name);
                free(name);
                break;
            }

            // Type specialization at -O2+: emit native types for simple literals
            if (compiler->opt_level >= 2 && stmt->as.let.initializer) {
                KtSpecType spec = kt_infer_expr_type(stmt->as.let.initializer);
                // Tag the name entry with the inferred type
                KtNameEntry* entry = kt_find_name(compiler->locals, name);
                if (!entry) entry = kt_find_name(compiler->globals, name);
                if (entry) entry->spec_type = spec;

                if (spec == KT_TYPE_NUMBER) {
                    char* val = kt_emit_spec_number(compiler, stmt->as.let.initializer);
                    kt_emit_line(compiler, "var %s: Double = %s", kt_name, val);
                    free(name); free(val);
                    break;
                } else if (spec == KT_TYPE_STRING && stmt->as.let.initializer->type == EXPR_STRING) {
                    char* escaped = kt_escape_string(stmt->as.let.initializer->as.string.value);
                    kt_emit_line(compiler, "var %s: String = \"%s\"", kt_name, escaped);
                    free(escaped);
                    free(name);
                    break;
                } else if (spec == KT_TYPE_BOOLEAN) {
                    int bval = stmt->as.let.initializer->as.boolean.value;
                    kt_emit_line(compiler, "var %s: Boolean = %s", kt_name, bval ? "true" : "false");
                    free(name);
                    break;
                }
            }

            char* expr = stmt->as.let.initializer
                ? kt_emit_expr(compiler, stmt->as.let.initializer)
                : kt_str_dup("S.nil");
            kt_emit_line(compiler, "var %s = %s", kt_name, expr);
            free(name); free(expr);
            break;
        }
        case STMT_IF: {
            char* cond = kt_emit_expr(compiler, stmt->as.if_stmt.condition);
            kt_emit_line(compiler, "if (S.truthy(%s)) {", cond);
            free(cond);
            kt_emit_embedded_block(compiler, stmt->as.if_stmt.then_branch);
            if (stmt->as.if_stmt.else_branch != NULL) {
                kt_emit_line(compiler, "} else {");
                kt_emit_embedded_block(compiler, stmt->as.if_stmt.else_branch);
            }
            kt_emit_line(compiler, "}");
            break;
        }
        case STMT_BLOCK:
            kt_emit_stmt_list(compiler, stmt->as.block.statements);
            break;
        case STMT_WHILE: {
            char* cond = kt_emit_expr(compiler, stmt->as.while_stmt.condition);
            kt_emit_line(compiler, "while (S.truthy(%s)) {", cond);
            free(cond);
            kt_emit_embedded_block(compiler, stmt->as.while_stmt.body);
            // Re-evaluate condition — Kotlin while doesn't re-evaluate complex expressions
            // So we use a break pattern
            kt_emit_line(compiler, "}");
            break;
        }
        case STMT_RETURN: {
            char* expr = stmt->as.ret.value
                ? kt_emit_expr(compiler, stmt->as.ret.value)
                : kt_str_dup("S.nil");
            kt_emit_line(compiler, "return %s", expr);
            free(expr);
            break;
        }
        case STMT_BREAK:
            kt_emit_line(compiler, "break");
            break;
        case STMT_CONTINUE:
            kt_emit_line(compiler, "continue");
            break;
        case STMT_PROC:
            break;  // Emitted as top-level functions
        case STMT_FOR: {
            char* iterable = kt_emit_expr(compiler, stmt->as.for_stmt.iterable);
            char* var_name = kt_token_to_string(stmt->as.for_stmt.variable);
            const char* kt_name = kt_resolve_name(compiler, var_name);
            if (kt_name == NULL) {
                kt_error_at(compiler, &stmt->as.for_stmt.variable, NULL,
                            "internal error: for-loop variable '%s' was not collected", var_name);
                free(var_name); free(iterable);
                break;
            }
            char* iter_var = kt_make_unique_name(compiler, "_iter");
            kt_emit_line(compiler, "run {");
            compiler->indent++;
            kt_emit_line(compiler, "val %s = S.toIterable(%s)", iter_var, iterable);
            kt_emit_line(compiler, "for (%s in %s) {", kt_name, iter_var);
            kt_emit_embedded_block(compiler, stmt->as.for_stmt.body);
            kt_emit_line(compiler, "}");
            compiler->indent--;
            kt_emit_line(compiler, "}");
            free(var_name); free(iterable); free(iter_var);
            break;
        }
        case STMT_TRY: {
            TryStmt* try_stmt = &stmt->as.try_stmt;
            kt_emit_line(compiler, "try {");
            kt_emit_embedded_block(compiler, try_stmt->try_block);
            if (try_stmt->catch_count > 0) {
                char* catch_var = kt_token_to_string(try_stmt->catches[0]->exception_var);
                const char* kt_catch = kt_resolve_name(compiler, catch_var);
                if (kt_catch != NULL) {
                    kt_emit_line(compiler, "} catch (_e: SageException) {");
                    compiler->indent++;
                    kt_emit_line(compiler, "var %s = _e.value", kt_catch);
                    compiler->indent--;
                } else {
                    kt_emit_line(compiler, "} catch (_e: SageException) {");
                }
                kt_emit_embedded_block(compiler, try_stmt->catches[0]->body);
                free(catch_var);
            }
            if (try_stmt->finally_block != NULL) {
                kt_emit_line(compiler, "} finally {");
                kt_emit_embedded_block(compiler, try_stmt->finally_block);
            }
            kt_emit_line(compiler, "}");
            break;
        }
        case STMT_RAISE: {
            char* expr = stmt->as.raise.exception
                ? kt_emit_expr(compiler, stmt->as.raise.exception)
                : kt_str_dup("S.str(\"exception\")");
            kt_emit_line(compiler, "throw SageException(%s)", expr);
            free(expr);
            break;
        }
        case STMT_CLASS:
            break;  // Emitted as top-level classes
        case STMT_IMPORT: {
            ImportStmt* imp = &stmt->as.import;
            for (KtImportedModule* m = compiler->modules; m != NULL; m = m->next) {
                if (strcmp(m->name, imp->module_name) == 0) {
                    for (Stmt* s = m->ast; s != NULL; s = s->next) {
                        if (s->type != STMT_PROC && s->type != STMT_ASYNC_PROC && s->type != STMT_CLASS) {
                            kt_emit_stmt(compiler, s);
                            if (compiler->failed) return;
                        }
                    }
                    break;
                }
            }
            break;
        }
        case STMT_MATCH: {
            char* val = kt_emit_expr(compiler, stmt->as.match_stmt.value);
            char* tmp = kt_make_unique_name(compiler, "_match");
            kt_emit_line(compiler, "run {");
            compiler->indent++;
            kt_emit_line(compiler, "val %s = %s", tmp, val);
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                CaseClause* clause = stmt->as.match_stmt.cases[i];
                char* pat = kt_emit_expr(compiler, clause->pattern);
                if (clause->guard != NULL) {
                    char* guard = kt_emit_expr(compiler, clause->guard);
                    kt_emit_line(compiler, "%sif (S.equal(%s, %s) && S.truthy(%s)) {",
                                 i > 0 ? "} else " : "", tmp, pat, guard);
                    free(guard);
                } else {
                    kt_emit_line(compiler, "%sif (S.equal(%s, %s)) {",
                                 i > 0 ? "} else " : "", tmp, pat);
                }
                kt_emit_embedded_block(compiler, clause->body);
                free(pat);
            }
            if (stmt->as.match_stmt.default_case) {
                if (stmt->as.match_stmt.case_count > 0)
                    kt_emit_line(compiler, "} else {");
                else
                    kt_emit_line(compiler, "run {");
                kt_emit_embedded_block(compiler, stmt->as.match_stmt.default_case);
            }
            if (stmt->as.match_stmt.case_count > 0 || stmt->as.match_stmt.default_case)
                kt_emit_line(compiler, "}");
            compiler->indent--;
            kt_emit_line(compiler, "}");
            free(val); free(tmp);
            break;
        }
        case STMT_DEFER: {
            // Emit as try-finally for proper cleanup semantics
            kt_emit_line(compiler, "val _defer_%d = {", compiler->next_unique_id++);
            kt_emit_embedded_block(compiler, stmt->as.defer.statement);
            kt_emit_line(compiler, "}");
            break;
        }
        case STMT_YIELD: {
            // Emit Kotlin sequence yield()
            if (stmt->as.yield_stmt.value) {
                char* val = kt_emit_expr(compiler, stmt->as.yield_stmt.value);
                if (compiler->in_generator) {
                    kt_emit_line(compiler, "yield(%s)", val);
                } else {
                    kt_emit_line(compiler, "return %s", val);
                }
                free(val);
            } else {
                if (compiler->in_generator) {
                    kt_emit_line(compiler, "yield(S.nil)");
                } else {
                    kt_emit_line(compiler, "return S.nil");
                }
            }
            break;
        }
        case STMT_ASYNC_PROC:
            break;  // Emitted as top-level functions
        case STMT_COMPTIME:
            kt_emit_embedded_block(compiler, stmt->as.comptime.body);
            break;
        case STMT_MACRO_DEF:
            break;  // Treated as proc
        case STMT_STRUCT: {
            // Emit as data class
            char* name = kt_token_to_string(stmt->as.struct_stmt.name);
            kt_emit_indent(compiler);
            fprintf(compiler->out, "data class %s(", name);
            for (int i = 0; i < stmt->as.struct_stmt.field_count; i++) {
                if (i > 0) fputs(", ", compiler->out);
                char* fname = kt_token_to_string(stmt->as.struct_stmt.field_names[i]);
                fprintf(compiler->out, "var %s: SageVal = S.nil", fname);
                free(fname);
            }
            fputs(")\n", compiler->out);
            free(name);
            break;
        }
        case STMT_ENUM: {
            char* name = kt_token_to_string(stmt->as.enum_stmt.name);
            kt_emit_line(compiler, "enum class %s {", name);
            compiler->indent++;
            for (int i = 0; i < stmt->as.enum_stmt.variant_count; i++) {
                char* vname = kt_token_to_string(stmt->as.enum_stmt.variant_names[i]);
                kt_emit_line(compiler, "%s%s", vname,
                             i < stmt->as.enum_stmt.variant_count - 1 ? "," : "");
                free(vname);
            }
            compiler->indent--;
            kt_emit_line(compiler, "}");
            free(name);
            break;
        }
        case STMT_TRAIT: {
            char* name = kt_token_to_string(stmt->as.trait_stmt.name);
            kt_emit_line(compiler, "interface %s {", name);
            compiler->indent++;
            for (Stmt* m = stmt->as.trait_stmt.methods; m != NULL; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = kt_token_to_string(m->as.proc.name);
                    kt_emit_indent(compiler);
                    fprintf(compiler->out, "fun %s(", mname);
                    // Skip self parameter
                    int start = 0;
                    if (m->as.proc.param_count > 0) {
                        char* first = kt_token_to_string(m->as.proc.params[0]);
                        if (strcmp(first, "self") == 0) start = 1;
                        free(first);
                    }
                    for (int i = start; i < m->as.proc.param_count; i++) {
                        if (i > start) fputs(", ", compiler->out);
                        char* pname = kt_token_to_string(m->as.proc.params[i]);
                        fprintf(compiler->out, "%s: SageVal", pname);
                        free(pname);
                    }
                    fputs("): SageVal\n", compiler->out);
                    free(mname);
                }
            }
            compiler->indent--;
            kt_emit_line(compiler, "}");
            free(name);
            break;
        }
    }
}

static void kt_emit_stmt_list(KtCompiler* compiler, Stmt* stmt) {
    while (stmt != NULL) {
        kt_emit_stmt(compiler, stmt);
        if (compiler->failed) return;
        stmt = stmt->next;
    }
}

// ============================================================================
// Symbol Collection — First pass over AST
// ============================================================================

static void kt_collect_local_lets(KtCompiler* compiler, Stmt* stmt, KtNameEntry** locals) {
    while (stmt != NULL) {
        if (stmt->type == STMT_LET) {
            char* name = kt_token_to_string(stmt->as.let.name);
            if (kt_find_name(*locals, name) == NULL)
                kt_add_name(compiler, locals, name, "v", 1);
            free(name);
        } else if (stmt->type == STMT_FOR) {
            char* name = kt_token_to_string(stmt->as.for_stmt.variable);
            if (kt_find_name(*locals, name) == NULL)
                kt_add_name(compiler, locals, name, "v", 1);
            free(name);
            if (stmt->as.for_stmt.body) {
                Stmt* body = stmt->as.for_stmt.body;
                if (body->type == STMT_BLOCK)
                    kt_collect_local_lets(compiler, body->as.block.statements, locals);
                else
                    kt_collect_local_lets(compiler, body, locals);
            }
        } else if (stmt->type == STMT_IF) {
            if (stmt->as.if_stmt.then_branch) {
                Stmt* then_b = stmt->as.if_stmt.then_branch;
                if (then_b->type == STMT_BLOCK)
                    kt_collect_local_lets(compiler, then_b->as.block.statements, locals);
                else
                    kt_collect_local_lets(compiler, then_b, locals);
            }
            if (stmt->as.if_stmt.else_branch) {
                Stmt* else_b = stmt->as.if_stmt.else_branch;
                if (else_b->type == STMT_BLOCK)
                    kt_collect_local_lets(compiler, else_b->as.block.statements, locals);
                else
                    kt_collect_local_lets(compiler, else_b, locals);
            }
        } else if (stmt->type == STMT_WHILE) {
            if (stmt->as.while_stmt.body) {
                Stmt* body = stmt->as.while_stmt.body;
                if (body->type == STMT_BLOCK)
                    kt_collect_local_lets(compiler, body->as.block.statements, locals);
                else
                    kt_collect_local_lets(compiler, body, locals);
            }
        } else if (stmt->type == STMT_BLOCK) {
            kt_collect_local_lets(compiler, stmt->as.block.statements, locals);
        } else if (stmt->type == STMT_TRY) {
            if (stmt->as.try_stmt.try_block)
                kt_collect_local_lets(compiler, stmt->as.try_stmt.try_block, locals);
            for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
                char* name = kt_token_to_string(stmt->as.try_stmt.catches[i]->exception_var);
                if (kt_find_name(*locals, name) == NULL)
                    kt_add_name(compiler, locals, name, "v", 1);
                free(name);
                if (stmt->as.try_stmt.catches[i]->body)
                    kt_collect_local_lets(compiler, stmt->as.try_stmt.catches[i]->body, locals);
            }
            if (stmt->as.try_stmt.finally_block)
                kt_collect_local_lets(compiler, stmt->as.try_stmt.finally_block, locals);
        }
        stmt = stmt->next;
    }
}

static void kt_collect_global_lets(KtCompiler* compiler, Stmt* stmt) {
    if (stmt == NULL) return;
    if (stmt->type == STMT_LET) {
        char* name = kt_token_to_string(stmt->as.let.name);
        if (kt_find_name(compiler->globals, name) == NULL)
            kt_add_name(compiler, &compiler->globals, name, "g", 1);
        free(name);
    } else if (stmt->type == STMT_FOR) {
        char* name = kt_token_to_string(stmt->as.for_stmt.variable);
        if (kt_find_name(compiler->globals, name) == NULL)
            kt_add_name(compiler, &compiler->globals, name, "g", 1);
        free(name);
        if (stmt->as.for_stmt.body) {
            Stmt* body = stmt->as.for_stmt.body;
            if (body->type == STMT_BLOCK) {
                for (Stmt* s = body->as.block.statements; s != NULL; s = s->next)
                    kt_collect_global_lets(compiler, s);
            } else {
                kt_collect_global_lets(compiler, body);
            }
        }
    } else if (stmt->type == STMT_IF) {
        if (stmt->as.if_stmt.then_branch) kt_collect_global_lets(compiler, stmt->as.if_stmt.then_branch);
        if (stmt->as.if_stmt.else_branch) kt_collect_global_lets(compiler, stmt->as.if_stmt.else_branch);
    } else if (stmt->type == STMT_WHILE) {
        if (stmt->as.while_stmt.body) kt_collect_global_lets(compiler, stmt->as.while_stmt.body);
    } else if (stmt->type == STMT_BLOCK) {
        for (Stmt* s = stmt->as.block.statements; s != NULL; s = s->next)
            kt_collect_global_lets(compiler, s);
    } else if (stmt->type == STMT_TRY) {
        if (stmt->as.try_stmt.try_block) kt_collect_global_lets(compiler, stmt->as.try_stmt.try_block);
        for (int i = 0; i < stmt->as.try_stmt.catch_count; i++) {
            char* name = kt_token_to_string(stmt->as.try_stmt.catches[i]->exception_var);
            if (kt_find_name(compiler->globals, name) == NULL)
                kt_add_name(compiler, &compiler->globals, name, "g", 1);
            free(name);
        }
        if (stmt->as.try_stmt.finally_block) kt_collect_global_lets(compiler, stmt->as.try_stmt.finally_block);
    }
}

// Import resolution
static char* kt_find_module_path(const char* module_name, const char* input_path) {
    char search_paths[4][512];
    int path_count = 0;

    // Same directory as input file
    if (input_path != NULL) {
        const char* slash = strrchr(input_path, '/');
        if (slash != NULL) {
            size_t dir_len = (size_t)(slash - input_path);
            snprintf(search_paths[path_count], sizeof(search_paths[0]),
                     "%.*s/%s.sage", (int)dir_len, input_path, module_name);
        } else {
            snprintf(search_paths[path_count], sizeof(search_paths[0]),
                     "%s.sage", module_name);
        }
        path_count++;
    }

    // lib/ directory (relative to input)
    snprintf(search_paths[path_count], sizeof(search_paths[0]),
             "lib/%s.sage", module_name);
    path_count++;

    for (int i = 0; i < path_count; i++) {
        if (access(search_paths[i], R_OK) == 0)
            return kt_str_dup(search_paths[i]);
    }
    return NULL;
}

static void kt_process_import(KtCompiler* compiler, ImportStmt* imp) {
    // Check already loaded
    for (KtImportedModule* m = compiler->modules; m != NULL; m = m->next) {
        if (strcmp(m->name, imp->module_name) == 0) return;
    }

    char* path = kt_find_module_path(imp->module_name, compiler->input_path);
    if (path == NULL) {
        // Not a fatal error — might be a standard library module
        // that gets mapped to Kotlin stdlib imports
        return;
    }

    FILE* f = fopen(path, "rb");
    if (f == NULL) { free(path); return; }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* source = malloc((size_t)size + 1);
    if ((long)fread(source, 1, (size_t)size, f) != size) {
        free(source); free(path); fclose(f);
        return;
    }
    source[size] = '\0';
    fclose(f);

    Stmt* ast = parse_program(source, path);

    KtImportedModule* mod = malloc(sizeof(KtImportedModule));
    mod->name = kt_str_dup(imp->module_name);
    mod->path = path;
    mod->source = source;
    mod->ast = ast;
    mod->next = compiler->modules;
    compiler->modules = mod;

    // Collect symbols from imported module
    for (Stmt* s = ast; s != NULL; s = s->next) {
        if (s->type == STMT_PROC || s->type == STMT_ASYNC_PROC) {
            char* name = kt_token_to_string(s->as.proc.name);
            if (kt_find_proc(compiler->procs, name) == NULL)
                kt_add_proc(compiler, name, s->as.proc.param_count, 0, s->type == STMT_ASYNC_PROC);
            free(name);
        }
        if (s->type == STMT_CLASS) {
            char* cname = kt_token_to_string(s->as.class_stmt.name);
            char* pname = NULL;
            if (s->as.class_stmt.has_parent)
                pname = kt_token_to_string(s->as.class_stmt.parent);
            if (kt_find_class(compiler->classes, cname) == NULL)
                kt_add_class(compiler, cname, pname, s->as.class_stmt.methods);
            free(cname); free(pname);
        }
    }
}

static void kt_collect_top_level_symbols(KtCompiler* compiler, Stmt* program) {
    // First pass: procs, classes, imports
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_PROC || stmt->type == STMT_ASYNC_PROC) {
            char* name = kt_token_to_string(stmt->as.proc.name);
            kt_add_proc(compiler, name, stmt->as.proc.param_count, 0,
                         stmt->type == STMT_ASYNC_PROC);
            free(name);
        }
        if (stmt->type == STMT_CLASS) {
            char* cname = kt_token_to_string(stmt->as.class_stmt.name);
            char* pname = NULL;
            if (stmt->as.class_stmt.has_parent)
                pname = kt_token_to_string(stmt->as.class_stmt.parent);
            kt_add_class(compiler, cname, pname, stmt->as.class_stmt.methods);
            free(cname); free(pname);
        }
        if (stmt->type == STMT_IMPORT)
            kt_process_import(compiler, &stmt->as.import);
    }
    // Second pass: global lets
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type != STMT_PROC && stmt->type != STMT_ASYNC_PROC && stmt->type != STMT_CLASS)
            kt_collect_global_lets(compiler, stmt);
    }
}

// ============================================================================
// Top-Level Emission — Functions, Classes, Main
// ============================================================================

static void kt_emit_function_definition(KtCompiler* compiler, Stmt* stmt) {
    ProcStmt* proc_stmt = &stmt->as.proc;
    char* proc_name = kt_token_to_string(proc_stmt->name);
    KtProcEntry* proc = kt_find_proc(compiler->procs, proc_name);
    free(proc_name);
    if (proc == NULL) return;

    // Collect local variables
    KtNameEntry* previous_locals = compiler->locals;
    compiler->locals = NULL;

    // Add params as locals
    for (int i = 0; i < proc_stmt->param_count; i++) {
        char* pname = kt_token_to_string(proc_stmt->params[i]);
        kt_add_name(compiler, &compiler->locals, pname, "p", 0);
        free(pname);
    }
    kt_collect_local_lets(compiler, proc_stmt->body, &compiler->locals);

    // Detect generator (proc contains yield statements)
    int is_generator = 0;
    if (proc_stmt->body != NULL) {
        Stmt* scan_body = proc_stmt->body;
        if (scan_body->type == STMT_BLOCK)
            is_generator = kt_body_has_yield(scan_body->as.block.statements);
        else
            is_generator = kt_body_has_yield(scan_body);
    }

    // Emit function signature
    int is_suspend = (stmt->type == STMT_ASYNC_PROC);
    kt_emit_indent(compiler);
    if (is_suspend)
        fprintf(compiler->out, "suspend fun %s(", proc->kt_name);
    else
        fprintf(compiler->out, "fun %s(", proc->kt_name);

    for (int i = 0; i < proc_stmt->param_count; i++) {
        if (i > 0) fputs(", ", compiler->out);
        char* pname = kt_token_to_string(proc_stmt->params[i]);
        KtNameEntry* param = kt_find_name(compiler->locals, pname);
        fprintf(compiler->out, "%s: SageVal", param ? param->kt_name : pname);
        free(pname);
    }

    if (is_generator) {
        // Generator: return Sequence<SageVal>, body wrapped in sequence { }
        fputs("): Sequence<SageVal> = sequence {\n", compiler->out);
    } else {
        fputs("): SageVal {\n", compiler->out);
    }
    compiler->indent++;

    compiler->in_function_body = 1;
    compiler->in_generator = is_generator;

    // Emit body
    if (proc_stmt->body != NULL) {
        if (proc_stmt->body->type == STMT_BLOCK)
            kt_emit_stmt_list(compiler, proc_stmt->body->as.block.statements);
        else
            kt_emit_stmt_list(compiler, proc_stmt->body);
    }

    compiler->in_function_body = 0;
    compiler->in_generator = 0;

    if (!is_generator) {
        kt_emit_line(compiler, "return S.nil");
    }
    compiler->indent--;
    kt_emit_line(compiler, "}");
    fputc('\n', compiler->out);

    kt_free_name_entries(compiler->locals);
    compiler->locals = previous_locals;
}

static void kt_emit_class_definition(KtCompiler* compiler, KtClassInfo* cls) {
    // Emit class
    if (cls->parent_name)
        kt_emit_line(compiler, "open class %s : %s() {", cls->class_name, cls->parent_name);
    else
        kt_emit_line(compiler, "open class %s : SageObject(\"%s\") {", cls->class_name, cls->class_name);

    compiler->indent++;
    compiler->in_class = 1;
    compiler->current_class = cls->class_name;

    // Emit a dynamic property map for instance properties (self.x = ...)
    kt_emit_line(compiler, "override val props = mutableMapOf<String, SageVal>()");
    kt_emit_line(compiler, "");

    // Emit methods
    for (Stmt* method = cls->methods; method != NULL; method = method->next) {
        if (method->type == STMT_PROC) {
            ProcStmt* proc = &method->as.proc;
            char* mname = kt_token_to_string(proc->name);

            // Determine if first param is self
            int start_param = 0;
            if (proc->param_count > 0) {
                char* first = kt_token_to_string(proc->params[0]);
                if (strcmp(first, "self") == 0) start_param = 1;
                free(first);
            }

            // Collect locals for this method
            KtNameEntry* prev = compiler->locals;
            compiler->locals = NULL;
            for (int i = start_param; i < proc->param_count; i++) {
                char* pname = kt_token_to_string(proc->params[i]);
                kt_add_name(compiler, &compiler->locals, pname, "p", 0);
                free(pname);
            }
            kt_collect_local_lets(compiler, proc->body, &compiler->locals);

            // init → constructor-like
            int is_init = (strcmp(mname, "init") == 0 || strcmp(mname, "__init__") == 0);

            if (is_init) {
                kt_emit_indent(compiler);
                fprintf(compiler->out, "fun sageInit(");
            } else {
                kt_emit_indent(compiler);
                fprintf(compiler->out, "open fun %s(", mname);
            }

            for (int i = start_param; i < proc->param_count; i++) {
                if (i > start_param) fputs(", ", compiler->out);
                char* pname = kt_token_to_string(proc->params[i]);
                KtNameEntry* param = kt_find_name(compiler->locals, pname);
                fprintf(compiler->out, "%s: SageVal", param ? param->kt_name : pname);
                free(pname);
            }

            if (is_init)
                fputs("): SageVal {\n", compiler->out);
            else
                fputs("): SageVal {\n", compiler->out);

            compiler->indent++;
            compiler->in_function_body = 1;

            if (proc->body != NULL) {
                if (proc->body->type == STMT_BLOCK)
                    kt_emit_stmt_list(compiler, proc->body->as.block.statements);
                else
                    kt_emit_stmt_list(compiler, proc->body);
            }

            compiler->in_function_body = 0;
            kt_emit_line(compiler, "return S.nil");
            compiler->indent--;
            kt_emit_line(compiler, "}");
            kt_emit_line(compiler, "");

            kt_free_name_entries(compiler->locals);
            compiler->locals = prev;
            free(mname);
        }
    }

    compiler->in_class = 0;
    compiler->current_class = NULL;
    compiler->indent--;
    kt_emit_line(compiler, "}");
    kt_emit_line(compiler, "");
}

static void kt_emit_function_definitions(KtCompiler* compiler, Stmt* program) {
    // Emit imported module functions first
    for (KtImportedModule* mod = compiler->modules; mod != NULL; mod = mod->next) {
        for (Stmt* s = mod->ast; s != NULL; s = s->next) {
            if (s->type == STMT_PROC || s->type == STMT_ASYNC_PROC) {
                kt_emit_function_definition(compiler, s);
                if (compiler->failed) return;
            }
        }
    }
    // Emit user functions
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_PROC || stmt->type == STMT_ASYNC_PROC) {
            kt_emit_function_definition(compiler, stmt);
            if (compiler->failed) return;
        }
    }
}

// ============================================================================
// Kotlin File Prelude
// ============================================================================

static void kt_emit_prelude(FILE* out) {
    fputs(
        "// Generated by Sage Kotlin Backend\n"
        "// https://github.com/sageLang/sage\n"
        "@file:Suppress(\"UNUSED_PARAMETER\", \"UNUSED_VARIABLE\", \"NAME_SHADOWING\")\n"
        "\n"
        "import sage.runtime.*\n"
        "import sage.runtime.SageRuntime as S\n"
        "import kotlinx.coroutines.*\n"
        "\n"
        "typealias SageVal = SageRuntime.Value\n"
        "\n",
        out
    );
}

// ============================================================================
// Main entry — emit main() function with top-level statements
// ============================================================================

static void kt_emit_main(KtCompiler* compiler, Stmt* program) {
    kt_emit_line(compiler, "fun main() {");
    compiler->indent++;
    kt_emit_line(compiler, "S.init()");
    kt_emit_line(compiler, "");

    // Register classes
    for (KtClassInfo* cls = compiler->classes; cls != NULL; cls = cls->next) {
        kt_emit_line(compiler, "S.registerClass(\"%s\") { args -> %s().also { it.sageInit(*args) } }",
                     cls->class_name, cls->class_name);
    }
    if (compiler->classes) kt_emit_line(compiler, "");

    // Emit top-level statements
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type != STMT_PROC && stmt->type != STMT_ASYNC_PROC && stmt->type != STMT_CLASS) {
            kt_emit_stmt(compiler, stmt);
            if (compiler->failed) {
                compiler->indent--;
                kt_emit_line(compiler, "}");
                return;
            }
        }
    }

    kt_emit_line(compiler, "");
    compiler->indent--;
    kt_emit_line(compiler, "}");
}

// ============================================================================
// Public API — write_kotlin_output_internal
// ============================================================================

static int write_kotlin_output_internal(const char* source, const char* input_path,
                                        const char* output_path, int opt_level, int debug_info) {
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "Could not open Kotlin output \"%s\": %s\n", output_path, strerror(errno));
        return 0;
    }

    KtCompiler compiler;
    memset(&compiler, 0, sizeof(compiler));
    compiler.out = out;
    compiler.input_path = input_path;
    compiler.next_unique_id = 1;
    compiler.opt_level = opt_level;

    Stmt* program = parse_program(source, input_path);

    // Run optimization passes
    if (opt_level > 0) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        program = run_passes(program, &pass_ctx);
    }

    kt_collect_top_level_symbols(&compiler, program);

    if (!compiler.failed) {
        kt_emit_prelude(out);

        // Emit classes
        for (KtClassInfo* cls = compiler.classes; cls != NULL; cls = cls->next) {
            kt_emit_class_definition(&compiler, cls);
            if (compiler.failed) break;
        }

        // Emit functions
        kt_emit_function_definitions(&compiler, program);

        // Emit main
        if (!compiler.failed)
            kt_emit_main(&compiler, program);
    }

    fclose(out);
    free_stmt(program);
    kt_free_name_entries(compiler.globals);
    kt_free_proc_entries(compiler.procs);
    kt_free_class_info(compiler.classes);
    kt_free_imported_modules(compiler.modules);
    return compiler.failed ? 0 : 1;
}

int compile_source_to_kotlin(const char* source, const char* input_path,
                             const char* output_path) {
    return write_kotlin_output_internal(source, input_path, output_path, 0, 0);
}

int compile_source_to_kotlin_opt(const char* source, const char* input_path,
                                 const char* output_path,
                                 int opt_level, int debug_info) {
    return write_kotlin_output_internal(source, input_path, output_path, opt_level, debug_info);
}

// ============================================================================
// Android Project Scaffolding Generator
// ============================================================================

static int kt_mkdir_p(const char* dir) {
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", dir);
    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755) == 0 || errno == EEXIST;
}

static int kt_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    fputs(content, f);
    fclose(f);
    return 1;
}

static int kt_write_file_fmt(const char* path, const char* fmt, ...) {
    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);
    fclose(f);
    return 1;
}

// Write the SageRuntime.kt file into the Android project
static int kt_write_sage_runtime(const char* runtime_dir) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/SageRuntime.kt", runtime_dir);
    FILE* f = fopen(path, "wb");
    if (!f) return 0;

    // Package and class definitions
    fputs("package sage.runtime\n\n", f);
    fputs("class SageException(val value: SageRuntime.Value) : Exception(SageRuntime.toKString(value))\n\n", f);
    fputs("open class SageObject(val className: String) {\n", f);
    fputs("    open val props = mutableMapOf<String, SageRuntime.Value>()\n", f);
    fputs("    fun sageInit(vararg args: SageRuntime.Value): SageRuntime.Value = SageRuntime.nil\n", f);
    fputs("}\n\nobject SageRuntime {\n\n", f);

    // Value type
    fputs("    sealed class Value {\n", f);
    fputs("        data class Num(val v: Double) : Value()\n", f);
    fputs("        data class Str(val v: String) : Value()\n", f);
    fputs("        data class Bool(val v: Boolean) : Value()\n", f);
    fputs("        object Nil : Value()\n", f);
    fputs("        data class Arr(val v: MutableList<Value>) : Value()\n", f);
    fputs("        data class Dict(val v: MutableMap<String, Value>) : Value()\n", f);
    fputs("        data class Tup(val v: List<Value>) : Value()\n", f);
    fputs("        data class Obj(val v: SageObject) : Value()\n", f);
    fputs("        data class Fn(val name: String, val f: (Array<out Value>) -> Value) : Value()\n", f);
    fputs("        data class Gen(val v: Sequence<Value>) : Value()\n", f);
    fputs("        data class Ptr(val buf: java.nio.ByteBuffer, val size: Int) : Value()\n", f);
    fputs("    }\n\n", f);

    // Constructors
    fputs("    val nil: Value = Value.Nil\n", f);
    fputs("    fun num(v: Double): Value = Value.Num(v)\n", f);
    fputs("    fun num(v: Int): Value = Value.Num(v.toDouble())\n", f);
    fputs("    fun str(v: String): Value = Value.Str(v)\n", f);
    fputs("    fun bool(v: Boolean): Value = Value.Bool(v)\n", f);
    fputs("    fun array(vararg elems: Value): Value = Value.Arr(elems.toMutableList())\n", f);
    fputs("    fun dict(vararg pairs: Pair<String, Value>): Value = Value.Dict(mutableMapOf(*pairs))\n", f);
    fputs("    fun tuple(vararg elems: Value): Value = Value.Tup(elems.toList())\n\n", f);

    // Class registry
    fputs("    private val classRegistry = mutableMapOf<String, (Array<out Value>) -> Value>()\n", f);
    fputs("    fun init() { }\n", f);
    fputs("    fun registerClass(name: String, ctor: (Array<out Value>) -> Value) { classRegistry[name] = ctor }\n", f);
    fputs("    fun newInstance(className: String, vararg args: Value): Value {\n", f);
    fputs("        val ctor = classRegistry[className] ?: throw RuntimeException(\"Unknown class: $className\")\n", f);
    fputs("        return ctor(args)\n    }\n\n", f);

    // Truthiness
    fputs("    fun truthy(v: Value): Boolean = when (v) {\n", f);
    fputs("        is Value.Nil -> false; is Value.Bool -> v.v; is Value.Num -> v.v != 0.0\n", f);
    fputs("        is Value.Str -> v.v.isNotEmpty(); is Value.Arr -> v.v.isNotEmpty()\n", f);
    fputs("        is Value.Dict -> v.v.isNotEmpty(); else -> true\n    }\n\n", f);

    // Arithmetic
    fputs("    fun add(a: Value, b: Value): Value = when {\n", f);
    fputs("        a is Value.Num && b is Value.Num -> num(a.v + b.v)\n", f);
    fputs("        a is Value.Str || b is Value.Str -> str(toKString(a) + toKString(b))\n", f);
    fputs("        a is Value.Arr && b is Value.Arr -> Value.Arr((a.v + b.v).toMutableList())\n", f);
    fputs("        else -> num(toDouble(a) + toDouble(b))\n    }\n", f);
    fputs("    fun sub(a: Value, b: Value): Value = num(toDouble(a) - toDouble(b))\n", f);
    fputs("    fun mul(a: Value, b: Value): Value = when {\n", f);
    fputs("        a is Value.Str && b is Value.Num -> str(a.v.repeat(b.v.toInt().coerceAtLeast(0)))\n", f);
    fputs("        a is Value.Num && b is Value.Str -> str(b.v.repeat(a.v.toInt().coerceAtLeast(0)))\n", f);
    fputs("        else -> num(toDouble(a) * toDouble(b))\n    }\n", f);
    fputs("    fun div(a: Value, b: Value): Value = num(toDouble(a) / toDouble(b))\n", f);
    fputs("    fun mod(a: Value, b: Value): Value = num(toDouble(a) % toDouble(b))\n\n", f);

    // Comparison
    fputs("    fun eq(a: Value, b: Value): Value = bool(equal(a, b))\n", f);
    fputs("    fun neq(a: Value, b: Value): Value = bool(!equal(a, b))\n", f);
    fputs("    fun gt(a: Value, b: Value): Value = bool(toDouble(a) > toDouble(b))\n", f);
    fputs("    fun lt(a: Value, b: Value): Value = bool(toDouble(a) < toDouble(b))\n", f);
    fputs("    fun gte(a: Value, b: Value): Value = bool(toDouble(a) >= toDouble(b))\n", f);
    fputs("    fun lte(a: Value, b: Value): Value = bool(toDouble(a) <= toDouble(b))\n", f);
    fputs("    fun equal(a: Value, b: Value): Boolean = when {\n", f);
    fputs("        a is Value.Nil && b is Value.Nil -> true\n", f);
    fputs("        a is Value.Num && b is Value.Num -> a.v == b.v\n", f);
    fputs("        a is Value.Str && b is Value.Str -> a.v == b.v\n", f);
    fputs("        a is Value.Bool && b is Value.Bool -> a.v == b.v\n", f);
    fputs("        else -> a == b\n    }\n\n", f);

    // Logical + Bitwise
    fputs("    fun not(v: Value): Value = bool(!truthy(v))\n", f);
    fputs("    fun and(a: Value, b: Value): Value = if (truthy(a)) b else a\n", f);
    fputs("    fun or(a: Value, b: Value): Value = if (truthy(a)) a else b\n", f);
    fputs("    fun bitAnd(a: Value, b: Value): Value = num((toDouble(a).toLong() and toDouble(b).toLong()).toDouble())\n", f);
    fputs("    fun bitOr(a: Value, b: Value): Value = num((toDouble(a).toLong() or toDouble(b).toLong()).toDouble())\n", f);
    fputs("    fun bitXor(a: Value, b: Value): Value = num((toDouble(a).toLong() xor toDouble(b).toLong()).toDouble())\n", f);
    fputs("    fun bitNot(v: Value): Value = num(toDouble(v).toLong().inv().toDouble())\n", f);
    fputs("    fun shl(a: Value, b: Value): Value = num((toDouble(a).toLong() shl toDouble(b).toInt()).toDouble())\n", f);
    fputs("    fun shr(a: Value, b: Value): Value = num((toDouble(a).toLong() shr toDouble(b).toInt()).toDouble())\n\n", f);

    // Collections
    fputs("    fun len(v: Value): Value = num(when (v) {\n", f);
    fputs("        is Value.Str -> v.v.length.toDouble(); is Value.Arr -> v.v.size.toDouble()\n", f);
    fputs("        is Value.Dict -> v.v.size.toDouble(); is Value.Tup -> v.v.size.toDouble()\n", f);
    fputs("        else -> 0.0\n    })\n", f);
    fputs("    fun index(collection: Value, idx: Value): Value = when (collection) {\n", f);
    fputs("        is Value.Arr -> { val i = toDouble(idx).toInt(); val e = if (i<0) collection.v.size+i else i; if (e in collection.v.indices) collection.v[e] else nil }\n", f);
    fputs("        is Value.Dict -> collection.v[toKString(idx)] ?: nil\n", f);
    fputs("        is Value.Str -> { val i = toDouble(idx).toInt(); val e = if (i<0) collection.v.length+i else i; if (e in collection.v.indices) str(collection.v[e].toString()) else nil }\n", f);
    fputs("        is Value.Tup -> { val i = toDouble(idx).toInt(); if (i in collection.v.indices) collection.v[i] else nil }\n", f);
    fputs("        else -> nil\n    }\n", f);
    fputs("    fun indexSet(c: Value, idx: Value, v: Value): Value { when(c) { is Value.Arr -> { val i=toDouble(idx).toInt(); val e=if(i<0)c.v.size+i else i; if(e in c.v.indices) c.v[e]=v }; is Value.Dict -> c.v[toKString(idx)]=v; else -> {} }; return v }\n", f);
    fputs("    fun slice(c: Value, s: Value, e: Value): Value {\n", f);
    fputs("        if(c is Value.Arr){val a=if(s is Value.Nil)0 else toDouble(s).toInt();val b=if(e is Value.Nil)c.v.size else toDouble(e).toInt();return Value.Arr(c.v.subList(a.coerceAtLeast(0),b.coerceAtMost(c.v.size)).toMutableList())}\n", f);
    fputs("        if(c is Value.Str){val a=if(s is Value.Nil)0 else toDouble(s).toInt();val b=if(e is Value.Nil)c.v.length else toDouble(e).toInt();return str(c.v.substring(a.coerceAtLeast(0),b.coerceAtMost(c.v.length)))}\n", f);
    fputs("        return nil\n    }\n", f);
    fputs("    fun push(arr: Value, value: Value): Value { if(arr is Value.Arr) arr.v.add(value); return nil }\n", f);
    fputs("    fun pop(arr: Value): Value { if(arr is Value.Arr && arr.v.isNotEmpty()) return arr.v.removeAt(arr.v.size-1); return nil }\n", f);
    fputs("    fun range(stop: Value): Value { val n=toDouble(stop).toInt(); return Value.Arr((0 until n).map{num(it.toDouble())}.toMutableList()) }\n", f);
    fputs("    fun range(start: Value, stop: Value): Value { val s=toDouble(start).toInt();val e=toDouble(stop).toInt(); return Value.Arr((s until e).map{num(it.toDouble())}.toMutableList()) }\n\n", f);

    // Dict operations
    fputs("    fun dictKeys(d: Value): Value = if(d is Value.Dict) Value.Arr(d.v.keys.map{str(it)}.toMutableList()) else nil\n", f);
    fputs("    fun dictValues(d: Value): Value = if(d is Value.Dict) Value.Arr(d.v.values.toMutableList()) else nil\n", f);
    fputs("    fun dictHas(d: Value, key: Value): Value = bool(d is Value.Dict && toKString(key) in d.v)\n", f);
    fputs("    fun dictDelete(d: Value, key: Value): Value { if(d is Value.Dict) d.v.remove(toKString(key)); return nil }\n", f);
    fputs("    fun dictSet(d: Value, key: Value, value: Value): Value { if(d is Value.Dict) d.v[toKString(key)]=value; return value }\n", f);
    fputs("    fun dictGet(d: Value, key: Value): Value = if(d is Value.Dict) d.v[toKString(key)] ?: nil else nil\n\n", f);

    // Type / Conversion
    fputs("    fun str(v: Value): Value = Value.Str(toKString(v))\n", f);
    fputs("    fun toNumber(v: Value): Value = num(toDouble(v))\n", f);
    fputs("    fun typeOf(v: Value): Value = str(when(v) {\n", f);
    fputs("        is Value.Num->\"number\";is Value.Str->\"string\";is Value.Bool->\"bool\";is Value.Nil->\"nil\"\n", f);
    fputs("        is Value.Arr->\"array\";is Value.Dict->\"dict\";is Value.Tup->\"tuple\"\n", f);
    fputs("        is Value.Obj->v.v.className;is Value.Fn->\"function\";is Value.Gen->\"generator\";is Value.Ptr->\"pointer\"\n    })\n", f);
    fputs("    fun toKString(v: Value): String = when(v) {\n", f);
    fputs("        is Value.Num -> { val d=v.v; if(d==d.toLong().toDouble()) d.toLong().toString() else d.toString() }\n", f);
    fputs("        is Value.Str -> v.v; is Value.Bool -> if(v.v) \"true\" else \"false\"; is Value.Nil -> \"nil\"\n", f);
    fputs("        is Value.Arr -> \"[\" + v.v.joinToString(\", \"){toKString(it)} + \"]\"\n", f);
    fputs("        is Value.Dict -> \"{\" + v.v.entries.joinToString(\", \"){\"\\\"${it.key}\\\": ${toKString(it.value)}\"} + \"}\"\n", f);
    fputs("        is Value.Tup -> \"(\" + v.v.joinToString(\", \"){toKString(it)} + \")\"\n", f);
    fputs("        is Value.Obj -> \"<${v.v.className} instance>\"; is Value.Fn -> \"<function ${v.name}>\"\n", f);
    fputs("        is Value.Gen -> \"<generator>\"; is Value.Ptr -> \"<pointer ${v.size}B>\"\n    }\n", f);
    fputs("    fun toDouble(v: Value): Double = when(v) { is Value.Num->v.v; is Value.Str->v.v.toDoubleOrNull()?:0.0; is Value.Bool->if(v.v)1.0 else 0.0; else->0.0 }\n\n", f);

    // Iteration (supports arrays, strings, dicts, tuples, and generators)
    fputs("    fun toIterable(v: Value): Iterable<Value> = when(v) { is Value.Arr->v.v; is Value.Str->v.v.map{str(it.toString())}; is Value.Dict->v.v.keys.map{str(it)}; is Value.Tup->v.v; is Value.Gen->v.v.asIterable(); else->emptyList() }\n\n", f);

    // Property access
    fputs("    fun getProperty(obj: Value, name: String): Value = when(obj) {\n", f);
    fputs("        is Value.Obj -> obj.v.props[name] ?: nil\n", f);
    fputs("        is Value.Dict -> obj.v[name] ?: nil\n", f);
    fputs("        is Value.Str -> when(name){\"length\"->num(obj.v.length.toDouble()); else->nil}\n", f);
    fputs("        is Value.Arr -> when(name){\"length\"->num(obj.v.size.toDouble()); else->nil}\n", f);
    fputs("        else -> nil\n    }\n", f);
    fputs("    fun setProperty(obj: Value, name: String, value: Value): Value { when(obj){is Value.Obj->obj.v.props[name]=value; is Value.Dict->obj.v[name]=value; else->{}}; return value }\n\n", f);

    // Method calls
    fputs("    fun callMethod(obj: Value, method: String, vararg args: Value): Value {\n", f);
    fputs("        if(obj is Value.Obj) { val m=obj.v::class.java.methods.firstOrNull{it.name==method}; if(m!=null) return try{m.invoke(obj.v,*args) as? Value ?: nil}catch(_:Exception){nil} }\n", f);
    fputs("        if(obj is Value.Str) return when(method) {\n", f);
    fputs("            \"upper\"->str(obj.v.uppercase()); \"lower\"->str(obj.v.lowercase()); \"strip\",\"trim\"->str(obj.v.trim())\n", f);
    fputs("            \"split\"->if(args.isNotEmpty()) Value.Arr(obj.v.split(toKString(args[0])).map{str(it)}.toMutableList()) else nil\n", f);
    fputs("            \"replace\"->if(args.size>=2) str(obj.v.replace(toKString(args[0]),toKString(args[1]))) else nil\n", f);
    fputs("            \"starts_with\",\"startsWith\"->if(args.isNotEmpty()) bool(obj.v.startsWith(toKString(args[0]))) else nil\n", f);
    fputs("            \"ends_with\",\"endsWith\"->if(args.isNotEmpty()) bool(obj.v.endsWith(toKString(args[0]))) else nil\n", f);
    fputs("            \"contains\"->if(args.isNotEmpty()) bool(obj.v.contains(toKString(args[0]))) else nil\n", f);
    fputs("            \"find\"->if(args.isNotEmpty()) num(obj.v.indexOf(toKString(args[0])).toDouble()) else nil\n", f);
    fputs("            \"join\"->if(args.isNotEmpty()&&args[0] is Value.Arr) str((args[0] as Value.Arr).v.joinToString(obj.v){toKString(it)}) else nil\n", f);
    fputs("            else->nil\n        }\n", f);
    fputs("        if(obj is Value.Arr) return when(method) {\n", f);
    fputs("            \"push\",\"append\"->{ if(args.isNotEmpty()) obj.v.add(args[0]); nil }\n", f);
    fputs("            \"pop\"->if(obj.v.isNotEmpty()) obj.v.removeAt(obj.v.size-1) else nil\n", f);
    fputs("            \"sort\"->{ obj.v.sortWith(compareBy{toDouble(it)}); nil }; \"reverse\"->{ obj.v.reverse(); nil }\n", f);
    fputs("            \"map\"->if(args.isNotEmpty()&&args[0] is Value.Fn) Value.Arr(obj.v.map{(args[0] as Value.Fn).f(arrayOf(it))}.toMutableList()) else nil\n", f);
    fputs("            \"filter\"->if(args.isNotEmpty()&&args[0] is Value.Fn) Value.Arr(obj.v.filter{truthy((args[0] as Value.Fn).f(arrayOf(it)))}.toMutableList()) else nil\n", f);
    fputs("            \"join\"->if(args.isNotEmpty()) str(obj.v.joinToString(toKString(args[0])){toKString(it)}) else str(obj.v.joinToString(\"\"){toKString(it)})\n", f);
    fputs("            else->nil\n        }\n        return nil\n    }\n", f);
    fputs("    fun superCall(obj: Value, method: String, vararg args: Value): Value = callMethod(obj, method, *args)\n\n", f);

    // Memory operations (ByteBuffer-backed)
    fputs("    fun memAlloc(size: Value): Value { val n=toDouble(size).toInt().coerceIn(1,67108864); return Value.Ptr(java.nio.ByteBuffer.allocateDirect(n).order(java.nio.ByteOrder.nativeOrder()), n) }\n", f);
    fputs("    fun memFree(ptr: Value): Value { if(ptr is Value.Ptr) { (ptr.buf as? sun.nio.ch.DirectBuffer)?.cleaner()?.clean() }; return nil }\n", f);
    fputs("    fun memRead(ptr: Value, offset: Value, type: Value): Value {\n", f);
    fputs("        if(ptr !is Value.Ptr) return nil; val o=toDouble(offset).toInt(); val t=toKString(type); val b=ptr.buf\n", f);
    fputs("        return when(t) { \"byte\"->num(b.get(o).toDouble()); \"int\"->num(b.getInt(o).toDouble()); \"double\"->num(b.getDouble(o))\n", f);
    fputs("            \"string\"->{ val sb=StringBuilder(); var i=o; while(i<ptr.size&&b.get(i)!=0.toByte()){sb.append(b.get(i).toInt().toChar());i++}; str(sb.toString()) }\n", f);
    fputs("            else->nil }\n    }\n", f);
    fputs("    fun memWrite(ptr: Value, offset: Value, type: Value, value: Value): Value {\n", f);
    fputs("        if(ptr !is Value.Ptr) return nil; val o=toDouble(offset).toInt(); val t=toKString(type); val b=ptr.buf\n", f);
    fputs("        when(t) { \"byte\"->b.put(o, toDouble(value).toInt().toByte()); \"int\"->b.putInt(o, toDouble(value).toInt()); \"double\"->b.putDouble(o, toDouble(value))\n", f);
    fputs("            \"string\"->{ val s=toKString(value); for(i in s.indices) b.put(o+i, s[i].code.toByte()); b.put(o+s.length, 0) } }; return nil\n    }\n\n", f);

    // FFI (JNI bridge — load native libraries and call functions via reflection)
    fputs("    private val ffiLibs = mutableMapOf<String, Any?>()\n", f);
    fputs("    fun ffiOpen(name: Value): Value { val n=toKString(name); try { System.loadLibrary(n.removeSuffix(\".so\").removePrefix(\"lib\")); ffiLibs[n]=true; return str(n) } catch(_:Exception){ return nil } }\n", f);
    fputs("    fun ffiCall(lib: Value, func: Value, retType: Value, args: Value = nil): Value {\n", f);
    fputs("        // JNI native calls require pre-declared external functions;\n", f);
    fputs("        // this stub logs the call for debugging. Real FFI needs JNI bindings.\n", f);
    fputs("        val fname = toKString(func); val rt = toKString(retType)\n", f);
    fputs("        println(\"[FFI] call $fname -> $rt\"); return nil\n    }\n", f);
    fputs("    fun ffiClose(lib: Value): Value { if(lib is Value.Str) ffiLibs.remove(lib.v); return nil }\n\n", f);

    // I/O + GC
    fputs("    fun printLn(v: Value) = println(toKString(v))\n", f);
    fputs("    fun input(): Value = str(readlnOrNull() ?: \"\")\n", f);
    fputs("    fun input(prompt: Value): Value { print(toKString(prompt)); return input() }\n", f);
    fputs("    fun gcCollect(): Value { System.gc(); return nil }\n", f);
    fputs("    fun gcStats(): Value = str(\"GC: JVM managed\")\n\n", f);

    // Atomic operations (java.util.concurrent.atomic)
    fputs("    fun atomicNew(v: Value): Value { val a = java.util.concurrent.atomic.AtomicLong(toDouble(v).toLong()); return Value.Obj(object : SageObject(\"atomic\") { val atom = a }) }\n", f);
    fputs("    fun atomicLoad(a: Value): Value { if(a is Value.Obj) { val f=a.v::class.java.getDeclaredField(\"atom\"); f.isAccessible=true; return num((f.get(a.v) as java.util.concurrent.atomic.AtomicLong).get().toDouble()) }; return nil }\n", f);
    fputs("    fun atomicStore(a: Value, v: Value): Value { if(a is Value.Obj) { val f=a.v::class.java.getDeclaredField(\"atom\"); f.isAccessible=true; (f.get(a.v) as java.util.concurrent.atomic.AtomicLong).set(toDouble(v).toLong()) }; return nil }\n", f);
    fputs("    fun atomicAdd(a: Value, v: Value): Value { if(a is Value.Obj) { val f=a.v::class.java.getDeclaredField(\"atom\"); f.isAccessible=true; return num((f.get(a.v) as java.util.concurrent.atomic.AtomicLong).addAndGet(toDouble(v).toLong()).toDouble()) }; return nil }\n", f);
    fputs("    fun atomicCas(a: Value, exp: Value, des: Value): Value { if(a is Value.Obj) { val f=a.v::class.java.getDeclaredField(\"atom\"); f.isAccessible=true; return bool((f.get(a.v) as java.util.concurrent.atomic.AtomicLong).compareAndSet(toDouble(exp).toLong(), toDouble(des).toLong())) }; return bool(false) }\n", f);

    // Semaphore operations (java.util.concurrent.Semaphore)
    fputs("    fun semNew(v: Value): Value { val s = java.util.concurrent.Semaphore(toDouble(v).toInt()); return Value.Obj(object : SageObject(\"semaphore\") { val sem = s }) }\n", f);
    fputs("    fun semWait(s: Value): Value { if(s is Value.Obj) { val f=s.v::class.java.getDeclaredField(\"sem\"); f.isAccessible=true; (f.get(s.v) as java.util.concurrent.Semaphore).acquire() }; return nil }\n", f);
    fputs("    fun semPost(s: Value): Value { if(s is Value.Obj) { val f=s.v::class.java.getDeclaredField(\"sem\"); f.isAccessible=true; (f.get(s.v) as java.util.concurrent.Semaphore).release() }; return nil }\n", f);
    fputs("    fun semTryWait(s: Value): Value { if(s is Value.Obj) { val f=s.v::class.java.getDeclaredField(\"sem\"); f.isAccessible=true; return bool((f.get(s.v) as java.util.concurrent.Semaphore).tryAcquire()) }; return bool(false) }\n\n", f);

    // String operations
    fputs("    fun upper(v: Value): Value = if(v is Value.Str) str(v.v.uppercase()) else nil\n", f);
    fputs("    fun lower(v: Value): Value = if(v is Value.Str) str(v.v.lowercase()) else nil\n", f);
    fputs("    fun strip(v: Value): Value = if(v is Value.Str) str(v.v.trim()) else nil\n", f);
    fputs("    fun split(v: Value, d: Value): Value = if(v is Value.Str) Value.Arr(v.v.split(toKString(d)).map{str(it)}.toMutableList()) else nil\n", f);
    fputs("    fun join(items: Value, sep: Value): Value = if(items is Value.Arr) str(items.v.joinToString(toKString(sep)){toKString(it)}) else nil\n", f);
    fputs("    fun replace(v: Value, old: Value, new_: Value): Value = if(v is Value.Str) str(v.v.replace(toKString(old), toKString(new_))) else nil\n", f);
    fputs("    fun chr(v: Value): Value = str(toDouble(v).toInt().toChar().toString())\n", f);
    fputs("    fun ord(v: Value): Value = if(v is Value.Str && v.v.isNotEmpty()) num(v.v[0].code.toDouble()) else num(0.0)\n", f);
    fputs("    fun clock(): Value = num(System.nanoTime().toDouble() / 1e9)\n\n", f);

    // Path operations
    fputs("    fun pathJoin(a: Value, b: Value): Value = str(toKString(a) + java.io.File.separator + toKString(b))\n", f);
    fputs("    fun pathExists(p: Value): Value = bool(java.io.File(toKString(p)).exists())\n", f);
    fputs("    fun pathBasename(p: Value): Value = str(java.io.File(toKString(p)).name)\n", f);
    fputs("    fun pathDirname(p: Value): Value = str(java.io.File(toKString(p)).parent ?: \"\")\n", f);
    fputs("    fun pathExt(p: Value): Value { val n=toKString(p); val d=n.lastIndexOf('.'); return if(d>=0) str(n.substring(d)) else str(\"\") }\n\n", f);

    // Hash and sizeof
    fputs("    fun hash(v: Value): Value = num(v.hashCode().toDouble())\n", f);
    fputs("    fun sizeOf(v: Value): Value = num(when(v) { is Value.Str->v.v.length.toDouble()*2; is Value.Arr->v.v.size.toDouble()*24; else->8.0 })\n", f);

    fputs("}\n", f);

    fclose(f);
    return 1;
}

int compile_source_to_android(const char* source, const char* input_path,
                              const char* output_dir,
                              const char* package_name,
                              const char* app_name,
                              int min_sdk,
                              int opt_level, int debug_info) {
    const char* pkg = (package_name && package_name[0]) ? package_name : "com.sage.app";
    const char* name = (app_name && app_name[0]) ? app_name : "SageApp";
    int sdk = min_sdk > 0 ? min_sdk : 24;

    // Detect Compose usage by scanning source for "import android.compose"
    int uses_compose = (strstr(source, "import android.compose") != NULL);

    // Create directory structure
    char pkg_path[256];
    snprintf(pkg_path, sizeof(pkg_path), "%s", pkg);
    for (char* p = pkg_path; *p; p++) { if (*p == '.') *p = '/'; }

    char src_dir[1024], runtime_dir[1024], res_dir[1024], manifest_dir[1024];
    snprintf(src_dir, sizeof(src_dir), "%s/app/src/main/kotlin/%s", output_dir, pkg_path);
    snprintf(runtime_dir, sizeof(runtime_dir), "%s/app/src/main/kotlin/sage/runtime", output_dir);
    snprintf(res_dir, sizeof(res_dir), "%s/app/src/main/res/values", output_dir);
    snprintf(manifest_dir, sizeof(manifest_dir), "%s/app/src/main", output_dir);

    kt_mkdir_p(src_dir);
    kt_mkdir_p(runtime_dir);
    kt_mkdir_p(res_dir);

    // 1. Transpile Sage → Kotlin
    char kt_output[1024];
    snprintf(kt_output, sizeof(kt_output), "%s/Main.kt", src_dir);

    // Write with package header
    FILE* out = fopen(kt_output, "wb");
    if (!out) {
        fprintf(stderr, "Could not create %s: %s\n", kt_output, strerror(errno));
        return 0;
    }
    fprintf(out, "package %s\n\n", pkg);
    fclose(out);

    // Append transpiled code
    char temp_kt[256];
    snprintf(temp_kt, sizeof(temp_kt), "/tmp/sage_kt_%d.kt", (int)getpid());
    if (!write_kotlin_output_internal(source, input_path, temp_kt, opt_level, debug_info)) {
        unlink(temp_kt);
        return 0;
    }

    // Read temp, append to output (skip the prelude's package line since we wrote our own)
    FILE* temp_in = fopen(temp_kt, "rb");
    out = fopen(kt_output, "ab");
    if (temp_in && out) {
        char buf[4096];
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), temp_in)) > 0)
            fwrite(buf, 1, n, out);
    }
    if (temp_in) fclose(temp_in);
    if (out) fclose(out);
    unlink(temp_kt);

    // 2. Write SageRuntime.kt
    kt_write_sage_runtime(runtime_dir);

    // 3. Write AndroidManifest.xml
    char manifest_path[1024];
    snprintf(manifest_path, sizeof(manifest_path), "%s/AndroidManifest.xml", manifest_dir);
    kt_write_file_fmt(manifest_path,
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\"\n"
        "    package=\"%s\">\n"
        "\n"
        "    <uses-permission android:name=\"android.permission.INTERNET\" />\n"
        "\n"
        "    <application\n"
        "        android:allowBackup=\"true\"\n"
        "        android:label=\"%s\"\n"
        "        android:supportsRtl=\"true\"\n"
        "        android:theme=\"@style/Theme.SageApp\">\n"
        "\n"
        "        <activity\n"
        "            android:name=\".MainActivity\"\n"
        "            android:exported=\"true\">\n"
        "            <intent-filter>\n"
        "                <action android:name=\"android.intent.action.MAIN\" />\n"
        "                <category android:name=\"android.intent.category.LAUNCHER\" />\n"
        "            </intent-filter>\n"
        "        </activity>\n"
        "    </application>\n"
        "</manifest>\n",
        pkg, name
    );

    // 4. Write MainActivity.kt
    char activity_path[1024];
    snprintf(activity_path, sizeof(activity_path), "%s/MainActivity.kt", src_dir);

    if (uses_compose) {
        // Compose-based MainActivity with @Composable entry point
        kt_write_file_fmt(activity_path,
            "package %s\n"
            "\n"
            "import android.os.Bundle\n"
            "import androidx.activity.ComponentActivity\n"
            "import androidx.activity.compose.setContent\n"
            "import androidx.compose.foundation.layout.*\n"
            "import androidx.compose.foundation.rememberScrollState\n"
            "import androidx.compose.foundation.verticalScroll\n"
            "import androidx.compose.material3.*\n"
            "import androidx.compose.runtime.*\n"
            "import androidx.compose.ui.Modifier\n"
            "import androidx.compose.ui.unit.dp\n"
            "import androidx.compose.ui.unit.sp\n"
            "import sage.runtime.*\n"
            "import sage.runtime.SageRuntime as S\n"
            "import java.io.ByteArrayOutputStream\n"
            "import java.io.PrintStream\n"
            "\n"
            "typealias SageVal = SageRuntime.Value\n"
            "\n"
            "class MainActivity : ComponentActivity() {\n"
            "    override fun onCreate(savedInstanceState: Bundle?) {\n"
            "        super.onCreate(savedInstanceState)\n"
            "        setContent {\n"
            "            MaterialTheme {\n"
            "                SageApp()\n"
            "            }\n"
            "        }\n"
            "    }\n"
            "}\n"
            "\n"
            "@Composable\n"
            "fun SageApp() {\n"
            "    val output = remember {\n"
            "        val capture = ByteArrayOutputStream()\n"
            "        val oldOut = System.out\n"
            "        System.setOut(PrintStream(capture))\n"
            "        try { main() } catch (e: Exception) { capture.write(\"Error: ${e.message}\".toByteArray()) }\n"
            "        finally { System.setOut(oldOut) }\n"
            "        capture.toString()\n"
            "    }\n"
            "    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {\n"
            "        Column(modifier = Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {\n"
            "            output.lines().forEach { line ->\n"
            "                Text(text = line, fontSize = 16.sp)\n"
            "            }\n"
            "        }\n"
            "    }\n"
            "}\n",
            pkg
        );
    } else {
        // Standard programmatic-view MainActivity
        kt_write_file_fmt(activity_path,
            "package %s\n"
            "\n"
            "import android.os.Bundle\n"
            "import android.widget.ScrollView\n"
            "import android.widget.TextView\n"
            "import androidx.appcompat.app.AppCompatActivity\n"
            "import sage.runtime.*\n"
            "import sage.runtime.SageRuntime as S\n"
            "import java.io.ByteArrayOutputStream\n"
            "import java.io.PrintStream\n"
            "\n"
            "typealias SageVal = SageRuntime.Value\n"
            "\n"
            "class MainActivity : AppCompatActivity() {\n"
            "    override fun onCreate(savedInstanceState: Bundle?) {\n"
            "        super.onCreate(savedInstanceState)\n"
            "\n"
            "        val capture = ByteArrayOutputStream()\n"
            "        val oldOut = System.out\n"
            "        System.setOut(PrintStream(capture))\n"
            "        try { main() }\n"
            "        catch (e: Exception) { capture.write(\"Error: ${e.message}\".toByteArray()) }\n"
            "        finally { System.setOut(oldOut) }\n"
            "\n"
            "        val tv = TextView(this).apply {\n"
            "            text = capture.toString()\n"
            "            textSize = 16f\n"
            "            setPadding(32, 32, 32, 32)\n"
            "            setTextIsSelectable(true)\n"
            "        }\n"
            "        val scroll = ScrollView(this).apply { addView(tv) }\n"
            "        setContentView(scroll)\n"
            "    }\n"
            "}\n",
            pkg
        );
    }

    // 5. Write build.gradle.kts (project root)
    char root_gradle[1024];
    snprintf(root_gradle, sizeof(root_gradle), "%s/build.gradle.kts", output_dir);

    if (uses_compose) {
        kt_write_file(root_gradle,
            "// Top-level build file generated by Sage Kotlin backend (Compose)\n"
            "plugins {\n"
            "    id(\"com.android.application\") version \"8.2.0\" apply false\n"
            "    id(\"org.jetbrains.kotlin.android\") version \"1.9.22\" apply false\n"
            "}\n"
        );
    } else {
        kt_write_file(root_gradle,
            "// Top-level build file generated by Sage Kotlin backend\n"
            "plugins {\n"
            "    id(\"com.android.application\") version \"8.2.0\" apply false\n"
            "    id(\"org.jetbrains.kotlin.android\") version \"1.9.22\" apply false\n"
            "}\n"
        );
    }

    // 6. Write settings.gradle.kts
    char settings_path[1024];
    snprintf(settings_path, sizeof(settings_path), "%s/settings.gradle.kts", output_dir);
    kt_write_file_fmt(settings_path,
        "pluginManagement {\n"
        "    repositories {\n"
        "        google()\n"
        "        mavenCentral()\n"
        "        gradlePluginPortal()\n"
        "    }\n"
        "}\n"
        "dependencyResolutionManagement {\n"
        "    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)\n"
        "    repositories {\n"
        "        google()\n"
        "        mavenCentral()\n"
        "    }\n"
        "}\n"
        "rootProject.name = \"%s\"\n"
        "include(\":app\")\n",
        name
    );

    // 7. Write app/build.gradle.kts
    char app_gradle[1024];
    snprintf(app_gradle, sizeof(app_gradle), "%s/app/build.gradle.kts", output_dir);

    if (uses_compose) {
        kt_write_file_fmt(app_gradle,
            "plugins {\n"
            "    id(\"com.android.application\")\n"
            "    id(\"org.jetbrains.kotlin.android\")\n"
            "}\n"
            "\n"
            "android {\n"
            "    namespace = \"%s\"\n"
            "    compileSdk = 34\n"
            "\n"
            "    defaultConfig {\n"
            "        applicationId = \"%s\"\n"
            "        minSdk = %d\n"
            "        targetSdk = 34\n"
            "        versionCode = 1\n"
            "        versionName = \"1.0\"\n"
            "    }\n"
            "\n"
            "    buildTypes {\n"
            "        release {\n"
            "            isMinifyEnabled = true\n"
            "            proguardFiles(getDefaultProguardFile(\"proguard-android-optimize.txt\"))\n"
            "        }\n"
            "    }\n"
            "\n"
            "    compileOptions {\n"
            "        sourceCompatibility = JavaVersion.VERSION_17\n"
            "        targetCompatibility = JavaVersion.VERSION_17\n"
            "    }\n"
            "\n"
            "    kotlinOptions {\n"
            "        jvmTarget = \"17\"\n"
            "    }\n"
            "\n"
            "    buildFeatures {\n"
            "        compose = true\n"
            "    }\n"
            "\n"
            "    composeOptions {\n"
            "        kotlinCompilerExtensionVersion = \"1.5.8\"\n"
            "    }\n"
            "}\n"
            "\n"
            "dependencies {\n"
            "    implementation(\"androidx.core:core-ktx:1.12.0\")\n"
            "    implementation(\"androidx.activity:activity-compose:1.8.2\")\n"
            "    implementation(platform(\"androidx.compose:compose-bom:2024.01.00\"))\n"
            "    implementation(\"androidx.compose.ui:ui\")\n"
            "    implementation(\"androidx.compose.material3:material3\")\n"
            "    implementation(\"androidx.compose.ui:ui-tooling-preview\")\n"
            "    implementation(\"androidx.navigation:navigation-compose:2.7.6\")\n"
            "    implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3\")\n"
            "    implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3\")\n"
            "    debugImplementation(\"androidx.compose.ui:ui-tooling\")\n"
            "}\n",
            pkg, pkg, sdk
        );
    } else {
        kt_write_file_fmt(app_gradle,
            "plugins {\n"
            "    id(\"com.android.application\")\n"
            "    id(\"org.jetbrains.kotlin.android\")\n"
            "}\n"
            "\n"
            "android {\n"
            "    namespace = \"%s\"\n"
            "    compileSdk = 34\n"
            "\n"
            "    defaultConfig {\n"
            "        applicationId = \"%s\"\n"
            "        minSdk = %d\n"
            "        targetSdk = 34\n"
            "        versionCode = 1\n"
            "        versionName = \"1.0\"\n"
            "    }\n"
            "\n"
            "    buildTypes {\n"
            "        release {\n"
            "            isMinifyEnabled = true\n"
            "            proguardFiles(getDefaultProguardFile(\"proguard-android-optimize.txt\"))\n"
            "        }\n"
            "    }\n"
            "\n"
            "    compileOptions {\n"
            "        sourceCompatibility = JavaVersion.VERSION_17\n"
            "        targetCompatibility = JavaVersion.VERSION_17\n"
            "    }\n"
            "\n"
            "    kotlinOptions {\n"
            "        jvmTarget = \"17\"\n"
            "    }\n"
            "}\n"
            "\n"
            "dependencies {\n"
            "    implementation(\"androidx.core:core-ktx:1.12.0\")\n"
            "    implementation(\"androidx.appcompat:appcompat:1.6.1\")\n"
            "    implementation(\"com.google.android.material:material:1.11.0\")\n"
            "    implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3\")\n"
            "    implementation(\"org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3\")\n"
            "}\n",
            pkg, pkg, sdk
        );
    }

    // 8. Write gradle.properties
    char gradle_props[1024];
    snprintf(gradle_props, sizeof(gradle_props), "%s/gradle.properties", output_dir);
    kt_write_file(gradle_props,
        "org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\n"
        "android.useAndroidX=true\n"
        "kotlin.code.style=official\n"
        "android.nonTransitiveRClass=true\n"
    );

    // 9. Write res/values/styles.xml (theme)
    char styles_path[1024];
    snprintf(styles_path, sizeof(styles_path), "%s/styles.xml", res_dir);
    kt_write_file(styles_path,
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<resources>\n"
        "    <style name=\"Theme.SageApp\" parent=\"Theme.MaterialComponents.DayNight.DarkActionBar\">\n"
        "        <item name=\"colorPrimary\">#6750A4</item>\n"
        "        <item name=\"colorPrimaryDark\">#4A3580</item>\n"
        "        <item name=\"colorAccent\">#B4A7D6</item>\n"
        "    </style>\n"
        "</resources>\n"
    );

    // 10. Write res/values/strings.xml
    char strings_path[1024];
    snprintf(strings_path, sizeof(strings_path), "%s/strings.xml", res_dir);
    kt_write_file_fmt(strings_path,
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<resources>\n"
        "    <string name=\"app_name\">%s</string>\n"
        "</resources>\n",
        name
    );

    printf("Android project generated at: %s\n", output_dir);
    printf("  Package: %s\n", pkg);
    printf("  Min SDK: %d\n", sdk);
    printf("  Build:   cd %s && ./gradlew assembleDebug\n", output_dir);

    return 1;
}

int build_android_apk(const char* project_dir,
                      char* apk_path_out, size_t apk_path_out_size) {
    // Check for gradlew or gradle
    char gradlew_path[1024];
    snprintf(gradlew_path, sizeof(gradlew_path), "%s/gradlew", project_dir);

    const char* gradle_cmd;
    if (access(gradlew_path, X_OK) == 0) {
        gradle_cmd = gradlew_path;
    } else {
        gradle_cmd = "gradle";
    }

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Could not fork gradle process.\n");
        return 0;
    }

    if (pid == 0) {
        if (chdir(project_dir) != 0) _exit(127);
        execlp(gradle_cmd, gradle_cmd, "assembleDebug", "--quiet", (char*)NULL);
        fprintf(stderr, "Could not execute gradle: %s\n", strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Could not wait for gradle.\n");
        return 0;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "Gradle build failed.\n");
        return 0;
    }

    if (apk_path_out && apk_path_out_size > 0) {
        snprintf(apk_path_out, apk_path_out_size,
                 "%s/app/build/outputs/apk/debug/app-debug.apk", project_dir);
    }

    return 1;
}
