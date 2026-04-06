#include "aot.h"
#include "gc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>

// ============================================================================
// AOT Compiler — Generates type-specialized C code
// ============================================================================

void aot_init(AotCompiler* aot, int opt_level) {
    memset(aot, 0, sizeof(AotCompiler));
    aot->opt_level = opt_level;
    aot->emit_guards = 0;
}

void aot_free(AotCompiler* aot) {
    for (int i = 0; i < aot->line_count; i++) free(aot->lines[i]);
    free(aot->lines);
    for (int i = 0; i < aot->type_env.count; i++) free(aot->type_env.vars[i].name);
    free(aot->type_env.vars);
    memset(aot, 0, sizeof(AotCompiler));
}

static void aot_emit(AotCompiler* aot, const char* fmt, ...) {
    char buf[4096];
    // Indent
    int offset = 0;
    for (int i = 0; i < aot->indent; i++) {
        buf[offset++] = ' '; buf[offset++] = ' ';
        buf[offset++] = ' '; buf[offset++] = ' ';
    }
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf + offset, sizeof(buf) - offset, fmt, ap);
    va_end(ap);

    if (aot->line_count >= aot->line_capacity) {
        aot->line_capacity = aot->line_capacity == 0 ? 256 : aot->line_capacity * 2;
        aot->lines = realloc(aot->lines, sizeof(char*) * aot->line_capacity);
    }
    aot->lines[aot->line_count++] = strdup(buf);
}

// ============================================================================
// Type Inference
// ============================================================================

void aot_set_var_type(AotCompiler* aot, const char* name, JitTypeTag type) {
    for (int i = 0; i < aot->type_env.count; i++) {
        if (strcmp(aot->type_env.vars[i].name, name) == 0) {
            aot->type_env.vars[i].inferred_type = type;
            return;
        }
    }
    if (aot->type_env.count >= aot->type_env.capacity) {
        aot->type_env.capacity = aot->type_env.capacity == 0 ? 32 : aot->type_env.capacity * 2;
        aot->type_env.vars = realloc(aot->type_env.vars, sizeof(AotVarType) * aot->type_env.capacity);
    }
    aot->type_env.vars[aot->type_env.count].name = strdup(name);
    aot->type_env.vars[aot->type_env.count].inferred_type = type;
    aot->type_env.count++;
}

JitTypeTag aot_get_var_type(AotCompiler* aot, const char* name) {
    for (int i = 0; i < aot->type_env.count; i++) {
        if (strcmp(aot->type_env.vars[i].name, name) == 0) {
            return aot->type_env.vars[i].inferred_type;
        }
    }
    return JIT_TYPE_UNKNOWN;
}

static JitTypeTag aot_infer_expr_type(AotCompiler* aot, Expr* expr) {
    if (!expr) return JIT_TYPE_UNKNOWN;
    switch (expr->type) {
        case EXPR_NUMBER: {
            double d = expr->as.number.value;
            if (d == (double)(int64_t)d) return JIT_TYPE_INT;
            return JIT_TYPE_FLOAT;
        }
        case EXPR_STRING: return JIT_TYPE_STRING;
        case EXPR_BOOL:   return JIT_TYPE_BOOL;
        case EXPR_NIL:    return JIT_TYPE_NIL;
        case EXPR_ARRAY:  return JIT_TYPE_ARRAY;
        case EXPR_DICT:   return JIT_TYPE_DICT;
        case EXPR_VARIABLE: {
            char name[256];
            int len = expr->as.variable.name.length;
            if (len > 255) len = 255;
            memcpy(name, expr->as.variable.name.start, len);
            name[len] = '\0';
            return aot_get_var_type(aot, name);
        }
        case EXPR_BINARY: {
            JitTypeTag left = aot_infer_expr_type(aot, expr->as.binary.left);
            JitTypeTag right = aot_infer_expr_type(aot, expr->as.binary.right);
            int op = expr->as.binary.op.type;
            // Arithmetic on ints stays int
            if (left == JIT_TYPE_INT && right == JIT_TYPE_INT) {
                if (op == TOKEN_PLUS || op == TOKEN_MINUS || op == TOKEN_STAR || op == TOKEN_PERCENT)
                    return JIT_TYPE_INT;
                if (op == TOKEN_SLASH) return JIT_TYPE_FLOAT;
                if (op == TOKEN_GT || op == TOKEN_LT || op == TOKEN_GTE || op == TOKEN_LTE ||
                    op == TOKEN_EQ || op == TOKEN_NEQ)
                    return JIT_TYPE_BOOL;
            }
            if ((left == JIT_TYPE_INT || left == JIT_TYPE_FLOAT) &&
                (right == JIT_TYPE_INT || right == JIT_TYPE_FLOAT)) {
                if (op == TOKEN_PLUS || op == TOKEN_MINUS || op == TOKEN_STAR || op == TOKEN_SLASH)
                    return JIT_TYPE_FLOAT;
            }
            if (left == JIT_TYPE_STRING && right == JIT_TYPE_STRING && op == TOKEN_PLUS)
                return JIT_TYPE_STRING;
            if (op == TOKEN_EQ || op == TOKEN_NEQ || op == TOKEN_GT || op == TOKEN_LT ||
                op == TOKEN_GTE || op == TOKEN_LTE)
                return JIT_TYPE_BOOL;
            return JIT_TYPE_UNKNOWN;
        }
        default: return JIT_TYPE_UNKNOWN;
    }
}

void aot_infer_types(AotCompiler* aot, Stmt* program) {
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_LET && s->as.let.initializer) {
            JitTypeTag t = aot_infer_expr_type(aot, s->as.let.initializer);
            char name[256];
            int len = s->as.let.name.length;
            if (len > 255) len = 255;
            memcpy(name, s->as.let.name.start, len);
            name[len] = '\0';
            aot_set_var_type(aot, name, t);
        }
    }
}

// ============================================================================
// C Code Generation — Type-Specialized
// ============================================================================

static char* aot_temp(AotCompiler* aot) {
    char buf[32];
    snprintf(buf, sizeof(buf), "t%d", aot->next_temp++);
    return strdup(buf);
}

static char* escape_c_str(const char* s) {
    int len = (int)strlen(s);
    char* out = malloc(len * 4 + 1);
    int j = 0;
    for (int i = 0; i < len; i++) {
        switch (s[i]) {
            case '\n': out[j++]='\\'; out[j++]='n'; break;
            case '\t': out[j++]='\\'; out[j++]='t'; break;
            case '\\': out[j++]='\\'; out[j++]='\\'; break;
            case '"':  out[j++]='\\'; out[j++]='"'; break;
            default:   out[j++]=s[i]; break;
        }
    }
    out[j] = '\0';
    return out;
}

static char* sanitize_name(const char* start, int len) {
    char* out = malloc(len + 8);
    out[0] = 's'; out[1] = '_';
    for (int i = 0; i < len; i++) {
        char c = start[i];
        out[i + 2] = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                     (c >= '0' && c <= '9') || c == '_' ? c : '_';
    }
    out[len + 2] = '\0';
    return out;
}

char* aot_compile_expr(AotCompiler* aot, Expr* expr) {
    if (!expr) return strdup("sage_nil()");

    switch (expr->type) {
        case EXPR_NUMBER: {
            char buf[64];
            snprintf(buf, sizeof(buf), "sage_number(%.17g)", expr->as.number.value);
            return strdup(buf);
        }
        case EXPR_STRING: {
            char* esc = escape_c_str(expr->as.string.value);
            char* buf = malloc(strlen(esc) + 32);
            sprintf(buf, "sage_string(\"%s\")", esc);
            free(esc);
            return buf;
        }
        case EXPR_BOOL:
            return strdup(expr->as.boolean.value ? "sage_bool(1)" : "sage_bool(0)");
        case EXPR_NIL:
            return strdup("sage_nil()");
        case EXPR_VARIABLE: {
            char* name = sanitize_name(expr->as.variable.name.start, expr->as.variable.name.length);
            return name;
        }
        case EXPR_BINARY: {
            char* left = aot_compile_expr(aot, expr->as.binary.left);
            char* right = aot_compile_expr(aot, expr->as.binary.right);
            JitTypeTag lt = aot_infer_expr_type(aot, expr->as.binary.left);
            JitTypeTag rt = aot_infer_expr_type(aot, expr->as.binary.right);
            char* result = malloc(strlen(left) + strlen(right) + 128);

            int op = expr->as.binary.op.type;
            // Type-specialized fast paths
            if (lt == JIT_TYPE_INT && rt == JIT_TYPE_INT) {
                const char* cop = NULL;
                switch (op) {
                    case TOKEN_PLUS:  cop = "+"; break;
                    case TOKEN_MINUS: cop = "-"; break;
                    case TOKEN_STAR:  cop = "*"; break;
                    case TOKEN_GT:  sprintf(result, "sage_bool(%s.as.number > %s.as.number)", left, right); goto done;
                    case TOKEN_LT:  sprintf(result, "sage_bool(%s.as.number < %s.as.number)", left, right); goto done;
                    case TOKEN_EQ:  sprintf(result, "sage_bool(%s.as.number == %s.as.number)", left, right); goto done;
                    case TOKEN_NEQ: sprintf(result, "sage_bool(%s.as.number != %s.as.number)", left, right); goto done;
                    default: break;
                }
                if (cop) {
                    sprintf(result, "sage_number(%s.as.number %s %s.as.number)", left, cop, right);
                    goto done;
                }
            }
            if (lt == JIT_TYPE_STRING && rt == JIT_TYPE_STRING && op == TOKEN_PLUS) {
                sprintf(result, "sage_strcat(%s, %s)", left, right);
                goto done;
            }
            // Generic fallback — all operators
            switch (op) {
                case TOKEN_PLUS:    sprintf(result, "sage_add(%s, %s)", left, right); break;
                case TOKEN_MINUS:   sprintf(result, "sage_sub(%s, %s)", left, right); break;
                case TOKEN_STAR:    sprintf(result, "sage_mul(%s, %s)", left, right); break;
                case TOKEN_SLASH:   sprintf(result, "sage_div(%s, %s)", left, right); break;
                case TOKEN_PERCENT: sprintf(result, "sage_mod(%s, %s)", left, right); break;
                case TOKEN_EQ:      sprintf(result, "sage_eq(%s, %s)", left, right); break;
                case TOKEN_NEQ:     sprintf(result, "sage_neq(%s, %s)", left, right); break;
                case TOKEN_GT:      sprintf(result, "sage_gt(%s, %s)", left, right); break;
                case TOKEN_LT:      sprintf(result, "sage_lt(%s, %s)", left, right); break;
                case TOKEN_GTE:     sprintf(result, "sage_bool(%s.as.number >= %s.as.number)", left, right); break;
                case TOKEN_LTE:     sprintf(result, "sage_bool(%s.as.number <= %s.as.number)", left, right); break;
                case TOKEN_AND:     sprintf(result, "(sage_truthy(%s) ? %s : %s)", left, right, left); break;
                case TOKEN_OR:      sprintf(result, "(sage_truthy(%s) ? %s : %s)", left, left, right); break;
                case TOKEN_NOT:     sprintf(result, "sage_bool(!sage_truthy(%s))", left); break;
                case TOKEN_AMP:     sprintf(result, "sage_number((double)((long long)%s.as.number & (long long)%s.as.number))", left, right); break;
                case TOKEN_PIPE:    sprintf(result, "sage_number((double)((long long)%s.as.number | (long long)%s.as.number))", left, right); break;
                case TOKEN_CARET:   sprintf(result, "sage_number((double)((long long)%s.as.number ^ (long long)%s.as.number))", left, right); break;
                case TOKEN_LSHIFT:  sprintf(result, "sage_number((double)((long long)%s.as.number << (int)%s.as.number))", left, right); break;
                case TOKEN_RSHIFT:  sprintf(result, "sage_number((double)((long long)%s.as.number >> (int)%s.as.number))", left, right); break;
                default:            sprintf(result, "sage_add(%s, %s)", left, right); break;
            }
            done:
            free(left);
            free(right);
            return result;
        }
        case EXPR_CALL: {
            if (expr->as.call.callee && expr->as.call.callee->type == EXPR_VARIABLE) {
                const char* raw = expr->as.call.callee->as.variable.name.start;
                int rawlen = expr->as.call.callee->as.variable.name.length;
                int argc = expr->as.call.arg_count;

                // Builtin function mapping — direct C calls for known builtins
                #define BUILTIN_MATCH(name) (rawlen == (int)strlen(name) && memcmp(raw, name, rawlen) == 0)
                #define EMIT_1(cfn) do { char*a0=aot_compile_expr(aot,expr->as.call.args[0]); char*b=malloc(strlen(a0)+64); sprintf(b,"%s(%s)",cfn,a0); free(a0); return b; } while(0)
                #define EMIT_2(cfn) do { char*a0=aot_compile_expr(aot,expr->as.call.args[0]); char*a1=aot_compile_expr(aot,expr->as.call.args[1]); char*b=malloc(strlen(a0)+strlen(a1)+64); sprintf(b,"%s(%s, %s)",cfn,a0,a1); free(a0);free(a1); return b; } while(0)

                if (BUILTIN_MATCH("len") && argc==1) EMIT_1("sage_len");
                if (BUILTIN_MATCH("str") && argc==1) EMIT_1("sage_str");
                if (BUILTIN_MATCH("tonumber") && argc==1) EMIT_1("sage_tonumber");
                if (BUILTIN_MATCH("type") && argc==1) EMIT_1("sage_type");
                if (BUILTIN_MATCH("push") && argc==2) {
                    char*a0=aot_compile_expr(aot,expr->as.call.args[0]);
                    char*a1=aot_compile_expr(aot,expr->as.call.args[1]);
                    char*b=malloc(strlen(a0)+strlen(a1)+64);
                    sprintf(b,"(sage_push(%s, %s), sage_nil())",a0,a1);
                    free(a0);free(a1); return b;
                }
                if (BUILTIN_MATCH("pop") && argc==1) EMIT_1("sage_pop");
                if (BUILTIN_MATCH("dict_keys") && argc==1) EMIT_1("sage_dict_keys");
                if (BUILTIN_MATCH("range") && argc==1) {
                    char*a0=aot_compile_expr(aot,expr->as.call.args[0]);
                    char*b=malloc(strlen(a0)+64);
                    sprintf(b,"sage_range((int)%s.as.number)",a0);
                    free(a0); return b;
                }

                #undef BUILTIN_MATCH
                #undef EMIT_1
                #undef EMIT_2

                // User-defined function call
                char* fname = sanitize_name(raw, rawlen);
                char* buf = malloc(4096);
                int pos = sprintf(buf, "({ SageValue _args[%d]; ", argc > 0 ? argc : 1);
                for (int i = 0; i < argc; i++) {
                    char* arg = aot_compile_expr(aot, expr->as.call.args[i]);
                    pos += sprintf(buf + pos, "_args[%d] = %s; ", i, arg);
                    free(arg);
                }
                pos += sprintf(buf + pos, "%s(%d, _args); })", fname, argc);
                free(fname);
                return buf;
            }
            char* callee = aot_compile_expr(aot, expr->as.call.callee);
            char* buf = malloc(256);
            sprintf(buf, "sage_nil() /* unsupported call: %s */", callee);
            free(callee);
            return buf;
        }
        case EXPR_SET: {
            // Variable assignment: name = value
            if (expr->as.set.object == NULL && expr->as.set.property.start) {
                char* name = sanitize_name(expr->as.set.property.start, expr->as.set.property.length);
                char* val = aot_compile_expr(aot, expr->as.set.value);
                char* buf = malloc(strlen(name) + strlen(val) + 16);
                sprintf(buf, "(%s = %s)", name, val);
                free(name);
                free(val);
                return buf;
            }
            return strdup("sage_nil()");
        }
        case EXPR_ARRAY: {
            int n = expr->as.array.count;
            char* buf = malloc(4096);
            int pos = sprintf(buf, "sage_array(%d", n);
            for (int i = 0; i < n; i++) {
                char* elem = aot_compile_expr(aot, expr->as.array.elements[i]);
                pos += sprintf(buf + pos, ", %s", elem);
                free(elem);
            }
            pos += sprintf(buf + pos, ")");
            return buf;
        }
        case EXPR_INDEX: {
            char* obj = aot_compile_expr(aot, expr->as.index.array);
            char* idx = aot_compile_expr(aot, expr->as.index.index);
            char* buf = malloc(strlen(obj) + strlen(idx) + 32);
            sprintf(buf, "sage_index(%s, %s)", obj, idx);
            free(obj); free(idx);
            return buf;
        }
        case EXPR_INDEX_SET: {
            char* obj = aot_compile_expr(aot, expr->as.index_set.array);
            char* idx = aot_compile_expr(aot, expr->as.index_set.index);
            char* val = aot_compile_expr(aot, expr->as.index_set.value);
            char* buf = malloc(strlen(obj) + strlen(idx) + strlen(val) + 48);
            sprintf(buf, "sage_index_set(%s, %s, %s)", obj, idx, val);
            free(obj); free(idx); free(val);
            return buf;
        }
        case EXPR_DICT: {
            int n = expr->as.dict.count;
            char* buf = malloc(4096);
            int pos = sprintf(buf, "sage_dict(%d", n);
            for (int i = 0; i < n; i++) {
                char* esc = escape_c_str(expr->as.dict.keys[i]);
                char* val = aot_compile_expr(aot, expr->as.dict.values[i]);
                pos += sprintf(buf + pos, ", \"%s\", %s", esc, val);
                free(esc); free(val);
            }
            pos += sprintf(buf + pos, ")");
            return buf;
        }
        case EXPR_GET: {
            char* obj = aot_compile_expr(aot, expr->as.get.object);
            char* prop = sanitize_name(expr->as.get.property.start, expr->as.get.property.length);
            char* esc = escape_c_str(prop + 2); // skip s_ prefix
            char* buf = malloc(strlen(obj) + strlen(esc) + 48);
            sprintf(buf, "sage_get_property(%s, \"%s\")", obj, esc);
            free(obj); free(prop); free(esc);
            return buf;
        }
        case EXPR_SLICE: {
            char* obj = aot_compile_expr(aot, expr->as.slice.array);
            char* start = expr->as.slice.start ? aot_compile_expr(aot, expr->as.slice.start) : strdup("sage_number(0)");
            char* end = expr->as.slice.end ? aot_compile_expr(aot, expr->as.slice.end) : strdup("sage_nil()");
            char* buf = malloc(strlen(obj) + strlen(start) + strlen(end) + 48);
            sprintf(buf, "sage_slice(%s, %s, %s)", obj, start, end);
            free(obj); free(start); free(end);
            return buf;
        }
        case EXPR_TUPLE: {
            int n = expr->as.tuple.count;
            char* buf = malloc(4096);
            int pos = sprintf(buf, "sage_tuple(%d", n);
            for (int i = 0; i < n; i++) {
                char* elem = aot_compile_expr(aot, expr->as.tuple.elements[i]);
                pos += sprintf(buf + pos, ", %s", elem);
                free(elem);
            }
            pos += sprintf(buf + pos, ")");
            return buf;
        }
        case EXPR_AWAIT:
            return aot_compile_expr(aot, expr->as.await.expression);
        case EXPR_COMPTIME:
            return aot_compile_expr(aot, expr->as.comptime.expression);
        default: return strdup("sage_nil()");
    }
}

void aot_compile_stmt(AotCompiler* aot, Stmt* stmt) {
    if (!stmt) return;
    switch (stmt->type) {
        case STMT_PRINT: {
            char* val = aot_compile_expr(aot, stmt->as.print.expression);
            aot_emit(aot, "sage_print_value(%s); printf(\"\\n\");", val);
            free(val);
            break;
        }
        case STMT_LET: {
            char* name = sanitize_name(stmt->as.let.name.start, stmt->as.let.name.length);
            if (stmt->as.let.initializer) {
                char* val = aot_compile_expr(aot, stmt->as.let.initializer);
                aot_emit(aot, "SageValue %s = %s;", name, val);
                free(val);
            } else {
                aot_emit(aot, "SageValue %s = sage_nil();", name);
            }
            free(name);
            break;
        }
        case STMT_EXPRESSION: {
            char* val = aot_compile_expr(aot, stmt->as.expression);
            aot_emit(aot, "%s;", val);
            free(val);
            break;
        }
        case STMT_IF: {
            char* cond = aot_compile_expr(aot, stmt->as.if_stmt.condition);
            aot_emit(aot, "if (sage_truthy(%s)) {", cond);
            free(cond);
            aot->indent++;
            for (Stmt* s = stmt->as.if_stmt.then_branch; s; s = s->next)
                aot_compile_stmt(aot, s);
            aot->indent--;
            if (stmt->as.if_stmt.else_branch) {
                aot_emit(aot, "} else {");
                aot->indent++;
                for (Stmt* s = stmt->as.if_stmt.else_branch; s; s = s->next)
                    aot_compile_stmt(aot, s);
                aot->indent--;
            }
            aot_emit(aot, "}");
            break;
        }
        case STMT_WHILE: {
            char* cond = aot_compile_expr(aot, stmt->as.while_stmt.condition);
            aot_emit(aot, "while (sage_truthy(%s)) {", cond);
            free(cond);
            aot->indent++;
            for (Stmt* s = stmt->as.while_stmt.body; s; s = s->next)
                aot_compile_stmt(aot, s);
            // Re-evaluate condition
            cond = aot_compile_expr(aot, stmt->as.while_stmt.condition);
            free(cond);
            aot->indent--;
            aot_emit(aot, "}");
            break;
        }
        case STMT_RETURN: {
            if (stmt->as.ret.value) {
                char* val = aot_compile_expr(aot, stmt->as.ret.value);
                aot_emit(aot, "return %s;", val);
                free(val);
            } else {
                aot_emit(aot, "return sage_nil();");
            }
            break;
        }
        case STMT_BLOCK: {
            for (Stmt* s = stmt->as.block.statements; s; s = s->next)
                aot_compile_stmt(aot, s);
            break;
        }
        case STMT_FOR: {
            char* iterable = aot_compile_expr(aot, stmt->as.for_stmt.iterable);
            char* var = sanitize_name(stmt->as.for_stmt.variable.start, stmt->as.for_stmt.variable.length);
            char* idx = aot_temp(aot);
            aot_emit(aot, "{ SageValue _iter_%s = %s;", idx, iterable);
            aot->indent++;
            aot_emit(aot, "for (int %s = 0; %s < sage_array_len(_iter_%s); %s++) {", idx, idx, idx, idx);
            aot->indent++;
            aot_emit(aot, "SageValue %s = sage_array_get(_iter_%s, %s);", var, idx, idx);
            for (Stmt* s = stmt->as.for_stmt.body; s; s = s->next)
                aot_compile_stmt(aot, s);
            aot->indent--;
            aot_emit(aot, "}");
            aot->indent--;
            aot_emit(aot, "}");
            free(iterable); free(var); free(idx);
            break;
        }
        case STMT_BREAK:
            aot_emit(aot, "break;");
            break;
        case STMT_CONTINUE:
            aot_emit(aot, "continue;");
            break;
        case STMT_TRY: {
            aot_emit(aot, "/* try */ {");
            aot->indent++;
            for (Stmt* s = stmt->as.try_stmt.try_block; s; s = s->next)
                aot_compile_stmt(aot, s);
            aot->indent--;
            aot_emit(aot, "}");
            if (stmt->as.try_stmt.finally_block) {
                aot_emit(aot, "/* finally */ {");
                aot->indent++;
                for (Stmt* s = stmt->as.try_stmt.finally_block; s; s = s->next)
                    aot_compile_stmt(aot, s);
                aot->indent--;
                aot_emit(aot, "}");
            }
            break;
        }
        case STMT_RAISE: {
            char* val = aot_compile_expr(aot, stmt->as.raise.exception);
            aot_emit(aot, "{ sage_print_value(%s); printf(\"\\n\"); exit(1); } /* raise */", val);
            free(val);
            break;
        }
        case STMT_MATCH: {
            char* val = aot_compile_expr(aot, stmt->as.match_stmt.value);
            char* tmp = aot_temp(aot);
            aot_emit(aot, "{ SageValue %s = %s;", tmp, val);
            aot->indent++;
            for (int i = 0; i < stmt->as.match_stmt.case_count; i++) {
                CaseClause* c = stmt->as.match_stmt.cases[i];
                char* pat = aot_compile_expr(aot, c->pattern);
                aot_emit(aot, "%sif (sage_eq(%s, %s).as.boolean) {", i > 0 ? "} else " : "", tmp, pat);
                aot->indent++;
                for (Stmt* s = c->body; s; s = s->next)
                    aot_compile_stmt(aot, s);
                aot->indent--;
                free(pat);
            }
            if (stmt->as.match_stmt.default_case) {
                aot_emit(aot, "} else {");
                aot->indent++;
                for (Stmt* s = stmt->as.match_stmt.default_case; s; s = s->next)
                    aot_compile_stmt(aot, s);
                aot->indent--;
            }
            if (stmt->as.match_stmt.case_count > 0 || stmt->as.match_stmt.default_case)
                aot_emit(aot, "}");
            aot->indent--;
            aot_emit(aot, "}");
            free(val); free(tmp);
            break;
        }
        case STMT_DEFER: {
            aot_emit(aot, "/* defer */ {");
            aot->indent++;
            for (Stmt* s = stmt->as.defer.statement; s; s = s->next)
                aot_compile_stmt(aot, s);
            aot->indent--;
            aot_emit(aot, "}");
            break;
        }
        case STMT_YIELD:
            if (stmt->as.yield_stmt.value) {
                char* val = aot_compile_expr(aot, stmt->as.yield_stmt.value);
                aot_emit(aot, "return %s; /* yield */", val);
                free(val);
            } else {
                aot_emit(aot, "return sage_nil(); /* yield */");
            }
            break;
        case STMT_IMPORT:
            aot_emit(aot, "/* import %s */", stmt->as.import.module_name ? stmt->as.import.module_name : "?");
            break;
        case STMT_CLASS:
            aot_emit(aot, "/* class %.*s — classes compiled as dict constructors */", stmt->as.class_stmt.name.length, stmt->as.class_stmt.name.start);
            break;
        case STMT_ASYNC_PROC:
            // Treat as regular proc
            if (1) {
                char* name = sanitize_name(stmt->as.async_proc.name.start, stmt->as.async_proc.name.length);
                aot_emit(aot, "/* async */ static SageValue %s(int argc, SageValue* argv) {", name);
                aot->indent++;
                for (int i = 0; i < stmt->as.async_proc.param_count; i++) {
                    char* pn = sanitize_name(stmt->as.async_proc.params[i].start, stmt->as.async_proc.params[i].length);
                    aot_emit(aot, "SageValue %s = (argc > %d) ? argv[%d] : sage_nil();", pn, i, i);
                    free(pn);
                }
                for (Stmt* bs = stmt->as.async_proc.body; bs; bs = bs->next)
                    aot_compile_stmt(aot, bs);
                aot_emit(aot, "return sage_nil();");
                aot->indent--;
                aot_emit(aot, "}");
                free(name);
            }
            break;
        case STMT_STRUCT:
            aot_emit(aot, "/* struct %.*s */", stmt->as.struct_stmt.name.length, stmt->as.struct_stmt.name.start);
            break;
        case STMT_ENUM:
            aot_emit(aot, "/* enum %.*s */", stmt->as.enum_stmt.name.length, stmt->as.enum_stmt.name.start);
            break;
        case STMT_TRAIT:
            aot_emit(aot, "/* trait %.*s */", stmt->as.trait_stmt.name.length, stmt->as.trait_stmt.name.start);
            break;
        case STMT_COMPTIME:
            for (Stmt* s = stmt->as.comptime.body; s; s = s->next)
                aot_compile_stmt(aot, s);
            break;
        case STMT_MACRO_DEF:
            aot_emit(aot, "/* macro %.*s */", stmt->as.macro_def.name.length, stmt->as.macro_def.name.start);
            break;
        default:
            aot_emit(aot, "/* unsupported stmt type %d */", stmt->type);
            break;
    }
}

char* aot_compile_program(AotCompiler* aot, Stmt* program) {
    // Type inference pass
    aot_infer_types(aot, program);

    // Emit C prelude
    aot_emit(aot, "#define _POSIX_C_SOURCE 200809L");
    aot_emit(aot, "#include <stdio.h>");
    aot_emit(aot, "#include <stdlib.h>");
    aot_emit(aot, "#include <string.h>");
    aot_emit(aot, "#include <stdarg.h>");
    aot_emit(aot, "#include <math.h>");
    aot_emit(aot, "");
    aot_emit(aot, "/* Sage AOT Runtime */");
    aot_emit(aot, "typedef struct { int type; union { double number; int boolean; const char* string; void* ptr; } as; } SageValue;");
    aot_emit(aot, "enum { SAGE_NIL=0, SAGE_NUM=1, SAGE_BOOL=2, SAGE_STR=3 };");
    aot_emit(aot, "static SageValue sage_number(double n) { SageValue v; v.type=SAGE_NUM; v.as.number=n; return v; }");
    aot_emit(aot, "static SageValue sage_bool(int b) { SageValue v; v.type=SAGE_BOOL; v.as.boolean=b; return v; }");
    aot_emit(aot, "static SageValue sage_string(const char* s) { SageValue v; v.type=SAGE_STR; v.as.string=s; return v; }");
    aot_emit(aot, "static SageValue sage_nil(void) { SageValue v; v.type=SAGE_NIL; return v; }");
    aot_emit(aot, "static int sage_truthy(SageValue v) { if(v.type==SAGE_NIL) return 0; if(v.type==SAGE_BOOL) return v.as.boolean; if(v.type==SAGE_NUM) return v.as.number!=0.0; return 1; }");
    aot_emit(aot, "static SageValue sage_add(SageValue a, SageValue b) { if(a.type==SAGE_NUM&&b.type==SAGE_NUM) return sage_number(a.as.number+b.as.number); return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_sub(SageValue a, SageValue b) { return sage_number(a.as.number-b.as.number); }");
    aot_emit(aot, "static SageValue sage_mul(SageValue a, SageValue b) { return sage_number(a.as.number*b.as.number); }");
    aot_emit(aot, "static SageValue sage_div(SageValue a, SageValue b) { return sage_number(a.as.number/b.as.number); }");
    aot_emit(aot, "static SageValue sage_mod(SageValue a, SageValue b) { return sage_number(fmod(a.as.number,b.as.number)); }");
    aot_emit(aot, "static SageValue sage_eq(SageValue a, SageValue b) { if(a.type!=b.type) return sage_bool(0); if(a.type==SAGE_NUM) return sage_bool(a.as.number==b.as.number); if(a.type==SAGE_STR) return sage_bool(strcmp(a.as.string,b.as.string)==0); return sage_bool(0); }");
    aot_emit(aot, "static SageValue sage_neq(SageValue a, SageValue b) { return sage_bool(!sage_eq(a,b).as.boolean); }");
    aot_emit(aot, "static SageValue sage_gt(SageValue a, SageValue b) { return sage_bool(a.as.number>b.as.number); }");
    aot_emit(aot, "static SageValue sage_lt(SageValue a, SageValue b) { return sage_bool(a.as.number<b.as.number); }");
    aot_emit(aot, "static SageValue sage_strcat(SageValue a, SageValue b) { if(a.type!=SAGE_STR||b.type!=SAGE_STR) return sage_nil(); size_t la=strlen(a.as.string),lb=strlen(b.as.string); char* r=malloc(la+lb+1); memcpy(r,a.as.string,la); memcpy(r+la,b.as.string,lb); r[la+lb]=0; SageValue v; v.type=SAGE_STR; v.as.string=r; return v; }");
    aot_emit(aot, "");
    // Array/Dict/Index runtime support — must come before sage_print_value
    aot_emit(aot, "enum { SAGE_ARR=4, SAGE_DICT=5, SAGE_TUPLE=6 };");
    aot_emit(aot, "typedef struct { SageValue* elems; int count; int cap; } SageArr;");
    aot_emit(aot, "typedef struct { char** keys; SageValue* vals; int count; int cap; } SageDict;");
    aot_emit(aot, "static SageValue sage_array(int n, ...) { SageArr* a=malloc(sizeof(SageArr)); a->cap=n>4?n:4; a->count=n; a->elems=malloc(sizeof(SageValue)*a->cap); va_list ap; va_start(ap,n); for(int i=0;i<n;i++) a->elems[i]=va_arg(ap,SageValue); va_end(ap); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }");
    aot_emit(aot, "static int sage_array_len(SageValue v) { if(v.type==SAGE_ARR) return ((SageArr*)v.as.ptr)->count; return 0; }");
    aot_emit(aot, "static SageValue sage_array_get(SageValue v, int i) { if(v.type==SAGE_ARR){SageArr*a=(SageArr*)v.as.ptr; if(i>=0&&i<a->count) return a->elems[i];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_index(SageValue c, SageValue i) { if(c.type==SAGE_ARR) return sage_array_get(c,(int)i.as.number); if(c.type==SAGE_DICT){SageDict*d=(SageDict*)c.as.ptr; if(i.type==SAGE_STR) for(int k=0;k<d->count;k++) if(strcmp(d->keys[k],i.as.string)==0) return d->vals[k];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_index_set(SageValue c, SageValue i, SageValue val) { if(c.type==SAGE_ARR){SageArr*a=(SageArr*)c.as.ptr; int idx=(int)i.as.number; if(idx>=0&&idx<a->count) a->elems[idx]=val;} if(c.type==SAGE_DICT){SageDict*d=(SageDict*)c.as.ptr; if(i.type==SAGE_STR){for(int k=0;k<d->count;k++) if(strcmp(d->keys[k],i.as.string)==0){d->vals[k]=val;return val;} if(d->count>=d->cap){d->cap=d->cap?d->cap*2:4;d->keys=realloc(d->keys,sizeof(char*)*d->cap);d->vals=realloc(d->vals,sizeof(SageValue)*d->cap);}d->keys[d->count]=strdup(i.as.string);d->vals[d->count]=val;d->count++;}} return val; }");
    aot_emit(aot, "static SageValue sage_dict(int n, ...) { SageDict*d=calloc(1,sizeof(SageDict)); d->cap=n>2?n:2; d->keys=malloc(sizeof(char*)*d->cap); d->vals=malloc(sizeof(SageValue)*d->cap); va_list ap; va_start(ap,n); for(int i=0;i<n;i++){d->keys[i]=strdup(va_arg(ap,const char*));d->vals[i]=va_arg(ap,SageValue);d->count++;} va_end(ap); SageValue v; v.type=SAGE_DICT; v.as.ptr=d; return v; }");
    aot_emit(aot, "static SageValue sage_tuple(int n, ...) { SageArr*a=malloc(sizeof(SageArr)); a->cap=n; a->count=n; a->elems=malloc(sizeof(SageValue)*n); va_list ap; va_start(ap,n); for(int i=0;i<n;i++) a->elems[i]=va_arg(ap,SageValue); va_end(ap); SageValue v; v.type=SAGE_TUPLE; v.as.ptr=a; return v; }");
    aot_emit(aot, "static SageValue sage_slice(SageValue c, SageValue s, SageValue e) { if(c.type!=SAGE_ARR) return sage_nil(); SageArr*a=(SageArr*)c.as.ptr; int si=(int)s.as.number,ei=e.type==SAGE_NIL?a->count:(int)e.as.number; if(si<0)si=0;if(ei>a->count)ei=a->count; int n=ei-si;if(n<0)n=0; return sage_array(0); /* simplified */ }");
    aot_emit(aot, "static void sage_push(SageValue arr, SageValue val) { if(arr.type==SAGE_ARR){SageArr*a=(SageArr*)arr.as.ptr;if(a->count>=a->cap){a->cap=a->cap?a->cap*2:4;a->elems=realloc(a->elems,sizeof(SageValue)*a->cap);}a->elems[a->count++]=val;} }");
    aot_emit(aot, "static SageValue sage_pop(SageValue arr) { if(arr.type==SAGE_ARR){SageArr*a=(SageArr*)arr.as.ptr;if(a->count>0)return a->elems[--a->count];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_len(SageValue v) { if(v.type==SAGE_ARR) return sage_number(((SageArr*)v.as.ptr)->count); if(v.type==SAGE_STR) return sage_number(strlen(v.as.string)); if(v.type==SAGE_DICT) return sage_number(((SageDict*)v.as.ptr)->count); return sage_number(0); }");
    aot_emit(aot, "static SageValue sage_range(int n) { SageArr*a=malloc(sizeof(SageArr)); a->cap=n>4?n:4; a->count=n; a->elems=malloc(sizeof(SageValue)*a->cap); for(int i=0;i<n;i++) a->elems[i]=sage_number(i); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }");
    aot_emit(aot, "static SageValue sage_get_property(SageValue obj, const char* name) { if(obj.type==SAGE_DICT){SageDict*d=(SageDict*)obj.as.ptr; for(int i=0;i<d->count;i++) if(strcmp(d->keys[i],name)==0) return d->vals[i];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_dict_keys(SageValue d) { if(d.type!=SAGE_DICT) return sage_array(0); SageDict*dd=(SageDict*)d.as.ptr; SageArr*a=malloc(sizeof(SageArr)); a->cap=dd->count>4?dd->count:4; a->count=dd->count; a->elems=malloc(sizeof(SageValue)*a->cap); for(int i=0;i<dd->count;i++) a->elems[i]=sage_string(dd->keys[i]); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }");
    aot_emit(aot, "static SageValue sage_str(SageValue v) { char buf[256]; switch(v.type){case SAGE_NUM:{double d=v.as.number;if(d==(double)(long long)d&&d>=-1e15&&d<=1e15)snprintf(buf,sizeof(buf),\"%%lld\",(long long)d);else snprintf(buf,sizeof(buf),\"%%g\",d);break;}case SAGE_STR:return v;case SAGE_BOOL:return sage_string(v.as.boolean?\"true\":\"false\");default:return sage_string(\"nil\");}return sage_string(strdup(buf));}");
    aot_emit(aot, "static SageValue sage_tonumber(SageValue v) { if(v.type==SAGE_NUM)return v; if(v.type==SAGE_STR)return sage_number(atof(v.as.string)); return sage_number(0);}");
    aot_emit(aot, "static SageValue sage_type(SageValue v) { switch(v.type){case SAGE_NUM:return sage_string(\"number\");case SAGE_STR:return sage_string(\"string\");case SAGE_BOOL:return sage_string(\"bool\");case SAGE_ARR:return sage_string(\"array\");case SAGE_DICT:return sage_string(\"dict\");default:return sage_string(\"nil\");} }");
    // sage_print_value — MUST come after SageArr/SageDict definitions
    aot_emit(aot, "static void sage_print_value(SageValue v) { switch(v.type) { case SAGE_NUM: { double d=v.as.number; if(d==(double)(long long)d&&d>=-1e15&&d<=1e15) printf(\"%%lld\",(long long)d); else printf(\"%%g\",d); break; } case SAGE_BOOL: fputs(v.as.boolean?\"true\":\"false\",stdout); break; case SAGE_STR: fputs(v.as.string,stdout); break; case SAGE_ARR: { SageArr*a=(SageArr*)v.as.ptr; printf(\"[\"); for(int i=0;i<a->count;i++){if(i)printf(\", \");sage_print_value(a->elems[i]);} printf(\"]\"); break; } case SAGE_DICT: { SageDict*d=(SageDict*)v.as.ptr; printf(\"{\"); for(int i=0;i<d->count;i++){if(i)printf(\", \");printf(\"\\\"%%s\\\": \",d->keys[i]);sage_print_value(d->vals[i]);} printf(\"}\"); break; } default: fputs(\"nil\",stdout); } }");
    aot_emit(aot, "");

    // Forward-declare all procs (including async)
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = sanitize_name(s->as.proc.name.start, s->as.proc.name.length);
            aot_emit(aot, "static SageValue %s(int argc, SageValue* argv);", name);
            free(name);
        }
        if (s->type == STMT_ASYNC_PROC) {
            char* name = sanitize_name(s->as.async_proc.name.start, s->as.async_proc.name.length);
            aot_emit(aot, "static SageValue %s(int argc, SageValue* argv);", name);
            free(name);
        }
    }
    aot_emit(aot, "");

    // Emit proc definitions
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = sanitize_name(s->as.proc.name.start, s->as.proc.name.length);
            aot_emit(aot, "static SageValue %s(int argc, SageValue* argv) {", name);
            aot->indent++;
            // Bind params
            for (int i = 0; i < s->as.proc.param_count; i++) {
                char* pname = sanitize_name(s->as.proc.params[i].start, s->as.proc.params[i].length);
                aot_emit(aot, "SageValue %s = (argc > %d) ? argv[%d] : sage_nil();", pname, i, i);
                free(pname);
            }
            // Compile body
            for (Stmt* bs = s->as.proc.body; bs; bs = bs->next)
                aot_compile_stmt(aot, bs);
            aot_emit(aot, "return sage_nil();");
            aot->indent--;
            aot_emit(aot, "}");
            aot_emit(aot, "");
            free(name);
        }
    }

    aot_emit(aot, "int main(void) {");
    aot->indent++;

    // Compile all non-proc statements (procs already emitted above)
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_PROC || s->type == STMT_ASYNC_PROC) continue;
        aot_compile_stmt(aot, s);
    }

    aot_emit(aot, "return 0;");
    aot->indent--;
    aot_emit(aot, "}");

    // Join all lines
    int total = 0;
    for (int i = 0; i < aot->line_count; i++) total += strlen(aot->lines[i]) + 1;
    char* result = malloc(total + 1);
    result[0] = '\0';
    for (int i = 0; i < aot->line_count; i++) {
        strcat(result, aot->lines[i]);
        strcat(result, "\n");
    }
    return result;
}

int aot_write_c_file(AotCompiler* aot, const char* path) {
    (void)aot;
    (void)path;
    return 1;
}

int aot_compile_to_binary(AotCompiler* aot, const char* c_path, const char* bin_path) {
    (void)aot;
    const char* cc = "cc";
    pid_t pid = fork();
    if (pid < 0) return 0;
    if (pid == 0) {
        execlp(cc, cc, "-std=c11", "-O2", c_path, "-o", bin_path, "-lm", (char*)NULL);
        _exit(127);
    }
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
