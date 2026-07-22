#include "aot.h"
#include "gc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <math.h>

// ============================================================================
// AOT Compiler — Generates type-specialized C code
// ============================================================================

void aot_init(AotCompiler* aot, int opt_level) {
    memset(aot, 0, sizeof(AotCompiler));
    aot->opt_level = opt_level;
    aot->emit_guards = 0;
    aot->line_capacity = 10000;
    aot->lines = malloc(sizeof(char*) * aot->line_capacity);
    aot->proc_count = 0;
    
    // Register built-in native procs so EXPR_CALL can call them directly
    const char* builtins[] = {
        "s_print", "s_input", "s_len", "s_push", "s_pop", "s_range", 
        "s_keys", "s_typeof", "s_tonumber", "s_dict_has", "s_dict_delete",
        "s_readfile", "s_sys_exec", "s_time", "s_sleep", "s_getenv", "s_getch",
        "s_slice", "s_strip", "s_startswith", "s_endswith", "s_contains", "s_split",
        "s_join", "s_replace", "s_clock", "s_words", "s_sys_args_builtin", "s_chr", "s_ord",
        "s_stdout_write", "s_indexof", "s_lower", "s_upper",
        "s_listdir", "s_shell_exec", "s_connect", "s_send", "s_recv", "s_close",
        "s_isdir", "s_exists", "s_writefile", "s_writebytes", "s_appendbytes", 
        "s_readbytes", "s_remove", "s_mkdir", "s_spawn", "s_string_count",
        "s_string_repeat", "s_sendall", "s_gc_collect", "s_gc_disable",
        "s_io_readfile", "s_io_writefile", "s_io_writebytes", "s_io_appendbytes",
        "s_io_readbytes", "s_io_exists", "s_io_remove", "s_io_isdir", "s_io_mkdir",
        "s_io_listdir", "s_sys_getenv_native", "s_sys_exec", "s_exec"
    };
    for (int i = 0; i < sizeof(builtins)/sizeof(char*); i++) {
        aot->procs[aot->proc_count++] = strdup(builtins[i]);
    }
    aot->builtin_count = aot->proc_count;
}

void aot_free(AotCompiler* aot) {
    for (int i = 0; i < aot->line_count; i++) free(aot->lines[i]);
    free(aot->lines);
    for (int i = 0; i < aot->type_env.count; i++) free(aot->type_env.vars[i].name);
    free(aot->type_env.vars);
    memset(aot, 0, sizeof(AotCompiler));
}

static void aot_emit(AotCompiler* aot, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);

    // Determine required size for message
    va_list ap_copy;
    va_copy(ap_copy, ap);
    int msg_len = vsnprintf(NULL, 0, fmt, ap_copy);
    va_end(ap_copy);

    if (msg_len < 0) {
        va_end(ap);
        return;
    }

    int indent_len = aot->indent * 4;
    char* full_line = malloc(indent_len + msg_len + 1);
    if (!full_line) {
        va_end(ap);
        return;
    }

    // Apply indentation
    if (indent_len > 0) memset(full_line, ' ', indent_len);
    vsnprintf(full_line + indent_len, msg_len + 1, fmt, ap);
    va_end(ap);

    if (aot->line_count >= aot->line_capacity) {
        size_t new_cap = aot->line_capacity == 0 ? 256 : aot->line_capacity * 2;
        char **tmp = realloc(aot->lines, sizeof(char*) * new_cap);
        if (!tmp) {
            free(full_line);
            va_end(ap);
            return;
        }
        aot->lines = tmp;
        aot->line_capacity = new_cap;
    }
    aot->lines[aot->line_count++] = full_line;

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
            default:
                if ((unsigned char)s[i] < 0x20 || (unsigned char)s[i] == 0x7F) {
                    j += snprintf(out + j, 5, "\\x%02x", (unsigned char)s[i]);
                } else {
                    out[j++]=s[i];
                }
                break;
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

static char* sanitize_var_name(AotCompiler* aot, const char* start, int len) {
    char* name = sanitize_name(start, len);
    for (int i = 0; i < aot->builtin_count; i++) {
        if (strcmp(aot->procs[i], name) == 0) {
            char* vname = malloc(strlen(name) + 8);
            sprintf(vname, "v_%s", name);
            free(name);
            return vname;
        }
    }
    return name;
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
            char* name = sanitize_var_name(aot, expr->as.variable.name.start, expr->as.variable.name.length);
            
            // Check if this variable is actually a user-defined proc!
            int is_proc = 0;
            for (int i = aot->builtin_count; i < aot->proc_count; i++) {
                if (strcmp(aot->procs[i], name) == 0) {
                    is_proc = 1;
                    break;
                }
            }
            
            if (is_proc) {
                // Return it wrapped as a native function pointer so it can be passed around
                char buf[512];
                snprintf(buf, sizeof(buf), "val_native(%s)", name);
                free(name);
                return strdup(buf);
            }
            
            return name;
        }
        case EXPR_BINARY: {
            char* left = aot_compile_expr(aot, expr->as.binary.left);
            char* right = aot_compile_expr(aot, expr->as.binary.right);
            JitTypeTag lt = aot_infer_expr_type(aot, expr->as.binary.left);
            JitTypeTag rt = aot_infer_expr_type(aot, expr->as.binary.right);
            size_t sz = strlen(left)*2 + strlen(right)*2 + 128;
            char* result = malloc(sz);

            int op = expr->as.binary.op.type;
            // Type-specialized fast paths
            if (lt == JIT_TYPE_INT && rt == JIT_TYPE_INT) {
                const char* cop = NULL;
                switch (op) {
                    case TOKEN_PLUS:  cop = "+"; break;
                    case TOKEN_MINUS: cop = "-"; break;
                    case TOKEN_STAR:  cop = "*"; break;
                    case TOKEN_GT:  snprintf(result, sz, "sage_bool(%s.as.number > %s.as.number)", left, right); goto done;
                    case TOKEN_LT:  snprintf(result, sz, "sage_bool(%s.as.number < %s.as.number)", left, right); goto done;
                    case TOKEN_EQ:  snprintf(result, sz, "sage_bool(%s.as.number == %s.as.number)", left, right); goto done;
                    case TOKEN_NEQ: snprintf(result, sz, "sage_bool(%s.as.number != %s.as.number)", left, right); goto done;
                    case TOKEN_PERCENT: snprintf(result, sz, "sage_number(fmod(%s.as.number, %s.as.number))", left, right); goto done;
                    default: break;
                }
                if (cop) {
                    snprintf(result, sz, "sage_number(%s.as.number %s %s.as.number)", left, cop, right);
                    goto done;
                }
            }
            if (lt == JIT_TYPE_STRING && rt == JIT_TYPE_STRING && op == TOKEN_PLUS) {
                snprintf(result, sz, "sage_strcat(%s, %s)", left, right);
                goto done;
            }
            // Generic fallback — all operators
            switch (op) {
                case TOKEN_PLUS:    snprintf(result, sz, "sage_add(%s, %s)", left, right); break;
                case TOKEN_MINUS:   snprintf(result, sz, "sage_sub(%s, %s)", left, right); break;
                case TOKEN_STAR:    snprintf(result, sz, "sage_mul(%s, %s)", left, right); break;
                case TOKEN_SLASH:   snprintf(result, sz, "sage_div(%s, %s)", left, right); break;
                case TOKEN_PERCENT: snprintf(result, sz, "sage_mod(%s, %s)", left, right); break;
                case TOKEN_EQ:      snprintf(result, sz, "sage_eq(%s, %s)", left, right); break;
                case TOKEN_NEQ:     snprintf(result, sz, "sage_neq(%s, %s)", left, right); break;
                case TOKEN_GT:      snprintf(result, sz, "sage_gt(%s, %s)", left, right); break;
                case TOKEN_LT:      snprintf(result, sz, "sage_lt(%s, %s)", left, right); break;
                case TOKEN_GTE:     snprintf(result, sz, "sage_bool(%s.as.number >= %s.as.number)", left, right); break;
                case TOKEN_LTE:     snprintf(result, sz, "sage_bool(%s.as.number <= %s.as.number)", left, right); break;
                case TOKEN_AND:     snprintf(result, sz, "(sage_truthy(%s) ? %s : %s)", left, right, left); break;
                case TOKEN_OR:      snprintf(result, sz, "(sage_truthy(%s) ? %s : %s)", left, left, right); break;
                case TOKEN_NOT:     snprintf(result, sz, "sage_bool(!sage_truthy(%s))", left); break;
                case TOKEN_AMP:     snprintf(result, sz, "sage_number((double)((long long)%s.as.number & (long long)%s.as.number))", left, right); break;
                case TOKEN_PIPE:    snprintf(result, sz, "sage_number((double)((long long)%s.as.number | (long long)%s.as.number))", left, right); break;
                case TOKEN_CARET:   snprintf(result, sz, "sage_number((double)((long long)%s.as.number ^ (long long)%s.as.number))", left, right); break;
                case TOKEN_LSHIFT:  snprintf(result, sz, "sage_number((double)((unsigned long long)%s.as.number << (int)%s.as.number))", left, right); break;
                case TOKEN_RSHIFT:  snprintf(result, sz, "sage_number((double)((unsigned long long)%s.as.number >> (int)%s.as.number))", left, right); break;
                default:            snprintf(result, sz, "sage_add(%s, %s)", left, right); break;
            }
            done:
            free(left);
            free(right);
            return result;
        }
        case EXPR_CALL: {
            const char* raw = NULL;
            int rawlen = 0;
            if (expr->as.call.callee && expr->as.call.callee->type == EXPR_VARIABLE) {
                raw = expr->as.call.callee->as.variable.name.start;
                rawlen = expr->as.call.callee->as.variable.name.length;
            } else if (expr->as.call.callee && expr->as.call.callee->type == EXPR_GET) {
                if (expr->as.call.callee->as.get.object->type == EXPR_VARIABLE) {
                    // For sys.stdout_write, raw becomes "stdout_write"
                    raw = expr->as.call.callee->as.get.property.start;
                    rawlen = expr->as.call.callee->as.get.property.length;
                }
            }
            if (raw) {
                int argc = expr->as.call.arg_count;

                // Builtin function mapping — direct C calls for known builtins
                #define BUILTIN_MATCH(name) (rawlen == (int)strlen(name) && memcmp(raw, name, rawlen) == 0)
                #define EMIT_1(cfn) do { char*a0=aot_compile_expr(aot,expr->as.call.args[0]); size_t sz=strlen(a0)+64; char*b=malloc(sz); snprintf(b,sz,"%s(%s)",cfn,a0); free(a0); return b; } while(0)
                #define EMIT_2(cfn) do { char*a0=aot_compile_expr(aot,expr->as.call.args[0]); char*a1=aot_compile_expr(aot,expr->as.call.args[1]); size_t sz=strlen(a0)+strlen(a1)+64; char*b=malloc(sz); snprintf(b,sz,"%s(%s, %s)",cfn,a0,a1); free(a0);free(a1); return b; } while(0)

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
                char** compiled_args = argc > 0 ? malloc(sizeof(char*) * argc) : NULL;
                if (argc > 0 && !compiled_args) {
                    free(fname);
                    return strdup("sage_nil()");
                }
                size_t total_len = strlen(fname) + 128; // preamble, postamble, and call logic
                for (int i = 0; i < argc; i++) {
                    compiled_args[i] = aot_compile_expr(aot, expr->as.call.args[i]);
                    total_len += strlen(compiled_args[i]) + 48; // "_args[NNNNN] = ...; "
                }

                char* buf = malloc(total_len);
                if (!buf) {
                    free(fname);
                    for (int i = 0; i < argc; i++) free(compiled_args[i]);
                    free(compiled_args);
                    return strdup("sage_nil()");
                }

                int pos = sprintf(buf, "({ SageValue _args[%d]; ", argc > 0 ? argc : 1);
                for (int i = 0; i < argc; i++) {
                    pos += sprintf(buf + pos, "_args[%d] = %s; ", i, compiled_args[i]);
                    free(compiled_args[i]);
                }
                free(compiled_args);
                
                // Check if fname is a known top-level proc
                int is_proc = 0;
                for (int i = 0; i < aot->proc_count; i++) {
                    if (strcmp(aot->procs[i], fname) == 0) {
                        is_proc = 1;
                        break;
                    }
                }
                
                if (is_proc) {
                    pos += sprintf(buf + pos, "%s(%d, _args); })", fname, argc);
                } else if (expr->as.call.callee && expr->as.call.callee->type == EXPR_GET) {
                    char* callee_expr = aot_compile_expr(aot, expr->as.call.callee);
                    pos += sprintf(buf + pos, "sage_call(%s, %d, _args); })", callee_expr, argc);
                    free(callee_expr);
                } else {
                    pos += sprintf(buf + pos, "sage_call(%s, %d, _args); })", fname, argc);
                }
                
                free(fname);
                return buf;
            }
            char* callee = aot_compile_expr(aot, expr->as.call.callee);
            size_t callee_len = strlen(callee);
            char* buf = malloc(callee_len + 64);
            if (buf) sprintf(buf, "sage_nil() /* unsupported call: %s */", callee);
            free(callee);
            return buf ? buf : strdup("sage_nil()");
        }
        case EXPR_SET: {
            // Variable assignment: name = value
            if (expr->as.set.object == NULL && expr->as.set.property.start) {
                char* name = sanitize_name(expr->as.set.property.start, expr->as.set.property.length);
                char* val = aot_compile_expr(aot, expr->as.set.value);
                char* buf = malloc(strlen(name) + strlen(val) + 16);
                if (buf) {
                    sprintf(buf, "(%s = %s)", name, val);
                } else {
                    fprintf(stderr, "Error: Out of memory in AOT expression\n");
                }
                free(name);
                free(val);
                return buf ? buf : strdup("sage_nil()");
            }
            return strdup("sage_nil()");
        }
        case EXPR_ARRAY: {
            int n = expr->as.array.count;
            char** compiled_elems = n > 0 ? malloc(sizeof(char*) * n) : NULL;
            if (n > 0 && !compiled_elems) return strdup("sage_nil()");
            size_t total_len = 32; // "sage_array(N" + ")"
            for (int i = 0; i < n; i++) {
                compiled_elems[i] = aot_compile_expr(aot, expr->as.array.elements[i]);
                total_len += strlen(compiled_elems[i]) + 4; // ", " + elem
            }

            char* buf = malloc(total_len);
            if (!buf) {
                for (int i = 0; i < n; i++) free(compiled_elems[i]);
                free(compiled_elems);
                return strdup("sage_nil()");
            }

            int pos = sprintf(buf, "sage_array(%d", n);
            for (int i = 0; i < n; i++) {
                pos += sprintf(buf + pos, ", %s", compiled_elems[i]);
                free(compiled_elems[i]);
            }
            free(compiled_elems);
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
            char** compiled_keys = n > 0 ? malloc(sizeof(char*) * n) : NULL;
            char** compiled_vals = n > 0 ? malloc(sizeof(char*) * n) : NULL;
            if (n > 0 && (!compiled_keys || !compiled_vals)) {
                free(compiled_keys); free(compiled_vals);
                return strdup("sage_nil()");
            }
            size_t total_len = 32; // "sage_dict(N" + ")"
            for (int i = 0; i < n; i++) {
                compiled_keys[i] = escape_c_str(expr->as.dict.keys[i]);
                compiled_vals[i] = aot_compile_expr(aot, expr->as.dict.values[i]);
                total_len += strlen(compiled_keys[i]) + strlen(compiled_vals[i]) + 8; // ", \"...\", "
            }

            char* buf = malloc(total_len);
            if (!buf) {
                for (int i = 0; i < n; i++) { free(compiled_keys[i]); free(compiled_vals[i]); }
                free(compiled_keys); free(compiled_vals);
                return strdup("sage_nil()");
            }

            int pos = sprintf(buf, "sage_dict(%d", n);
            for (int i = 0; i < n; i++) {
                pos += sprintf(buf + pos, ", \"%s\", %s", compiled_keys[i], compiled_vals[i]);
                free(compiled_keys[i]); free(compiled_vals[i]);
            }
            free(compiled_keys); free(compiled_vals);
            pos += sprintf(buf + pos, ")");
            return buf;
        }
        case EXPR_GET: {
            if (expr->as.get.object->type == EXPR_VARIABLE) {
                const char* obj_name = expr->as.get.object->as.variable.name.start;
                int obj_len = expr->as.get.object->as.variable.name.length;
                // Check if the object is a known module alias
                if ((obj_len == 3 && strncmp(obj_name, "cfg", 3) == 0) ||
                    (obj_len == 3 && strncmp(obj_name, "tui", 3) == 0) ||
                    (obj_len == 5 && strncmp(obj_name, "agent", 5) == 0) ||
                    (obj_len == 8 && strncmp(obj_name, "provider", 8) == 0) ||
                    (obj_len == 6 && strncmp(obj_name, "router", 6) == 0) ||
                    (obj_len == 5 && strncmp(obj_name, "tools", 5) == 0) ||
                    (obj_len == 6 && strncmp(obj_name, "skills", 6) == 0) ||
                    (obj_len == 6 && strncmp(obj_name, "ollama", 6) == 0) ||
                    (obj_len == 12 && strncmp(obj_name, "bench_runner", 12) == 0) ||
                    (obj_len == 3 && strncmp(obj_name, "sys", 3) == 0) ||
                    (obj_len == 2 && strncmp(obj_name, "io", 2) == 0) ||
                    (obj_len == 3 && strncmp(obj_name, "tcp", 3) == 0) ||
                    (obj_len == 4 && strncmp(obj_name, "json", 4) == 0) ||
                    (obj_len == 8 && strncmp(obj_name, "compiler", 8) == 0) ||
                    (obj_len == 5 && strncmp(obj_name, "bench", 5) == 0)) {
                    
                    // It's a module variable access! Map directly to the global variable.
                    char* prop = sanitize_name(expr->as.get.property.start, expr->as.get.property.length);
                    
                    int is_proc = 0;
                    for (int i = 0; i < aot->proc_count; i++) {
                        if (strcmp(aot->procs[i], prop) == 0) {
                            is_proc = 1;
                            break;
                        }
                    }
                    
                    char* buf;
                    if (is_proc) {
                        buf = malloc(strlen(prop) + 16);
                        sprintf(buf, "val_native(%s)", prop);
                        free(prop);
                    } else {
                        buf = prop; // already malloced
                    }
                    return buf;
                }
            }

            char* obj = aot_compile_expr(aot, expr->as.get.object);
            char* name = sanitize_name(expr->as.get.property.start, expr->as.get.property.length);
            // Revert sanitize_name's "s_" prefix for string property keys
            char* clean_name = strdup(name + 2);
            char* buf = malloc(strlen(obj) + strlen(clean_name) + 32);
            if (buf) sprintf(buf, "sage_get_property(%s, \"%s\")", obj, clean_name);
            free(obj);
            free(name);
            free(clean_name);
            return buf ? buf : strdup("sage_nil()");
        }
        case EXPR_SLICE: {
            char* obj = aot_compile_expr(aot, expr->as.slice.array);
            char* start = expr->as.slice.start ? aot_compile_expr(aot, expr->as.slice.start) : strdup("sage_number(0)");
            char* end = expr->as.slice.end ? aot_compile_expr(aot, expr->as.slice.end) : strdup("sage_nil()");
            char* buf = malloc(strlen(obj) + strlen(start) + strlen(end) + 48);
            if (buf) {
                sprintf(buf, "sage_slice(%s, %s, %s)", obj, start, end);
            } else {
                fprintf(stderr, "Error: Out of memory in AOT slice\n");
            }
            free(obj); free(start); free(end);
            return buf ? buf : strdup("sage_nil()");
        }
        case EXPR_TUPLE: {
            int n = expr->as.tuple.count;
            char** compiled_elems = n > 0 ? malloc(sizeof(char*) * n) : NULL;
            if (n > 0 && !compiled_elems) return strdup("sage_nil()");
            size_t total_len = 32; // "sage_tuple(N" + ")"
            for (int i = 0; i < n; i++) {
                compiled_elems[i] = aot_compile_expr(aot, expr->as.tuple.elements[i]);
                total_len += strlen(compiled_elems[i]) + 4; // ", " + elem
            }

            char* buf = malloc(total_len);
            if (!buf) {
                for (int i = 0; i < n; i++) free(compiled_elems[i]);
                free(compiled_elems);
                return strdup("sage_nil()");
            }

            int pos = sprintf(buf, "sage_tuple(%d", n);
            for (int i = 0; i < n; i++) {
                pos += sprintf(buf + pos, ", %s", compiled_elems[i]);
                free(compiled_elems[i]);
            }
            free(compiled_elems);
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
            char* name = sanitize_var_name(aot, stmt->as.let.name.start, stmt->as.let.name.length);
            int is_top = (aot->in_main && aot->indent == 1);
            if (stmt->as.let.initializer) {
                char* val = aot_compile_expr(aot, stmt->as.let.initializer);
                if (is_top) {
                    aot_emit(aot, "%s = %s;", name, val);
                } else {
                    aot_emit(aot, "SageValue %s = %s;", name, val);
                }
                free(val);
            } else {
                if (is_top) {
                    aot_emit(aot, "%s = sage_nil();", name);
                } else {
                    aot_emit(aot, "SageValue %s = sage_nil();", name);
                }
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
            char* var = sanitize_var_name(aot, stmt->as.for_stmt.variable.start, stmt->as.for_stmt.variable.length);
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
        case STMT_PROC: {
            char* name = sanitize_name(stmt->as.proc.name.start, stmt->as.proc.name.length);
            aot_emit(aot, "static SageValue %s(int argc, SageValue* argv) {", name);
            aot->indent++;
            for (int i = 0; i < stmt->as.proc.param_count; i++) {
                char* pname = sanitize_name(stmt->as.proc.params[i].start, stmt->as.proc.params[i].length);
                aot_emit(aot, "SageValue %s = (argc > %d) ? argv[%d] : sage_nil();", pname, i, i);
                free(pname);
            }
            for (Stmt* bs = stmt->as.proc.body; bs; bs = bs->next)
                aot_compile_stmt(aot, bs);
            aot_emit(aot, "return sage_nil();");
            aot->indent--;
            aot_emit(aot, "}");
            aot_emit(aot, "");
            free(name);
            break;
        }
        case STMT_IMPORT:
            aot_emit(aot, "/* import %s */", stmt->as.import.module_name ? stmt->as.import.module_name : "?");
            break;
        case STMT_CLASS: {
            char* cname = sanitize_name(stmt->as.class_stmt.name.start, stmt->as.class_stmt.name.length);
            for (Stmt* m = stmt->as.class_stmt.methods; m; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = sanitize_name(m->as.proc.name.start, m->as.proc.name.length);
                    aot_emit(aot, "static SageValue %s_%s(int argc, SageValue* argv) {", cname, mname + 2);
                    aot->indent++;
                    aot_emit(aot, "SageValue s_self = s_current_self;");
                    for (int i = 0; i < m->as.proc.param_count; i++) {
                        char* pn = sanitize_var_name(aot, m->as.proc.params[i].start, m->as.proc.params[i].length);
                        if (strcmp(pn, "s_self") == 0 || strcmp(pn, "v_s_self") == 0) {
                            aot_emit(aot, "if (argc > %d && sage_truthy(argv[%d])) s_self = argv[%d];", i, i, i);
                        } else {
                            aot_emit(aot, "SageValue %s = (argc > %d) ? argv[%d] : sage_nil();", pn, i, i);
                        }
                        free(pn);
                    }
                    for (Stmt* bs = m->as.proc.body; bs; bs = bs->next)
                        aot_compile_stmt(aot, bs);
                    aot_emit(aot, "return sage_nil();");
                    aot->indent--;
                    aot_emit(aot, "}");
                    aot_emit(aot, "");
                    free(mname);
                }
            }

            aot_emit(aot, "static SageValue %s(int argc, SageValue* argv) {", cname);
            aot->indent++;
            aot_emit(aot, "SageValue obj = sage_dict(0);");
            for (Stmt* m = stmt->as.class_stmt.methods; m; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = sanitize_name(m->as.proc.name.start, m->as.proc.name.length);
                    char raw_mname[256];
                    snprintf(raw_mname, sizeof(raw_mname), "%.*s", m->as.proc.name.length, m->as.proc.name.start);
                    aot_emit(aot, "sage_index_set(obj, sage_string(\"%s\"), val_native(%s_%s));", raw_mname, cname, mname + 2);
                    free(mname);
                }
            }
            int has_init = 0;
            for (Stmt* m = stmt->as.class_stmt.methods; m; m = m->next) {
                if (m->type == STMT_PROC && m->as.proc.name.length == 4 && memcmp(m->as.proc.name.start, "init", 4) == 0) {
                    has_init = 1;
                    break;
                }
            }
            if (has_init) {
                aot_emit(aot, "s_current_self = obj;");
                aot_emit(aot, "%s_init(argc, argv);", cname);
            }
            aot_emit(aot, "return obj;");
            aot->indent--;
            aot_emit(aot, "}");
            aot_emit(aot, "");
            free(cname);
            break;
        }
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

static void aot_forward_declare_stmt(AotCompiler* aot, Stmt* s) {
    if (!s) return;
    for (Stmt* curr = s; curr; curr = curr->next) {
        if (curr->type == STMT_PROC || curr->type == STMT_ASYNC_PROC) {
            char* name = sanitize_name(curr->type == STMT_PROC ? curr->as.proc.name.start : curr->as.async_proc.name.start, 
                                       curr->type == STMT_PROC ? curr->as.proc.name.length : curr->as.async_proc.name.length);
            int already = 0;
            for (int j = 0; j < aot->proc_count; j++) {
                if (strcmp(aot->procs[j], name) == 0) { already = 1; break; }
            }
            if (!already) {
                aot_emit(aot, "static SageValue %s(int argc, SageValue* argv);", name);
                if (aot->proc_count < 1024) aot->procs[aot->proc_count++] = strdup(name);
            }
            free(name);
        } else if (curr->type == STMT_LET) {
            char* name = sanitize_var_name(aot, curr->as.let.name.start, curr->as.let.name.length);
            int conflict = 0;
            for (int j = 0; j < aot->proc_count; j++) {
                if (strcmp(aot->procs[j], name) == 0) { conflict = 1; break; }
            }
            if (!conflict) {
                aot_emit(aot, "static SageValue %s;", name);
            }
            free(name);
        } else if (curr->type == STMT_BLOCK) {
            aot_forward_declare_stmt(aot, curr->as.block.statements);
        } else if (curr->type == STMT_COMPTIME) {
            aot_forward_declare_stmt(aot, curr->as.comptime.body);
        } else if (curr->type == STMT_CLASS) {
            char* cname = sanitize_name(curr->as.class_stmt.name.start, curr->as.class_stmt.name.length);
            int already = 0;
            for (int j = 0; j < aot->proc_count; j++) {
                if (strcmp(aot->procs[j], cname) == 0) { already = 1; break; }
            }
            if (!already) {
                aot_emit(aot, "static SageValue %s(int argc, SageValue* argv);", cname);
                if (aot->proc_count < 1024) aot->procs[aot->proc_count++] = strdup(cname);
            }
            for (Stmt* m = curr->as.class_stmt.methods; m; m = m->next) {
                if (m->type == STMT_PROC) {
                    char* mname = sanitize_name(m->as.proc.name.start, m->as.proc.name.length);
                    char fullm_s[512];
                    snprintf(fullm_s, sizeof(fullm_s), "%s_%s", cname, mname + 2);
                    int malready = 0;
                    for (int j = 0; j < aot->proc_count; j++) {
                        if (strcmp(aot->procs[j], fullm_s) == 0) { malready = 1; break; }
                    }
                    if (!malready) {
                        aot_emit(aot, "static SageValue %s(int argc, SageValue* argv);", fullm_s);
                        if (aot->proc_count < 1024) aot->procs[aot->proc_count++] = strdup(fullm_s);
                    }
                    free(mname);
                }
            }
            free(cname);
        }
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
    aot_emit(aot, "#include <sys/time.h>");
    aot_emit(aot, "");
    aot_emit(aot, "/* Sage AOT Runtime */");
    aot_emit(aot, "typedef struct { int type; union { double number; int boolean; const char* string; void* ptr; } as; } SageValue;");
    aot_emit(aot, "enum { SAGE_NIL=0, SAGE_NUM=1, SAGE_BOOL=2, SAGE_STR=3 };");
    aot_emit(aot, "static SageValue sage_number(double n) { SageValue v; v.type=SAGE_NUM; v.as.number=n; return v; }");
    aot_emit(aot, "static SageValue sage_bool(int b) { SageValue v; v.type=SAGE_BOOL; v.as.boolean=b; return v; }");
    aot_emit(aot, "static SageValue sage_string(const char* s) { SageValue v; v.type=SAGE_STR; v.as.string=s; return v; }");
    aot_emit(aot, "static SageValue sage_nil(void) { SageValue v; v.type=SAGE_NIL; return v; }");
    aot_emit(aot, "static int sage_truthy(SageValue v) { if(v.type==SAGE_NIL) return 0; if(v.type==SAGE_BOOL) return v.as.boolean; if(v.type==SAGE_NUM) return v.as.number!=0.0; return 1; }");
    aot_emit(aot, "static SageValue sage_str(SageValue v);  /* forward decl */");
    aot_emit(aot, "static SageValue sage_strcat(SageValue a, SageValue b);  /* forward decl */");
    aot_emit(aot, "static void sage_print_value(SageValue v);  /* forward decl */");
    aot_emit(aot, "static SageValue sage_add(SageValue a, SageValue b) { if(a.type==SAGE_NUM&&b.type==SAGE_NUM) return sage_number(a.as.number+b.as.number); if(a.type==SAGE_STR&&b.type==SAGE_STR) return sage_strcat(a,b); if(a.type==SAGE_STR||b.type==SAGE_STR){SageValue sa=sage_str(a),sb=sage_str(b);return sage_strcat(sa,sb);} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_sub(SageValue a, SageValue b) { return sage_number(a.as.number-b.as.number); }");
    aot_emit(aot, "static SageValue sage_mul(SageValue a, SageValue b) { return sage_number(a.as.number*b.as.number); }");
    aot_emit(aot, "static SageValue sage_div(SageValue a, SageValue b) { return sage_number(a.as.number/b.as.number); }");
    aot_emit(aot, "static SageValue sage_mod(SageValue a, SageValue b) { return sage_number(fmod(a.as.number,b.as.number)); }");
    aot_emit(aot, "static SageValue sage_eq(SageValue a, SageValue b) { if(a.type!=b.type) return sage_bool(0); if(a.type==SAGE_NIL) return sage_bool(1); if(a.type==SAGE_BOOL) return sage_bool(a.as.boolean==b.as.boolean); if(a.type==SAGE_NUM) return sage_bool(a.as.number==b.as.number); if(a.type==SAGE_STR) return sage_bool(strcmp(a.as.string,b.as.string)==0); return sage_bool(0); }");
    aot_emit(aot, "static SageValue sage_neq(SageValue a, SageValue b) { return sage_bool(!sage_eq(a,b).as.boolean); }");
    aot_emit(aot, "static SageValue sage_gt(SageValue a, SageValue b) { return sage_bool(a.as.number>b.as.number); }");
    aot_emit(aot, "static SageValue sage_lt(SageValue a, SageValue b) { return sage_bool(a.as.number<b.as.number); }");
    aot_emit(aot, "static SageValue sage_strcat(SageValue a, SageValue b) { if(a.type!=SAGE_STR||b.type!=SAGE_STR) return sage_nil(); size_t la=strlen(a.as.string),lb=strlen(b.as.string); char* r=malloc(la+lb+1); memcpy(r,a.as.string,la); memcpy(r+la,b.as.string,lb); r[la+lb]=0; SageValue v; v.type=SAGE_STR; v.as.string=r; return v; }");
    aot_emit(aot, "");
    // Array/Dict/Index runtime support — must come before sage_print_value
    aot_emit(aot, "enum { SAGE_ARR=4, SAGE_DICT=5, SAGE_TUPLE=6, SAGE_NATIVE=7 };");
    aot_emit(aot, "typedef SageValue (*SageNativeFn)(int, SageValue*);");
    aot_emit(aot, "typedef struct { SageValue* elems; int count; int cap; } SageArr;");
    aot_emit(aot, "typedef struct { char** keys; SageValue* vals; int count; int cap; } SageDict;");
    aot_emit(aot, "static SageValue val_native(SageNativeFn f) { SageValue v; v.type=SAGE_NATIVE; v.as.ptr=f; return v; }");
    aot_emit(aot, "static SageValue sage_call(SageValue f, int c, SageValue* a) { if(f.type==SAGE_NATIVE) return ((SageNativeFn)f.as.ptr)(c,a); return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_array(int n, ...) { SageArr* a=malloc(sizeof(SageArr)); a->cap=n>4?n:4; a->count=n; a->elems=malloc(sizeof(SageValue)*a->cap); va_list ap; va_start(ap,n); for(int i=0;i<n;i++) a->elems[i]=va_arg(ap,SageValue); va_end(ap); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }");
    aot_emit(aot, "static int sage_array_len(SageValue v) { if(v.type==SAGE_ARR) return ((SageArr*)v.as.ptr)->count; return 0; }");
    aot_emit(aot, "static SageValue sage_array_get(SageValue v, int i) { if(v.type==SAGE_ARR || v.type==SAGE_TUPLE){SageArr*a=(SageArr*)v.as.ptr; if(i>=0&&i<a->count) return a->elems[i];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_index(SageValue c, SageValue i) { if(c.type==SAGE_ARR || c.type==SAGE_TUPLE) return sage_array_get(c,(int)i.as.number); if(c.type==SAGE_DICT){SageDict*d=(SageDict*)c.as.ptr; if(i.type==SAGE_STR) for(int k=0;k<d->count;k++) if(strcmp(d->keys[k],i.as.string)==0) return d->vals[k];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_index_set(SageValue c, SageValue i, SageValue val) { if(c.type==SAGE_ARR){SageArr*a=(SageArr*)c.as.ptr; int idx=(int)i.as.number; if(idx>=0&&idx<a->count) a->elems[idx]=val;} if(c.type==SAGE_DICT){SageDict*d=(SageDict*)c.as.ptr; if(i.type==SAGE_STR){for(int k=0;k<d->count;k++) if(strcmp(d->keys[k],i.as.string)==0){d->vals[k]=val;return val;} if(d->count>=d->cap){d->cap=d->cap?d->cap*2:4;d->keys=realloc(d->keys,sizeof(char*)*d->cap);d->vals=realloc(d->vals,sizeof(SageValue)*d->cap);}d->keys[d->count]=strdup(i.as.string);d->vals[d->count]=val;d->count++;}} return val; }");
    aot_emit(aot, "static SageValue sage_dict(int n, ...) { SageDict*d=calloc(1,sizeof(SageDict)); d->cap=n>2?n:2; d->keys=malloc(sizeof(char*)*d->cap); d->vals=malloc(sizeof(SageValue)*d->cap); va_list ap; va_start(ap,n); for(int i=0;i<n;i++){d->keys[i]=strdup(va_arg(ap,const char*));d->vals[i]=va_arg(ap,SageValue);d->count++;} va_end(ap); SageValue v; v.type=SAGE_DICT; v.as.ptr=d; return v; }");
    aot_emit(aot, "static SageValue sage_tuple(int n, ...) { SageArr*a=malloc(sizeof(SageArr)); a->cap=n; a->count=n; a->elems=malloc(sizeof(SageValue)*n); va_list ap; va_start(ap,n); for(int i=0;i<n;i++) a->elems[i]=va_arg(ap,SageValue); va_end(ap); SageValue v; v.type=SAGE_TUPLE; v.as.ptr=a; return v; }");
    aot_emit(aot, "static SageValue sage_slice(SageValue c, SageValue s, SageValue e) { if(c.type!=SAGE_ARR) return sage_nil(); SageArr*a=(SageArr*)c.as.ptr; int si=(int)s.as.number,ei=e.type==SAGE_NIL?a->count:(int)e.as.number; if(si<0)si=0;if(ei>a->count)ei=a->count; int n=ei-si;if(n<0)n=0; return sage_array(0); /* simplified */ }");

    aot_emit(aot, "static SageValue sage_pop(SageValue arr) { if(arr.type==SAGE_ARR){SageArr*a=(SageArr*)arr.as.ptr;if(a->count>0)return a->elems[--a->count];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_len(SageValue v) { if(v.type==SAGE_ARR) return sage_number(((SageArr*)v.as.ptr)->count); if(v.type==SAGE_STR) return sage_number(strlen(v.as.string)); if(v.type==SAGE_DICT) return sage_number(((SageDict*)v.as.ptr)->count); return sage_number(0); }");
    aot_emit(aot, "static SageValue sage_range(int n) { SageArr*a=malloc(sizeof(SageArr)); a->cap=n>4?n:4; a->count=n; a->elems=malloc(sizeof(SageValue)*a->cap); for(int i=0;i<n;i++) a->elems[i]=sage_number(i); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }");
    aot_emit(aot, "static SageValue sage_get_property(SageValue obj, const char* name) { if(obj.type==SAGE_DICT){SageDict*d=(SageDict*)obj.as.ptr; for(int i=0;i<d->count;i++) if(strcmp(d->keys[i],name)==0) return d->vals[i];} return sage_nil(); }");
    aot_emit(aot, "static SageValue sage_dict_keys(SageValue d) { if(d.type!=SAGE_DICT) return sage_array(0); SageDict*dd=(SageDict*)d.as.ptr; SageArr*a=malloc(sizeof(SageArr)); a->cap=dd->count>4?dd->count:4; a->count=dd->count; a->elems=malloc(sizeof(SageValue)*a->cap); for(int i=0;i<dd->count;i++) a->elems[i]=sage_string(dd->keys[i]); SageValue v; v.type=SAGE_ARR; v.as.ptr=a; return v; }");
    aot_emit(aot, "static SageValue sage_str(SageValue v) { char buf[256]; switch(v.type){case SAGE_NUM:{double d=v.as.number;if(d==(double)(long long)d&&d>=-1e15&&d<=1e15)snprintf(buf,sizeof(buf),\"%%lld\",(long long)d);else snprintf(buf,sizeof(buf),\"%%g\",d);break;}case SAGE_STR:return v;case SAGE_BOOL:return sage_string(v.as.boolean?\"true\":\"false\");default:return sage_string(\"nil\");}return sage_string(strdup(buf));}");
    aot_emit(aot, "static SageValue sage_tonumber(SageValue v) { if(v.type==SAGE_NUM)return v; if(v.type==SAGE_STR)return sage_number(atof(v.as.string)); return sage_number(0);}");
    aot_emit(aot, "static SageValue sage_type(SageValue v) { switch(v.type){case SAGE_NUM:return sage_string(\"number\");case SAGE_STR:return sage_string(\"string\");case SAGE_BOOL:return sage_string(\"bool\");case SAGE_ARR:return sage_string(\"array\");case SAGE_DICT:return sage_string(\"dict\");default:return sage_string(\"nil\");} }");

    aot_emit(aot, "static SageValue s_getch(int c, SageValue* a) { (void)c; (void)a; int ch=getchar(); if(ch==EOF)return sage_string(\"\"); char b[2]={(char)ch,0}; return sage_string(strdup(b)); }");

    aot_emit(aot, "static void sage_push(SageValue arr, SageValue val) { if(arr.type==SAGE_ARR){SageArr*a=(SageArr*)arr.as.ptr;if(a->count>=a->cap){a->cap=a->cap?a->cap*2:4;a->elems=realloc(a->elems,sizeof(SageValue)*a->cap);}a->elems[a->count++]=val;} }");
    aot_emit(aot, "static SageValue s_current_self;");
    aot_emit(aot, "static SageValue s_dict_has(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_DICT||a[1].type!=SAGE_STR)return sage_bool(0); SageDict*d=(SageDict*)a[0].as.ptr; for(int i=0;i<d->count;i++)if(strcmp(d->keys[i],a[1].as.string)==0)return sage_bool(1); return sage_bool(0); }");
    aot_emit(aot, "static SageValue s_dict_delete(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_DICT||a[1].type!=SAGE_STR)return sage_nil(); SageDict*d=(SageDict*)a[0].as.ptr; for(int i=0;i<d->count;i++)if(strcmp(d->keys[i],a[1].as.string)==0){SageValue v=d->vals[i];for(int j=i;j<d->count-1;j++){d->keys[j]=d->keys[j+1];d->vals[j]=d->vals[j+1];}d->count--;return v;} return sage_nil(); }");
    aot_emit(aot, "static SageValue s_gc_collect(int c, SageValue* a) { (void)c; (void)a; return sage_nil(); }");
    aot_emit(aot, "static SageValue s_lower(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_string(\"\"); char*s=strdup(a[0].as.string); for(int i=0;s[i];i++)if(s[i]>='A'&&s[i]<='Z')s[i]+=32; SageValue v=sage_string(s); free(s); return v; }");
    aot_emit(aot, "static SageValue s_shell_exec(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_string(\"\"); FILE*f=popen(a[0].as.string,\"r\"); if(!f)return sage_string(\"\"); char buf[4096]; char*out=NULL; size_t slen=0; while(fgets(buf,sizeof(buf),f)){size_t l=strlen(buf); out=realloc(out,slen+l+1); memcpy(out+slen,buf,l); slen+=l; out[slen]=0;} pclose(f); SageValue v=sage_string(out?out:\"\"); free(out); return v; }");
    aot_emit(aot, "static SageValue s_stdout_write(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_nil(); fputs(a[0].as.string, stdout); fflush(stdout); return sage_nil(); }");
    aot_emit(aot, "#include <sys/socket.h>");
    aot_emit(aot, "#include <netinet/in.h>");
    aot_emit(aot, "#include <arpa/inet.h>");
    aot_emit(aot, "#include <netdb.h>");
    aot_emit(aot, "#include <unistd.h>");
    aot_emit(aot, "#include <time.h>");
    aot_emit(aot, "static SageValue s_connect(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_NUM)return sage_number(-1); int fd=socket(AF_INET,SOCK_STREAM,0); if(fd<0)return sage_number(-1); struct hostent*h=gethostbyname(a[0].as.string); if(!h){close(fd);return sage_number(-1);} struct sockaddr_in saddr; memset(&saddr,0,sizeof(saddr)); saddr.sin_family=AF_INET; saddr.sin_port=htons((int)a[1].as.number); memcpy(&saddr.sin_addr.s_addr,h->h_addr_list[0],h->h_length); if(connect(fd,(struct sockaddr*)&saddr,sizeof(saddr))<0){close(fd);return sage_number(-1);} return sage_number(fd); }");
    aot_emit(aot, "static SageValue s_send(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_NUM||a[1].type!=SAGE_STR)return sage_number(-1); int fd=(int)a[0].as.number; const char*str=a[1].as.string; int len=strlen(str); int s=send(fd,str,len,0); return sage_number(s); }");
    aot_emit(aot, "static SageValue s_recv(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_NUM||a[1].type!=SAGE_NUM)return sage_string(\"\"); int fd=(int)a[0].as.number; int size=(int)a[1].as.number; char*buf=malloc(size+1); int r=recv(fd,buf,size,0); if(r<0){free(buf);return sage_string(\"\");} buf[r]=0; SageValue v=sage_string(buf); free(buf); return v; }");
    aot_emit(aot, "static SageValue s_close(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_NUM)return sage_nil(); int fd=(int)a[0].as.number; close(fd); return sage_nil(); }");
    aot_emit(aot, "static SageValue s_gc_disable(int c, SageValue* a) { (void)c; (void)a; return sage_nil(); }");
    aot_emit(aot, "static SageValue s_slice(int c, SageValue* a) { if (c<3) return sage_nil(); return sage_slice(a[0], a[1], a[2]); }");
    aot_emit(aot, "static SageValue s_startswith(int c, SageValue* a) { if (c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR) return sage_bool(0); return sage_bool(strncmp(a[0].as.string, a[1].as.string, strlen(a[1].as.string))==0); }");
    aot_emit(aot, "static SageValue s_endswith(int c, SageValue* a) { if (c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR) return sage_bool(0); int l1=strlen(a[0].as.string); int l2=strlen(a[1].as.string); if(l2>l1)return sage_bool(0); return sage_bool(strcmp(a[0].as.string+l1-l2, a[1].as.string)==0); }");
    aot_emit(aot, "static SageValue s_contains(int c, SageValue* a) { if (c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR) return sage_bool(0); return sage_bool(strstr(a[0].as.string, a[1].as.string)!=NULL); }");
    aot_emit(aot, "static SageValue s_sleep(int c, SageValue* a) { if(c>0&&a[0].type==SAGE_NUM){ struct timespec req; req.tv_sec = (time_t)a[0].as.number; req.tv_nsec = (long)((a[0].as.number - (double)req.tv_sec) * 1e9); nanosleep(&req, NULL); } return sage_nil(); }");
    aot_emit(aot, "#include <pthread.h>");
    aot_emit(aot, "static void* _thread_runner(void* arg) { SageValue* fn = (SageValue*)arg; sage_call(*fn, 0, NULL); free(fn); return NULL; }");
    aot_emit(aot, "static SageValue s_spawn(int c, SageValue* a) { if(c<1)return sage_nil(); pthread_t* t=malloc(sizeof(pthread_t)); SageValue* fn=malloc(sizeof(SageValue)); *fn=a[0]; pthread_create(t, NULL, _thread_runner, fn); SageValue v; v.type=6; v.as.ptr=t; return v; }");
    aot_emit(aot, "static SageValue s_join(int c, SageValue* a) { if(c>0&&a[0].type==6){pthread_join(*(pthread_t*)a[0].as.ptr, NULL); free(a[0].as.ptr); return sage_nil();} if(c>1&&a[0].type==SAGE_ARR&&a[1].type==SAGE_STR){SageArr*arr=(SageArr*)a[0].as.ptr; if(arr->count==0)return sage_string(\"\"); int len=0; for(int i=0;i<arr->count;i++){SageValue sa=sage_str(arr->elems[i]); len+=strlen(sa.as.string);} len+=strlen(a[1].as.string)*arr->count; char*b=malloc(len+1); b[0]=0; for(int i=0;i<arr->count;i++){SageValue sa=sage_str(arr->elems[i]); strcat(b,sa.as.string); if(i<arr->count-1)strcat(b,a[1].as.string);} SageValue v; v.type=SAGE_STR; v.as.string=b; return v;} return sage_nil(); }");
    aot_emit(aot, "static SageValue s_string_count(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR)return sage_number(0); int ct=0; const char*p=a[0].as.string; const char*f=a[1].as.string; int fl=strlen(f); if(fl==0)return sage_number(0); while((p=strstr(p,f))!=NULL){ct++; p+=fl;} return sage_number(ct); }");
    aot_emit(aot, "static SageValue s_string_repeat(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_NUM)return sage_string(\"\"); int t=(int)a[1].as.number; if(t<=0)return sage_string(\"\"); int l=strlen(a[0].as.string); char*b=malloc(l*t+1); b[0]=0; for(int i=0;i<t;i++)strcat(b,a[0].as.string); return sage_string(b); }");
    aot_emit(aot, "static SageValue s_sendall(int c, SageValue* a) { return s_send(c,a); }");
    aot_emit(aot, "static SageValue s_indexof(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR)return sage_number(-1); char* p=strstr(a[0].as.string,a[1].as.string); if(!p)return sage_number(-1); return sage_number(p-a[0].as.string); }");
    aot_emit(aot, "#include <ctype.h>");
    aot_emit(aot, "static SageValue s_upper(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_string(\"\"); char* s=strdup(a[0].as.string); for(int i=0;s[i];i++) s[i]=toupper((unsigned char)s[i]); return sage_string(s); }");
    aot_emit(aot, "#include <dirent.h>");
    aot_emit(aot, "#include <sys/stat.h>");
    aot_emit(aot, "static SageValue s_listdir(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_array(0); DIR* d=opendir(a[0].as.string); if(!d)return sage_array(0); SageValue r=sage_array(0); struct dirent* dir; while((dir=readdir(d))!=NULL){if(strcmp(dir->d_name,\".\")!=0&&strcmp(dir->d_name,\"..\")!=0)sage_push(r,sage_string(strdup(dir->d_name)));} closedir(d); return r; }");
    aot_emit(aot, "static SageValue s_sys_args_builtin(int c, SageValue* a) { return sage_array(0); }");
    aot_emit(aot, "static SageValue s_isdir(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_bool(0); struct stat st; if(stat(a[0].as.string,&st)==0)return sage_bool(S_ISDIR(st.st_mode)); return sage_bool(0); }");
    aot_emit(aot, "static SageValue s_exists(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_bool(0); struct stat st; return sage_bool(stat(a[0].as.string,&st)==0); }");
    aot_emit(aot, "static SageValue s_readfile(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_string(\"\"); FILE* f=fopen(a[0].as.string,\"rb\"); if(!f)return sage_string(\"\"); fseek(f,0,SEEK_END); long s=ftell(f); fseek(f,0,SEEK_SET); char* b=malloc(s+1); fread(b,1,s,f); b[s]=0; fclose(f); return sage_string(b); }");
    aot_emit(aot, "static SageValue s_writefile(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR)return sage_bool(0); FILE* f=fopen(a[0].as.string,\"wb\"); if(!f)return sage_bool(0); size_t w=fwrite(a[1].as.string,1,strlen(a[1].as.string),f); fclose(f); return sage_bool(w==strlen(a[1].as.string)); }");
    aot_emit(aot, "static SageValue s_writebytes(int c, SageValue* a) { return s_writefile(c,a); }");
    aot_emit(aot, "static SageValue s_appendbytes(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR)return sage_bool(0); FILE* f=fopen(a[0].as.string,\"ab\"); if(!f)return sage_bool(0); size_t w=fwrite(a[1].as.string,1,strlen(a[1].as.string),f); fclose(f); return sage_bool(w==strlen(a[1].as.string)); }");
    aot_emit(aot, "static SageValue s_readbytes(int c, SageValue* a) { return s_readfile(c,a); }");
    aot_emit(aot, "static SageValue s_remove(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_bool(0); return sage_bool(remove(a[0].as.string)==0); }");
    aot_emit(aot, "static SageValue s_mkdir(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_bool(0); return sage_bool(mkdir(a[0].as.string,0777)==0); }");
    aot_emit(aot, "static SageValue s_getenv(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_string(\"\"); char* v=getenv(a[0].as.string); return sage_string(v?v:\"\"); }");
    aot_emit(aot, "static SageValue s_sys_getenv_native(int c, SageValue* a) { return s_getenv(c, a); }");
    aot_emit(aot, "static SageValue s_sys_exec(int c, SageValue* a) { return s_shell_exec(c, a); }");
    aot_emit(aot, "static SageValue s_io_readfile(int c, SageValue* a) { return s_readfile(c, a); }");
    aot_emit(aot, "static SageValue s_io_writefile(int c, SageValue* a) { return s_writefile(c, a); }");
    aot_emit(aot, "static SageValue s_io_writebytes(int c, SageValue* a) { return s_writebytes(c, a); }");
    aot_emit(aot, "static SageValue s_io_appendbytes(int c, SageValue* a) { return s_appendbytes(c, a); }");
    aot_emit(aot, "static SageValue s_io_readbytes(int c, SageValue* a) { return s_readbytes(c, a); }");
    aot_emit(aot, "static SageValue s_io_exists(int c, SageValue* a) { return s_exists(c, a); }");
    aot_emit(aot, "static SageValue s_io_remove(int c, SageValue* a) { return s_remove(c, a); }");
    aot_emit(aot, "static SageValue s_io_isdir(int c, SageValue* a) { return s_isdir(c, a); }");
    aot_emit(aot, "static SageValue s_io_mkdir(int c, SageValue* a) { return s_mkdir(c, a); }");
    aot_emit(aot, "static SageValue s_io_listdir(int c, SageValue* a) { return s_listdir(c, a); }");
    aot_emit(aot, "static SageValue s_pass;"); // no-op for 'pass' keyword
    aot_emit(aot, "static SageValue s_exec(int c, SageValue* a) { return s_shell_exec(c, a); }");
    aot_emit(aot, "static SageValue s_time(int c, SageValue* a) { (void)c; (void)a; return sage_number((double)time(NULL)); }");
    aot_emit(aot, "static SageValue s_print(int c, SageValue* a) { for(int i=0;i<c;i++){if(i)printf(\" \");sage_print_value(a[i]);}printf(\"\\n\");fflush(stdout);return sage_nil(); }");
    aot_emit(aot, "static SageValue s_keys(int c, SageValue* a) { if(c<1)return sage_array(0); return sage_dict_keys(a[0]); }");
    aot_emit(aot, "static SageValue s_range(int c, SageValue* a) { int n=0; if(c>0)n=(int)a[0].as.number; if(c>1)n=(int)a[1].as.number-(int)a[0].as.number; return sage_range(n>0?n:0); }");
    aot_emit(aot, "static SageValue s_input(int c, SageValue* a) { if(c>0&&a[0].type==SAGE_STR) { fputs(a[0].as.string,stdout); fflush(stdout); } char buf[4096]; int pos=0; while(pos<4095){ int ch=getchar(); if(ch==EOF||ch==4){ if(pos==0)return sage_string(\"\\x04\"); break; } if(ch=='\\n'||ch=='\\r'){ printf(\"\\r\\n\"); break; } if(ch==3||ch==27){ buf[pos++]=ch; break; } if(ch==12||ch=='\\t'){ buf[pos++]=ch; break; } if(ch==127||ch=='\\b'){ if(pos>0){ pos--; printf(\"\\b \\b\"); fflush(stdout); } continue; } buf[pos++]=ch; putchar(ch); fflush(stdout); } buf[pos]=0; return sage_string(buf); }");
    aot_emit(aot, "static SageValue s_split(int c, SageValue* a) { if(c<2||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR)return sage_array(0); SageArr*r=malloc(sizeof(SageArr)); r->cap=16; r->count=0; r->elems=malloc(sizeof(SageValue)*r->cap); char*str=strdup(a[0].as.string); char*tok=strtok(str,a[1].as.string); while(tok){if(r->count>=r->cap){r->cap*=2;r->elems=realloc(r->elems,sizeof(SageValue)*r->cap);}r->elems[r->count++]=sage_string(strdup(tok)); tok=strtok(NULL,a[1].as.string);} free(str); SageValue v;v.type=SAGE_ARR;v.as.ptr=r;return v; }");
    aot_emit(aot, "static SageValue s_chr(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_NUM)return sage_string(\"\"); char b[2]={(char)a[0].as.number,0}; return sage_string(strdup(b)); }");
    aot_emit(aot, "static SageValue s_replace(int c, SageValue* a) { if(c<3||a[0].type!=SAGE_STR||a[1].type!=SAGE_STR||a[2].type!=SAGE_STR)return a[0]; const char*str=a[0].as.string; const char*f=a[1].as.string; const char*r=a[2].as.string; if(strlen(f)==0)return a[0]; char*b=malloc(strlen(str)*4+1); b[0]=0; const char*p=str; while(1){const char*m=strstr(p,f); if(!m){strcat(b,p);break;} strncat(b,p,m-p); strcat(b,r); p=m+strlen(f);} SageValue v; v.type=SAGE_STR; v.as.string=b; return v; }");
    aot_emit(aot, "static SageValue s_strip(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR)return sage_string(\"\"); const char*s=a[0].as.string; while(*s==' '||*s=='\\t'||*s=='\\n'||*s=='\\r')s++; if(*s==0)return sage_string(\"\"); const char*e=s+strlen(s)-1; while(e>s&&(*e==' '||*e=='\\t'||*e=='\\n'||*e=='\\r'))e--; char*b=malloc(e-s+2); memcpy(b,s,e-s+1); b[e-s+1]=0; return sage_string(b); }");
    aot_emit(aot, "static SageValue s_clock(int c, SageValue* a) { (void)c; (void)a; struct timeval tv; gettimeofday(&tv, NULL); return sage_number((double)tv.tv_sec + (double)tv.tv_usec / 1000000.0); }");
    aot_emit(aot, "static SageValue s_ord(int c, SageValue* a) { if(c<1||a[0].type!=SAGE_STR||strlen(a[0].as.string)==0)return sage_number(0); return sage_number((unsigned char)a[0].as.string[0]); }");
    aot_emit(aot, "static void sage_print_value(SageValue v) { switch(v.type) { case SAGE_NUM: { double d=v.as.number; if(d==(double)(long long)d&&d>=-1e15&&d<=1e15) printf(\"%%lld\",(long long)d); else printf(\"%%g\",d); break; } case SAGE_BOOL: fputs(v.as.boolean?\"true\":\"false\",stdout); break; case SAGE_STR: fputs(v.as.string,stdout); break; case SAGE_ARR: { SageArr*a=(SageArr*)v.as.ptr; printf(\"[\"); for(int i=0;i<a->count;i++){if(i)printf(\", \");sage_print_value(a->elems[i]);} printf(\"]\"); break; } case SAGE_DICT: { SageDict*d=(SageDict*)v.as.ptr; printf(\"{\"); for(int i=0;i<d->count;i++){if(i)printf(\", \");printf(\"\\\"%%s\\\": \",d->keys[i]);sage_print_value(d->vals[i]);} printf(\"}\"); break; } default: fputs(\"nil\",stdout); } }");
    aot_emit(aot, "static SageValue s_words(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_compact(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_count_substring(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_repeat(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_pad_left(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_pad_right(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_surround(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_csv(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_dash_case(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_snake_case(int argc, SageValue* argv);");
    aot_emit(aot, "static SageValue s_from_bin(int argc, SageValue* argv);");
    aot_emit(aot, "");

    // Forward-declare all procs (including async) and top-level variables
    int builtin_count = aot->proc_count;
    aot_forward_declare_stmt(aot, program);
    aot_emit(aot, "");

    // Emit proc and class definitions
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_PROC || s->type == STMT_CLASS) {
            if (s->type == STMT_PROC) {
                char* name = sanitize_name(s->as.proc.name.start, s->as.proc.name.length);
                int already_builtin = 0;
                for (int j = 0; j < builtin_count; j++) {
                    if (strcmp(aot->procs[j], name) == 0) { already_builtin = 1; break; }
                }
                if (already_builtin) {
                    free(name);
                    continue;
                }
                free(name);
            }
            aot_compile_stmt(aot, s);
        }
    }

    aot_emit(aot, "int main(void) {");
    aot->in_main = 1;
    aot->indent++;

    // Compile all non-proc/non-class statements (procs and classes already emitted above)
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_PROC || s->type == STMT_ASYNC_PROC || s->type == STMT_CLASS) continue;
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
        execlp(cc, cc, "-std=c11", "-O2", "-fno-strict-aliasing", c_path, "-o", bin_path, "-lm", (char*)NULL);
        _exit(127);
    }
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
