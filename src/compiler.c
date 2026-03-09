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
#include "lexer.h"
#include "parser.h"

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

typedef struct {
    char* data;
    size_t len;
    size_t cap;
} StringBuffer;

typedef struct {
    FILE* out;
    const char* input_path;
    int failed;
    int indent;
    int next_unique_id;
    NameEntry* globals;
    ProcEntry* procs;
    NameEntry* locals;
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

static void compiler_error(Compiler* compiler, const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "Compiler error");
    if (compiler->input_path != NULL) {
        fprintf(stderr, " in %s", compiler->input_path);
    }
    fprintf(stderr, ": ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
    compiler->failed = 1;
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

static ProcEntry* add_proc_entry(Compiler* compiler, const char* sage_name, int param_count) {
    ProcEntry* existing = find_proc_entry(compiler->procs, sage_name);
    if (existing != NULL) {
        if (existing->param_count != param_count) {
            compiler_error(compiler, "procedure '%s' redefined with different arity", sage_name);
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
            case STMT_FOR:
            case STMT_CLASS:
            case STMT_MATCH:
            case STMT_DEFER:
            case STMT_TRY:
            case STMT_RAISE:
            case STMT_YIELD:
            case STMT_IMPORT:
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
            default:
                break;
        }
        stmt = stmt->next;
    }
}

static void collect_top_level_symbols(Compiler* compiler, Stmt* program) {
    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type == STMT_PROC) {
            char* name = token_to_string(stmt->as.proc.name);
            add_proc_entry(compiler, name, stmt->as.proc.param_count);
            free(name);
        }
    }

    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type != STMT_PROC) {
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
        compiler_error(compiler, "unsupported binary operator in C backend");
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
    if (call->callee->type != EXPR_VARIABLE) {
        compiler_error(compiler, "only direct function calls are supported by the C backend");
        return str_dup("sage_nil()");
    }

    char* callee_name = token_to_string(call->callee->as.variable.name);
    StringBuffer sb;
    sb_init(&sb);

    if (strcmp(callee_name, "str") == 0) {
        if (call->arg_count != 1) {
            compiler_error(compiler, "str() expects exactly one argument in the C backend");
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
            compiler_error(compiler, "len() expects exactly one argument in the C backend");
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
            compiler_error(compiler, "push() expects exactly two arguments in the C backend");
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
            compiler_error(compiler, "pop() expects exactly one argument in the C backend");
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
            compiler_error(compiler, "range() expects one or two arguments in the C backend");
            sb_append(&sb, "sage_nil()");
        }
        free(callee_name);
        return sb_take(&sb);
    }

    if (strcmp(callee_name, "slice") == 0) {
        if (call->arg_count != 3) {
            compiler_error(compiler, "slice() expects exactly three arguments in the C backend");
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

    ProcEntry* proc = find_proc_entry(compiler->procs, callee_name);
    if (proc == NULL) {
        compiler_error(compiler, "call target '%s' is not supported by the C backend", callee_name);
        free(callee_name);
        return str_dup("sage_nil()");
    }

    if (proc->param_count != call->arg_count) {
        compiler_error(compiler, "call to '%s' has arity %d, expected %d",
                       callee_name, call->arg_count, proc->param_count);
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
        compiler_error(compiler, "property assignment is not supported by the C backend");
        return str_dup("sage_nil()");
    }

    char* name = token_to_string(set->property);
    const char* slot_name = resolve_slot_name(compiler, name);
    if (slot_name == NULL) {
        compiler_error(compiler, "assignment to undefined variable '%s'", name);
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
                compiler_error(compiler, "variable '%s' is not available in the C backend scope", name);
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
        case EXPR_SLICE:
            return emit_slice_expr(compiler, &expr->as.slice);
        case EXPR_SET:
            return emit_set_expr(compiler, &expr->as.set);
        case EXPR_DICT:
        case EXPR_TUPLE:
        case EXPR_GET:
            compiler_error(compiler, "expression kind is not yet supported by the Phase 10 C backend");
            return str_dup("sage_nil()");
    }

    compiler_error(compiler, "unknown expression kind");
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
                compiler_error(compiler, "let target '%s' was not collected for code generation", name);
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
            emit_line(compiler, "return %s;", expr);
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
        case STMT_FOR:
        case STMT_CLASS:
        case STMT_MATCH:
        case STMT_DEFER:
        case STMT_TRY:
        case STMT_RAISE:
        case STMT_YIELD:
        case STMT_IMPORT:
            compiler_error(compiler, "statement kind is not yet supported by the Phase 10 C backend");
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
        "\n"
        "typedef struct {\n"
        "    int count;\n"
        "    int capacity;\n"
        "    SageValue* elements;\n"
        "} SageArray;\n"
        "\n"
        "typedef enum {\n"
        "    SAGE_TAG_NIL,\n"
        "    SAGE_TAG_NUMBER,\n"
        "    SAGE_TAG_BOOL,\n"
        "    SAGE_TAG_STRING,\n"
        "    SAGE_TAG_ARRAY\n"
        "} SageTag;\n"
        "\n"
        "struct SageValue {\n"
        "    SageTag type;\n"
        "    union {\n"
        "        double number;\n"
        "        int boolean;\n"
        "        const char* string;\n"
        "        SageArray* array;\n"
        "    } as;\n"
        "};\n"
        "\n"
        "typedef struct {\n"
        "    int defined;\n"
        "    SageValue value;\n"
        "} SageSlot;\n"
        "\n"
        "static void sage_fail(const char* message) {\n"
        "    fputs(message, stderr);\n"
        "    fputc('\\n', stderr);\n"
        "    exit(1);\n"
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
        "static SageArray* sage_new_array(void) {\n"
        "    SageArray* array = (SageArray*)malloc(sizeof(SageArray));\n"
        "    if (array == NULL) sage_fail(\"Runtime Error: out of memory\");\n"
        "    array->count = 0;\n"
        "    array->capacity = 0;\n"
        "    array->elements = NULL;\n"
        "    return array;\n"
        "}\n"
        "\n"
        "static SageValue sage_nil(void) { SageValue v; v.type = SAGE_TAG_NIL; v.as.number = 0; return v; }\n"
        "static SageValue sage_number(double value) { SageValue v; v.type = SAGE_TAG_NUMBER; v.as.number = value; return v; }\n"
        "static SageValue sage_bool(int value) { SageValue v; v.type = SAGE_TAG_BOOL; v.as.boolean = value ? 1 : 0; return v; }\n"
        "static SageValue sage_string(const char* value) { SageValue v; v.type = SAGE_TAG_STRING; v.as.string = value; return v; }\n"
        "static SageValue sage_array(void) { SageValue v; v.type = SAGE_TAG_ARRAY; v.as.array = sage_new_array(); return v; }\n"
        "static SageSlot sage_slot_undefined(void) { SageSlot slot; slot.defined = 0; slot.value = sage_nil(); return slot; }\n"
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
        "    SageValue array = sage_array();\n"
        "    for (int i = 0; i < count; i++) {\n"
        "        sage_array_push_raw(array.as.array, values[i]);\n"
        "    }\n"
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
        "            return sage_string(sage_dup_string(buffer));\n"
        "        case SAGE_TAG_BOOL:\n"
        "            return sage_string(value.as.boolean ? \"true\" : \"false\");\n"
        "        case SAGE_TAG_NIL:\n"
        "            return sage_string(\"nil\");\n"
        "        case SAGE_TAG_ARRAY:\n"
        "            return sage_string(\"nil\");\n"
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
        "    return sage_nil();\n"
        "}\n"
        "\n"
        "static SageValue sage_index(SageValue array, SageValue index) {\n"
        "    if (array.type != SAGE_TAG_ARRAY || index.type != SAGE_TAG_NUMBER) return sage_nil();\n"
        "    int idx = (int)index.as.number;\n"
        "    if (idx < 0 || idx >= array.as.array->count) return sage_nil();\n"
        "    return array.as.array->elements[idx];\n"
        "}\n"
        "\n"
        "static SageValue sage_slice(SageValue array, SageValue start, SageValue end) {\n"
        "    if (array.type != SAGE_TAG_ARRAY) return sage_nil();\n"
        "    int start_index = 0;\n"
        "    int end_index = array.as.array->count;\n"
        "    if (start.type == SAGE_TAG_NUMBER) start_index = (int)start.as.number;\n"
        "    else if (start.type != SAGE_TAG_NIL) return sage_nil();\n"
        "    if (end.type == SAGE_TAG_NUMBER) end_index = (int)end.as.number;\n"
        "    else if (end.type != SAGE_TAG_NIL) return sage_nil();\n"
        "    if (start_index < 0) start_index = array.as.array->count + start_index;\n"
        "    if (end_index < 0) end_index = array.as.array->count + end_index;\n"
        "    if (start_index < 0) start_index = 0;\n"
        "    if (end_index > array.as.array->count) end_index = array.as.array->count;\n"
        "    if (start_index >= end_index) return sage_array();\n"
        "    SageValue result = sage_array();\n"
        "    for (int i = start_index; i < end_index; i++) {\n"
        "        sage_array_push_raw(result.as.array, array.as.array->elements[i]);\n"
        "    }\n"
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
        "    SageValue result = sage_array();\n"
        "    for (int i = (int)start.as.number; i < (int)end.as.number; i++) {\n"
        "        sage_array_push_raw(result.as.array, sage_number((double)i));\n"
        "    }\n"
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
        "        return sage_string(result);\n"
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
        "\n",
        out
    );
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

static void emit_slot_declarations(Compiler* compiler, NameEntry* locals) {
    for (NameEntry* local = locals; local != NULL; local = local->next) {
        emit_line(compiler, "SageSlot %s = sage_slot_undefined();", local->c_name);
    }
}

static void emit_function_definition(Compiler* compiler, Stmt* stmt) {
    ProcStmt* proc_stmt = &stmt->as.proc;
    char* proc_name = token_to_string(proc_stmt->name);
    ProcEntry* proc = find_proc_entry(compiler->procs, proc_name);
    free(proc_name);
    if (proc == NULL) {
        compiler_error(compiler, "missing proc metadata during code generation");
        return;
    }

    NameEntry* params = NULL;
    for (int i = 0; i < proc_stmt->param_count; i++) {
        char* param_name = token_to_string(proc_stmt->params[i]);
        if (find_name_entry(params, param_name) != NULL) {
            compiler_error(compiler, "duplicate parameter '%s' in procedure", param_name);
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
    for (int i = 0; i < proc_stmt->param_count; i++) {
        char* param_name = token_to_string(proc_stmt->params[i]);
        NameEntry* param = find_name_entry(compiler->locals, param_name);
        free(param_name);
        emit_line(compiler, "sage_define_slot(&%s, arg%d);", param->c_name, i);
    }

    emit_stmt_list(compiler, proc_stmt->body);
    emit_line(compiler, "return sage_nil();");

    compiler->indent--;
    emit_line(compiler, "}");
    fputc('\n', compiler->out);

    free_name_entries(compiler->locals);
    compiler->locals = previous_locals;
}

static void emit_function_definitions(Compiler* compiler, Stmt* program) {
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

    for (Stmt* stmt = program; stmt != NULL; stmt = stmt->next) {
        if (stmt->type != STMT_PROC) {
            emit_stmt(compiler, stmt);
            if (compiler->failed) {
                compiler->indent--;
                emit_line(compiler, "return 1;");
                emit_line(compiler, "}");
                return;
            }
        }
    }

    emit_line(compiler, "return 0;");
    compiler->indent--;
    emit_line(compiler, "}");
}

static Stmt* parse_program(const char* source) {
    init_lexer(source);
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

static int write_c_output(const char* source, const char* input_path, const char* output_path,
                          CompilerTarget target) {
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

    Stmt* program = parse_program(source);
    collect_top_level_symbols(&compiler, program);

    if (!compiler.failed) {
        emit_runtime_prelude(out, target);
        compiler.indent = 0;
        emit_proc_prototypes(&compiler);
        if (compiler.procs != NULL) {
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
    return compiler.failed ? 0 : 1;
}

int compile_source_to_c(const char* source, const char* input_path, const char* output_path) {
    return write_c_output(source, input_path, output_path, COMPILER_TARGET_HOST);
}

int compile_source_to_executable(const char* source, const char* input_path,
                                 const char* c_output_path, const char* exe_output_path,
                                 const char* cc_command) {
    if (!write_c_output(source, input_path, c_output_path, COMPILER_TARGET_HOST)) {
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

int compile_source_to_pico_c(const char* source, const char* input_path, const char* output_path) {
    return write_c_output(source, input_path, output_path, COMPILER_TARGET_PICO);
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

    if (!write_c_output(source, input_path, source_path, COMPILER_TARGET_PICO)) {
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
