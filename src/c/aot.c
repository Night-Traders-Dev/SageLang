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
            // Generic fallback
            switch (op) {
                case TOKEN_PLUS:  sprintf(result, "sage_add(%s, %s)", left, right); break;
                case TOKEN_MINUS: sprintf(result, "sage_sub(%s, %s)", left, right); break;
                case TOKEN_STAR:  sprintf(result, "sage_mul(%s, %s)", left, right); break;
                case TOKEN_SLASH: sprintf(result, "sage_div(%s, %s)", left, right); break;
                case TOKEN_EQ:    sprintf(result, "sage_eq(%s, %s)", left, right); break;
                case TOKEN_NEQ:   sprintf(result, "sage_neq(%s, %s)", left, right); break;
                case TOKEN_GT:    sprintf(result, "sage_gt(%s, %s)", left, right); break;
                case TOKEN_LT:    sprintf(result, "sage_lt(%s, %s)", left, right); break;
                default:          sprintf(result, "sage_add(%s, %s)", left, right); break;
            }
            done:
            free(left);
            free(right);
            return result;
        }
        case EXPR_CALL: {
            // Direct call if callee is a simple variable (proc name)
            if (expr->as.call.callee && expr->as.call.callee->type == EXPR_VARIABLE) {
                char* fname = sanitize_name(expr->as.call.callee->as.variable.name.start,
                                            expr->as.call.callee->as.variable.name.length);
                int argc = expr->as.call.arg_count;
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
            // Fallback for complex callees
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
        default:
            aot_emit(aot, "/* unsupported stmt type %d */", stmt->type);
            break;
    }
}

char* aot_compile_program(AotCompiler* aot, Stmt* program) {
    // Type inference pass
    aot_infer_types(aot, program);

    // Emit C prelude
    aot_emit(aot, "#include <stdio.h>");
    aot_emit(aot, "#include <stdlib.h>");
    aot_emit(aot, "#include <string.h>");
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
    aot_emit(aot, "static void sage_print_value(SageValue v) { switch(v.type) { case SAGE_NUM: { double d=v.as.number; if(d==(double)(long long)d && d>=-1e15 && d<=1e15) printf(\"%%lld\",(long long)d); else printf(\"%%g\",d); break; } case SAGE_BOOL: fputs(v.as.boolean?\"true\":\"false\",stdout); break; case SAGE_STR: fputs(v.as.string,stdout); break; default: fputs(\"nil\",stdout); } }");
    aot_emit(aot, "static SageValue sage_strcat(SageValue a, SageValue b) { if(a.type!=SAGE_STR||b.type!=SAGE_STR) return sage_nil(); size_t la=strlen(a.as.string),lb=strlen(b.as.string); char* r=malloc(la+lb+1); memcpy(r,a.as.string,la); memcpy(r+la,b.as.string,lb); r[la+lb]=0; SageValue v; v.type=SAGE_STR; v.as.string=r; return v; }");
    aot_emit(aot, "");

    // Forward-declare all procs
    for (Stmt* s = program; s; s = s->next) {
        if (s->type == STMT_PROC) {
            char* name = sanitize_name(s->as.proc.name.start, s->as.proc.name.length);
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
        if (s->type == STMT_PROC) continue;
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
