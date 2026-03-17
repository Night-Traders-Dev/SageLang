#define _DEFAULT_SOURCE
#include "llvm_backend.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "ast.h"
#include "gc.h"
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

// ============================================================================
// LLVM Compiler State
// ============================================================================

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
} LLVMCompiler;

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
    ll_emit(lc, "target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128\"\n\n");

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
            int r = llc_new_reg(lc);
            // Check if it's a global variable
            int is_global = 0;
            for (int i = 0; i < lc->global_count; i++) {
                if (strcmp(lc->global_names[i], name) == 0) { is_global = 1; break; }
            }
            if (is_global) {
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

            // Allocate loop variable and counter
            char* var_name = token_to_str(stmt->as.for_stmt.variable);
            ll_line(lc, "%%%s = alloca %%SageValue", var_name);
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
        case STMT_IMPORT:
            // Module imports are not supported in compiled mode; skip silently
            break;
        case STMT_MATCH:
        case STMT_DEFER:
        case STMT_YIELD:
        case STMT_ASYNC_PROC:
            fprintf(stderr, "LLVM backend: unsupported statement type %d (match/defer/yield/async)\n", stmt->type);
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

    // Allocate all local variables used in main
    for (int i = 0; i < lc.global_count; i++) {
        // Globals are module-level, already declared above
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
        // Try several locations: obj/llvm_runtime.o, then next to the binary
        const char* rt_paths[] = {
            "obj/llvm_runtime.o",
            "./llvm_runtime.o",
            NULL
        };
        const char* rt_path = NULL;
        for (int i = 0; rt_paths[i] != NULL; i++) {
            if (access(rt_paths[i], F_OK) == 0) {
                rt_path = rt_paths[i];
                break;
            }
        }

        if (rt_path) {
            // Link with the runtime library
            execlp("clang", "clang", "-O2", ll_output_path, rt_path, "-o", exe_output_path,
                   "-lm", (char*)NULL);
        } else {
            // Fallback: try without runtime (will fail at link time if sage_rt_* used)
            execlp("clang", "clang", "-O2", ll_output_path, "-o", exe_output_path,
                   "-lm", (char*)NULL);
        }
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
