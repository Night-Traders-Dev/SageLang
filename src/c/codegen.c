#define _DEFAULT_SOURCE
#define _GNU_SOURCE
#include "codegen.h"

#include <errno.h>
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

// Forward declaration
extern Stmt* parse_program(const char* source);

// ============================================================================
// Code Buffer Implementation
// ============================================================================

void codebuf_init(CodeBuffer* buf) {
    buf->code_cap = 4096;
    buf->code_len = 0;
    buf->code = SAGE_ALLOC(buf->code_cap);
    buf->data_cap = 4096;
    buf->data_len = 0;
    buf->data = SAGE_ALLOC(buf->data_cap);
}

void codebuf_free(CodeBuffer* buf) {
    free(buf->code);
    free(buf->data);
    buf->code = NULL;
    buf->data = NULL;
}

static void codebuf_grow(CodeBuffer* buf, size_t needed) {
    while (buf->code_cap < buf->code_len + needed) {
        buf->code_cap *= 2;
    }
    buf->code = SAGE_REALLOC(buf->code, buf->code_cap);
}

void codebuf_emit8(CodeBuffer* buf, uint8_t byte) {
    codebuf_grow(buf, 1);
    buf->code[buf->code_len++] = byte;
}

void codebuf_emit16(CodeBuffer* buf, uint16_t val) {
    codebuf_grow(buf, 2);
    memcpy(buf->code + buf->code_len, &val, 2);
    buf->code_len += 2;
}

void codebuf_emit32(CodeBuffer* buf, uint32_t val) {
    codebuf_grow(buf, 4);
    memcpy(buf->code + buf->code_len, &val, 4);
    buf->code_len += 4;
}

void codebuf_emit64(CodeBuffer* buf, uint64_t val) {
    codebuf_grow(buf, 8);
    memcpy(buf->code + buf->code_len, &val, 8);
    buf->code_len += 8;
}

void codebuf_emit_data(CodeBuffer* buf, const uint8_t* data, size_t len) {
    codebuf_grow(buf, len);
    memcpy(buf->code + buf->code_len, data, len);
    buf->code_len += len;
}

// ============================================================================
// VInst Construction
// ============================================================================

VInst* vinst_new(VInstKind kind) {
    VInst* v = SAGE_ALLOC(sizeof(VInst));
    memset(v, 0, sizeof(VInst));
    v->kind = kind;
    v->dest = -1;
    v->src1 = -1;
    v->src2 = -1;
    return v;
}

void vinst_free_list(VInst* head) {
    while (head != NULL) {
        VInst* next = head->next;
        free(head->imm_string);
        free(head->label);
        free(head->label_false);
        free(head->func_name);
        free(head->call_args);
        free(head);
        head = next;
    }
}

// ============================================================================
// Instruction Selection Context
// ============================================================================

void isel_init(ISelContext* ctx) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->next_vreg = 0;
    ctx->next_label = 0;
    ctx->string_pool_cap = 16;
    ctx->string_pool = SAGE_ALLOC(sizeof(char*) * 16);
}

void isel_free(ISelContext* ctx) {
    vinst_free_list(ctx->head);
    for (int i = 0; i < ctx->string_pool_count; i++) {
        free(ctx->string_pool[i]);
    }
    free(ctx->string_pool);
}

static void isel_append(ISelContext* ctx, VInst* v) {
    if (ctx->head == NULL) {
        ctx->head = v;
    } else {
        ctx->tail->next = v;
    }
    ctx->tail = v;
}

static int isel_vreg(ISelContext* ctx) {
    return ctx->next_vreg++;
}

static char* isel_label(ISelContext* ctx) {
    char buf[32];
    snprintf(buf, sizeof(buf), ".L%d", ctx->next_label++);
    return SAGE_STRDUP(buf);
}

static int isel_add_string(ISelContext* ctx, const char* str) {
    if (ctx->string_pool_count >= ctx->string_pool_cap) {
        ctx->string_pool_cap *= 2;
        ctx->string_pool = SAGE_REALLOC(ctx->string_pool, sizeof(char*) * (size_t)ctx->string_pool_cap);
    }
    ctx->string_pool[ctx->string_pool_count] = SAGE_STRDUP(str);
    return ctx->string_pool_count++;
}

// ============================================================================
// Token helper
// ============================================================================

static char* tok_str(Token tok) {
    char* s = SAGE_ALLOC((size_t)tok.length + 1);
    memcpy(s, tok.start, (size_t)tok.length);
    s[tok.length] = '\0';
    return s;
}

// ============================================================================
// Instruction Selection - Expression
// ============================================================================

static int isel_expr(ISelContext* ctx, Expr* expr) {
    if (expr == NULL) {
        int r = isel_vreg(ctx);
        VInst* v = vinst_new(VINST_LOAD_NIL);
        v->dest = r;
        isel_append(ctx, v);
        return r;
    }

    switch (expr->type) {
        case EXPR_NUMBER: {
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_LOAD_IMM);
            v->dest = r;
            v->imm_number = expr->as.number.value;
            isel_append(ctx, v);
            return r;
        }
        case EXPR_STRING: {
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_LOAD_STRING);
            v->dest = r;
            v->imm_string = SAGE_STRDUP(expr->as.string.value);
            isel_append(ctx, v);
            isel_add_string(ctx, expr->as.string.value);
            return r;
        }
        case EXPR_BOOL: {
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_LOAD_BOOL);
            v->dest = r;
            v->imm_bool = expr->as.boolean.value;
            isel_append(ctx, v);
            return r;
        }
        case EXPR_NIL: {
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_LOAD_NIL);
            v->dest = r;
            isel_append(ctx, v);
            return r;
        }
        case EXPR_BINARY: {
            int left = isel_expr(ctx, expr->as.binary.left);
            int right = isel_expr(ctx, expr->as.binary.right);
            int r = isel_vreg(ctx);

            const char* op = expr->as.binary.op.start;
            int op_len = expr->as.binary.op.length;
            VInstKind kind = VINST_ADD;

            if (op_len == 1) {
                switch (*op) {
                    case '+': kind = VINST_ADD; break;
                    case '-': kind = VINST_SUB; break;
                    case '*': kind = VINST_MUL; break;
                    case '/': kind = VINST_DIV; break;
                    case '%': kind = VINST_MOD; break;
                    case '<': kind = VINST_LT; break;
                    case '>': kind = VINST_GT; break;
                    default: break;
                }
            } else if (op_len == 2) {
                if (op[0] == '=' && op[1] == '=') kind = VINST_EQ;
                else if (op[0] == '!' && op[1] == '=') kind = VINST_NEQ;
                else if (op[0] == '<' && op[1] == '=') kind = VINST_LTE;
                else if (op[0] == '>' && op[1] == '=') kind = VINST_GTE;
                else if (memcmp(op, "or", 2) == 0) kind = VINST_OR;
            } else if (op_len == 3 && memcmp(op, "and", 3) == 0) {
                kind = VINST_AND;
            }

            VInst* v = vinst_new(kind);
            v->dest = r;
            v->src1 = left;
            v->src2 = right;
            isel_append(ctx, v);
            return r;
        }
        case EXPR_VARIABLE: {
            int r = isel_vreg(ctx);
            char* name = tok_str(expr->as.variable.name);
            VInst* v = vinst_new(VINST_LOAD_GLOBAL);
            v->dest = r;
            v->imm_string = name;
            isel_append(ctx, v);
            return r;
        }
        case EXPR_CALL: {
            int* arg_regs = NULL;
            if (expr->as.call.arg_count > 0) {
                arg_regs = SAGE_ALLOC(sizeof(int) * (size_t)expr->as.call.arg_count);
                for (int i = 0; i < expr->as.call.arg_count; i++) {
                    arg_regs[i] = isel_expr(ctx, expr->as.call.args[i]);
                }
            }
            int r = isel_vreg(ctx);

            if (expr->as.call.callee->type == EXPR_VARIABLE) {
                char* name = tok_str(expr->as.call.callee->as.variable.name);
                // Check for builtin names
                int is_builtin = (strcmp(name, "str") == 0 || strcmp(name, "len") == 0 ||
                                  strcmp(name, "tonumber") == 0 || strcmp(name, "push") == 0 ||
                                  strcmp(name, "pop") == 0 || strcmp(name, "range") == 0);

                VInst* v = vinst_new(is_builtin ? VINST_CALL_BUILTIN : VINST_CALL);
                v->dest = r;
                v->func_name = name;
                v->call_args = arg_regs;
                v->call_arg_count = expr->as.call.arg_count;
                isel_append(ctx, v);
            } else {
                VInst* v = vinst_new(VINST_LOAD_NIL);
                v->dest = r;
                isel_append(ctx, v);
                free(arg_regs);
            }
            return r;
        }
        case EXPR_ARRAY: {
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_ARRAY_NEW);
            v->dest = r;
            v->src1 = expr->as.array.count;
            isel_append(ctx, v);

            for (int i = 0; i < expr->as.array.count; i++) {
                int elem = isel_expr(ctx, expr->as.array.elements[i]);
                VInst* set = vinst_new(VINST_ARRAY_SET);
                set->src1 = r;
                set->src2 = elem;
                set->imm_number = (double)i;
                isel_append(ctx, set);
            }
            return r;
        }
        case EXPR_INDEX: {
            int arr = isel_expr(ctx, expr->as.index.array);
            int idx = isel_expr(ctx, expr->as.index.index);
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_INDEX);
            v->dest = r;
            v->src1 = arr;
            v->src2 = idx;
            isel_append(ctx, v);
            return r;
        }
        case EXPR_INDEX_SET:
        case EXPR_DICT:
        case EXPR_TUPLE:
        case EXPR_SLICE:
        case EXPR_GET:
        case EXPR_SET:
        case EXPR_AWAIT:
            // TODO: not yet supported in codegen backend
            fprintf(stderr, "Codegen backend: unsupported expression type %d (index_set/dict/tuple/slice/get/set/await not yet implemented)\n", expr->type);
            /* fallthrough */
        default: {
            int r = isel_vreg(ctx);
            VInst* v = vinst_new(VINST_LOAD_NIL);
            v->dest = r;
            isel_append(ctx, v);
            return r;
        }
    }
}

// ============================================================================
// Instruction Selection - Statement
// ============================================================================

static void isel_stmt(ISelContext* ctx, Stmt* stmt);

static void isel_stmt_list(ISelContext* ctx, Stmt* head) {
    for (Stmt* s = head; s != NULL; s = s->next) {
        isel_stmt(ctx, s);
    }
}

static void isel_stmt(ISelContext* ctx, Stmt* stmt) {
    if (stmt == NULL) return;

    switch (stmt->type) {
        case STMT_PRINT: {
            int r = isel_expr(ctx, stmt->as.print.expression);
            VInst* v = vinst_new(VINST_PRINT);
            v->src1 = r;
            isel_append(ctx, v);
            break;
        }
        case STMT_EXPRESSION:
            isel_expr(ctx, stmt->as.expression);
            break;
        case STMT_LET: {
            int val = isel_expr(ctx, stmt->as.let.initializer);
            char* name = tok_str(stmt->as.let.name);
            VInst* v = vinst_new(VINST_STORE_GLOBAL);
            v->src1 = val;
            v->imm_string = name;
            isel_append(ctx, v);
            break;
        }
        case STMT_IF: {
            int cond = isel_expr(ctx, stmt->as.if_stmt.condition);
            char* then_label = isel_label(ctx);
            char* else_label = isel_label(ctx);
            char* merge_label = isel_label(ctx);

            VInst* br = vinst_new(VINST_BRANCH);
            br->src1 = cond;
            br->label = SAGE_STRDUP(then_label);
            br->label_false = stmt->as.if_stmt.else_branch ? SAGE_STRDUP(else_label) : SAGE_STRDUP(merge_label);
            isel_append(ctx, br);

            VInst* tl = vinst_new(VINST_LABEL);
            tl->label = SAGE_STRDUP(then_label);
            isel_append(ctx, tl);
            isel_stmt_list(ctx, stmt->as.if_stmt.then_branch);
            VInst* jmp1 = vinst_new(VINST_JUMP);
            jmp1->label = SAGE_STRDUP(merge_label);
            isel_append(ctx, jmp1);

            if (stmt->as.if_stmt.else_branch) {
                VInst* el = vinst_new(VINST_LABEL);
                el->label = SAGE_STRDUP(else_label);
                isel_append(ctx, el);
                isel_stmt_list(ctx, stmt->as.if_stmt.else_branch);
                VInst* jmp2 = vinst_new(VINST_JUMP);
                jmp2->label = SAGE_STRDUP(merge_label);
                isel_append(ctx, jmp2);
            }

            VInst* ml = vinst_new(VINST_LABEL);
            ml->label = SAGE_STRDUP(merge_label);
            isel_append(ctx, ml);

            free(then_label);
            free(else_label);
            free(merge_label);
            break;
        }
        case STMT_WHILE: {
            if (ctx->loop_depth >= 64) {
                fprintf(stderr, "codegen: loop nesting too deep (max 64)\n");
                return;
            }
            char* cond_label = isel_label(ctx);
            char* body_label = isel_label(ctx);
            char* end_label = isel_label(ctx);

            ctx->loop_cond_labels[ctx->loop_depth] = cond_label;
            ctx->loop_end_labels[ctx->loop_depth] = end_label;
            ctx->loop_depth++;

            VInst* jmp0 = vinst_new(VINST_JUMP);
            jmp0->label = SAGE_STRDUP(cond_label);
            isel_append(ctx, jmp0);

            VInst* cl = vinst_new(VINST_LABEL);
            cl->label = SAGE_STRDUP(cond_label);
            isel_append(ctx, cl);

            int cond = isel_expr(ctx, stmt->as.while_stmt.condition);
            VInst* br = vinst_new(VINST_BRANCH);
            br->src1 = cond;
            br->label = SAGE_STRDUP(body_label);
            br->label_false = SAGE_STRDUP(end_label);
            isel_append(ctx, br);

            VInst* bl = vinst_new(VINST_LABEL);
            bl->label = SAGE_STRDUP(body_label);
            isel_append(ctx, bl);
            isel_stmt_list(ctx, stmt->as.while_stmt.body);
            VInst* jmp1 = vinst_new(VINST_JUMP);
            jmp1->label = SAGE_STRDUP(cond_label);
            isel_append(ctx, jmp1);

            VInst* el = vinst_new(VINST_LABEL);
            el->label = SAGE_STRDUP(end_label);
            isel_append(ctx, el);

            ctx->loop_depth--;
            free(cond_label);
            free(body_label);
            free(end_label);
            break;
        }
        case STMT_BLOCK:
            isel_stmt_list(ctx, stmt->as.block.statements);
            break;
        case STMT_RETURN: {
            int r = isel_expr(ctx, stmt->as.ret.value);
            VInst* v = vinst_new(VINST_RET);
            v->src1 = r;
            isel_append(ctx, v);
            break;
        }
        case STMT_FOR: {
            // Emit iterable
            int iter = isel_expr(ctx, stmt->as.for_stmt.iterable);
            // Use CALL_BUILTIN to get array length
            int len_reg = isel_vreg(ctx);
            VInst* len_call = vinst_new(VINST_CALL_BUILTIN);
            len_call->dest = len_reg;
            len_call->func_name = SAGE_STRDUP("len");
            len_call->call_args = SAGE_ALLOC(sizeof(int));
            len_call->call_args[0] = iter;
            len_call->call_arg_count = 1;
            isel_append(ctx, len_call);

            // Counter variable
            int idx_reg = isel_vreg(ctx);
            VInst* idx_init = vinst_new(VINST_LOAD_IMM);
            idx_init->dest = idx_reg;
            idx_init->imm_number = 0.0;
            isel_append(ctx, idx_init);

            char* var_name = tok_str(stmt->as.for_stmt.variable);
            VInst* init_store = vinst_new(VINST_STORE_GLOBAL);
            init_store->src1 = idx_reg;
            init_store->imm_string = SAGE_STRDUP("__for_idx__");
            isel_append(ctx, init_store);

            if (ctx->loop_depth >= 64) {
                fprintf(stderr, "codegen: loop nesting too deep (max 64)\n");
                return;
            }
            char* cond_label = isel_label(ctx);
            char* body_label = isel_label(ctx);
            char* end_label = isel_label(ctx);

            ctx->loop_cond_labels[ctx->loop_depth] = cond_label;
            ctx->loop_end_labels[ctx->loop_depth] = end_label;
            ctx->loop_depth++;

            VInst* jmp0 = vinst_new(VINST_JUMP);
            jmp0->label = SAGE_STRDUP(cond_label);
            isel_append(ctx, jmp0);

            VInst* cl = vinst_new(VINST_LABEL);
            cl->label = SAGE_STRDUP(cond_label);
            isel_append(ctx, cl);

            // Load counter, compare with length
            int cur_idx = isel_vreg(ctx);
            VInst* load_idx = vinst_new(VINST_LOAD_GLOBAL);
            load_idx->dest = cur_idx;
            load_idx->imm_string = SAGE_STRDUP("__for_idx__");
            isel_append(ctx, load_idx);

            int cmp = isel_vreg(ctx);
            VInst* lt = vinst_new(VINST_LT);
            lt->dest = cmp;
            lt->src1 = cur_idx;
            lt->src2 = len_reg;
            isel_append(ctx, lt);

            VInst* br = vinst_new(VINST_BRANCH);
            br->src1 = cmp;
            br->label = SAGE_STRDUP(body_label);
            br->label_false = SAGE_STRDUP(end_label);
            isel_append(ctx, br);

            VInst* bl = vinst_new(VINST_LABEL);
            bl->label = SAGE_STRDUP(body_label);
            isel_append(ctx, bl);

            // Get element: arr[idx]
            int elem = isel_vreg(ctx);
            VInst* index_v = vinst_new(VINST_INDEX);
            index_v->dest = elem;
            index_v->src1 = iter;
            index_v->src2 = cur_idx;
            isel_append(ctx, index_v);

            // Store in loop variable
            VInst* store_var = vinst_new(VINST_STORE_GLOBAL);
            store_var->src1 = elem;
            store_var->imm_string = SAGE_STRDUP(var_name);
            isel_append(ctx, store_var);

            isel_stmt_list(ctx, stmt->as.for_stmt.body);

            // Increment counter: idx = idx + 1
            int one_reg = isel_vreg(ctx);
            VInst* one = vinst_new(VINST_LOAD_IMM);
            one->dest = one_reg;
            one->imm_number = 1.0;
            isel_append(ctx, one);

            int next_idx = isel_vreg(ctx);
            VInst* add = vinst_new(VINST_ADD);
            add->dest = next_idx;
            add->src1 = cur_idx;
            add->src2 = one_reg;
            isel_append(ctx, add);

            VInst* store_idx = vinst_new(VINST_STORE_GLOBAL);
            store_idx->src1 = next_idx;
            store_idx->imm_string = SAGE_STRDUP("__for_idx__");
            isel_append(ctx, store_idx);

            VInst* jmp1 = vinst_new(VINST_JUMP);
            jmp1->label = SAGE_STRDUP(cond_label);
            isel_append(ctx, jmp1);

            VInst* el = vinst_new(VINST_LABEL);
            el->label = SAGE_STRDUP(end_label);
            isel_append(ctx, el);

            ctx->loop_depth--;
            free(var_name);
            free(cond_label);
            free(body_label);
            free(end_label);
            break;
        }
        case STMT_BREAK: {
            if (ctx->loop_depth > 0) {
                VInst* jmp = vinst_new(VINST_JUMP);
                jmp->label = SAGE_STRDUP(ctx->loop_end_labels[ctx->loop_depth - 1]);
                isel_append(ctx, jmp);
            }
            break;
        }
        case STMT_CONTINUE: {
            if (ctx->loop_depth > 0) {
                VInst* jmp = vinst_new(VINST_JUMP);
                jmp->label = SAGE_STRDUP(ctx->loop_cond_labels[ctx->loop_depth - 1]);
                isel_append(ctx, jmp);
            }
            break;
        }
        case STMT_CLASS:
        case STMT_MATCH:
        case STMT_TRY:
        case STMT_RAISE:
        case STMT_DEFER:
        case STMT_YIELD:
        case STMT_IMPORT:
        case STMT_ASYNC_PROC:
            fprintf(stderr, "Codegen backend: unsupported statement type %d\n", stmt->type);
            break;
        default:
            break;
    }
}

// ============================================================================
// Full Instruction Selection Pipeline
// ============================================================================

VInst* isel_compile(const char* source, const char* input_path, int opt_level, int debug_info) {
    Stmt* program = parse_program(source);

    if (opt_level > 0) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        program = run_passes(program, &pass_ctx);
    }

    ISelContext ctx;
    isel_init(&ctx);

    isel_stmt_list(&ctx, program);

    VInst* result = ctx.head;
    ctx.head = NULL;
    ctx.tail = NULL;

    free_stmt(program);
    // Don't free ctx.head since we returned it
    for (int i = 0; i < ctx.string_pool_count; i++) {
        free(ctx.string_pool[i]);
    }
    free(ctx.string_pool);

    return result;
}

// ============================================================================
// Host Target Detection
// ============================================================================

CodegenTarget codegen_detect_host_target(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return CODEGEN_TARGET_X86_64;
#elif defined(__aarch64__) || defined(_M_ARM64)
    return CODEGEN_TARGET_AARCH64;
#elif defined(__riscv) && (__riscv_xlen == 64)
    return CODEGEN_TARGET_RV64;
#else
    return CODEGEN_TARGET_X86_64;  // default fallback
#endif
}

static const char* target_name(CodegenTarget target) {
    switch (target) {
        case CODEGEN_TARGET_X86_64: return "x86_64";
        case CODEGEN_TARGET_AARCH64: return "aarch64";
        case CODEGEN_TARGET_RV64: return "rv64";
    }
    return "unknown";
}

// ============================================================================
// Assembly Text Emission (generates GNU as syntax)
//
// This generates assembly that calls into the C runtime library.
// The runtime provides sage_rt_* functions for all value operations.
// ============================================================================

static void emit_asm_header(FILE* out, CodegenTarget target) {
    fprintf(out, "# SageLang assembly output for %s\n", target_name(target));
    fprintf(out, "# Generated by sage compiler\n\n");

    switch (target) {
        case CODEGEN_TARGET_X86_64:
            fprintf(out, ".intel_syntax noprefix\n");
            fprintf(out, ".text\n");
            fprintf(out, ".globl main\n\n");
            break;
        case CODEGEN_TARGET_AARCH64:
            fprintf(out, ".text\n");
            fprintf(out, ".globl main\n\n");
            break;
        case CODEGEN_TARGET_RV64:
            fprintf(out, ".text\n");
            fprintf(out, ".globl main\n\n");
            break;
    }
}

static void emit_asm_vinst_x86_64(FILE* out, VInst* v) {
    // Simplified assembly emission for x86-64
    // All operations go through runtime calls using System V ABI
    switch (v->kind) {
        case VINST_LOAD_IMM:
            fprintf(out, "  # v%d = number %f\n", v->dest, v->imm_number);
            fprintf(out, "  movsd .LC%d(%%rip), %%xmm0\n", v->dest);
            fprintf(out, "  call sage_rt_number\n");
            fprintf(out, "  movq %%rax, %d(%%rbp)\n", -(v->dest + 1) * 16);
            fprintf(out, "  movq %%rdx, %d(%%rbp)\n", -(v->dest + 1) * 16 + 8);
            break;
        case VINST_PRINT:
            fprintf(out, "  # print v%d\n", v->src1);
            fprintf(out, "  movq %d(%%rbp), %%rdi\n", -(v->src1 + 1) * 16);
            fprintf(out, "  movq %d(%%rbp), %%rsi\n", -(v->src1 + 1) * 16 + 8);
            fprintf(out, "  call sage_rt_print\n");
            break;
        case VINST_ADD:
        case VINST_SUB:
        case VINST_MUL:
        case VINST_DIV: {
            const char* fn = "sage_rt_add";
            if (v->kind == VINST_SUB) fn = "sage_rt_sub";
            else if (v->kind == VINST_MUL) fn = "sage_rt_mul";
            else if (v->kind == VINST_DIV) fn = "sage_rt_div";
            fprintf(out, "  # v%d = v%d op v%d\n", v->dest, v->src1, v->src2);
            fprintf(out, "  movq %d(%%rbp), %%rdi\n", -(v->src1 + 1) * 16);
            fprintf(out, "  movq %d(%%rbp), %%rsi\n", -(v->src1 + 1) * 16 + 8);
            fprintf(out, "  movq %d(%%rbp), %%rdx\n", -(v->src2 + 1) * 16);
            fprintf(out, "  movq %d(%%rbp), %%rcx\n", -(v->src2 + 1) * 16 + 8);
            fprintf(out, "  call %s\n", fn);
            fprintf(out, "  movq %%rax, %d(%%rbp)\n", -(v->dest + 1) * 16);
            fprintf(out, "  movq %%rdx, %d(%%rbp)\n", -(v->dest + 1) * 16 + 8);
            break;
        }
        case VINST_CALL:
            fprintf(out, "  # call %s\n", v->func_name);
            fprintf(out, "  call sage_fn_%s\n", v->func_name);
            fprintf(out, "  movq %%rax, %d(%%rbp)\n", -(v->dest + 1) * 16);
            fprintf(out, "  movq %%rdx, %d(%%rbp)\n", -(v->dest + 1) * 16 + 8);
            break;
        case VINST_LABEL:
            fprintf(out, "%s:\n", v->label);
            break;
        case VINST_JUMP:
            fprintf(out, "  jmp %s\n", v->label);
            break;
        case VINST_RET:
            fprintf(out, "  movq %d(%%rbp), %%rax\n", -(v->src1 + 1) * 16);
            fprintf(out, "  movq %d(%%rbp), %%rdx\n", -(v->src1 + 1) * 16 + 8);
            fprintf(out, "  leave\n");
            fprintf(out, "  ret\n");
            break;
        default:
            fprintf(out, "  # unhandled vinst %d\n", v->kind);
            break;
    }
}

static void emit_asm_vinst_aarch64(FILE* out, VInst* v) {
    switch (v->kind) {
        case VINST_LOAD_IMM:
            fprintf(out, "  // v%d = number %f\n", v->dest, v->imm_number);
            fprintf(out, "  bl sage_rt_number\n");
            fprintf(out, "  str x0, [sp, #%d]\n", v->dest * 16);
            fprintf(out, "  str x1, [sp, #%d]\n", v->dest * 16 + 8);
            break;
        case VINST_PRINT:
            fprintf(out, "  // print v%d\n", v->src1);
            fprintf(out, "  ldr x0, [sp, #%d]\n", v->src1 * 16);
            fprintf(out, "  ldr x1, [sp, #%d]\n", v->src1 * 16 + 8);
            fprintf(out, "  bl sage_rt_print\n");
            break;
        case VINST_LABEL:
            fprintf(out, "%s:\n", v->label);
            break;
        case VINST_JUMP:
            fprintf(out, "  b %s\n", v->label);
            break;
        case VINST_RET:
            fprintf(out, "  ldr x0, [sp, #%d]\n", v->src1 * 16);
            fprintf(out, "  ldr x1, [sp, #%d]\n", v->src1 * 16 + 8);
            fprintf(out, "  ldp x29, x30, [sp], #%d\n", 256);
            fprintf(out, "  ret\n");
            break;
        default:
            fprintf(out, "  // unhandled vinst %d\n", v->kind);
            break;
    }
}

static void emit_asm_vinst_rv64(FILE* out, VInst* v) {
    switch (v->kind) {
        case VINST_LOAD_IMM:
            fprintf(out, "  # v%d = number %f\n", v->dest, v->imm_number);
            fprintf(out, "  call sage_rt_number\n");
            fprintf(out, "  sd a0, %d(sp)\n", v->dest * 16);
            fprintf(out, "  sd a1, %d(sp)\n", v->dest * 16 + 8);
            break;
        case VINST_PRINT:
            fprintf(out, "  # print v%d\n", v->src1);
            fprintf(out, "  ld a0, %d(sp)\n", v->src1 * 16);
            fprintf(out, "  ld a1, %d(sp)\n", v->src1 * 16 + 8);
            fprintf(out, "  call sage_rt_print\n");
            break;
        case VINST_LABEL:
            fprintf(out, "%s:\n", v->label);
            break;
        case VINST_JUMP:
            fprintf(out, "  j %s\n", v->label);
            break;
        case VINST_RET:
            fprintf(out, "  ld a0, %d(sp)\n", v->src1 * 16);
            fprintf(out, "  ld a1, %d(sp)\n", v->src1 * 16 + 8);
            fprintf(out, "  ld ra, 8(sp)\n");
            fprintf(out, "  ld s0, 0(sp)\n");
            fprintf(out, "  addi sp, sp, 256\n");
            fprintf(out, "  ret\n");
            break;
        default:
            fprintf(out, "  # unhandled vinst %d\n", v->kind);
            break;
    }
}

// ============================================================================
// Assembly Output
// ============================================================================

static void emit_asm_function_prologue(FILE* out, CodegenTarget target, const char* name, int stack_size) {
    (void)stack_size;
    fprintf(out, "%s:\n", name);
    switch (target) {
        case CODEGEN_TARGET_X86_64:
            fprintf(out, "  push rbp\n");
            fprintf(out, "  mov rbp, rsp\n");
            fprintf(out, "  sub rsp, %d\n", 256);  // fixed stack frame
            break;
        case CODEGEN_TARGET_AARCH64:
            fprintf(out, "  stp x29, x30, [sp, #-256]!\n");
            fprintf(out, "  mov x29, sp\n");
            break;
        case CODEGEN_TARGET_RV64:
            fprintf(out, "  addi sp, sp, -256\n");
            fprintf(out, "  sd ra, 8(sp)\n");
            fprintf(out, "  sd s0, 0(sp)\n");
            fprintf(out, "  addi s0, sp, 256\n");
            break;
    }
}

static void emit_asm_function_epilogue(FILE* out, CodegenTarget target) {
    switch (target) {
        case CODEGEN_TARGET_X86_64:
            fprintf(out, "  xor eax, eax\n");
            fprintf(out, "  leave\n");
            fprintf(out, "  ret\n");
            break;
        case CODEGEN_TARGET_AARCH64:
            fprintf(out, "  mov w0, #0\n");
            fprintf(out, "  ldp x29, x30, [sp], #256\n");
            fprintf(out, "  ret\n");
            break;
        case CODEGEN_TARGET_RV64:
            fprintf(out, "  li a0, 0\n");
            fprintf(out, "  ld ra, 8(sp)\n");
            fprintf(out, "  ld s0, 0(sp)\n");
            fprintf(out, "  addi sp, sp, 256\n");
            fprintf(out, "  ret\n");
            break;
    }
}

static int write_asm_output(const char* source, const char* input_path, const char* output_path,
                            CodegenTarget target, int opt_level, int debug_info) {
    Stmt* program = parse_program(source);

    if (opt_level > 0) {
        PassContext pass_ctx = { opt_level, debug_info, 0, input_path };
        program = run_passes(program, &pass_ctx);
    }

    ISelContext ctx;
    isel_init(&ctx);
    isel_stmt_list(&ctx, program);

    FILE* out = fopen(output_path, "w");
    if (out == NULL) {
        fprintf(stderr, "Could not open assembly output \"%s\": %s\n", output_path, strerror(errno));
        free_stmt(program);
        isel_free(&ctx);
        return 0;
    }

    emit_asm_header(out, target);
    emit_asm_function_prologue(out, target, "main", 256);

    for (VInst* v = ctx.head; v != NULL; v = v->next) {
        switch (target) {
            case CODEGEN_TARGET_X86_64: emit_asm_vinst_x86_64(out, v); break;
            case CODEGEN_TARGET_AARCH64: emit_asm_vinst_aarch64(out, v); break;
            case CODEGEN_TARGET_RV64: emit_asm_vinst_rv64(out, v); break;
        }
    }

    emit_asm_function_epilogue(out, target);

    // Emit string data section with proper escaping
    if (ctx.string_pool_count > 0) {
        fprintf(out, "\n.section .rodata\n");
        for (int i = 0; i < ctx.string_pool_count; i++) {
            fprintf(out, ".LC%d:\n", i);
            fprintf(out, "  .asciz \"");
            for (const char* p = ctx.string_pool[i]; *p; p++) {
                if (*p == '"') fprintf(out, "\\\"");
                else if (*p == '\\') fprintf(out, "\\\\");
                else if (*p == '\n') fprintf(out, "\\n");
                else if (*p == '\t') fprintf(out, "\\t");
                else if (*p == '\r') fprintf(out, "\\r");
                else if ((unsigned char)*p < 0x20) fprintf(out, "\\%03o", (unsigned char)*p);
                else fputc(*p, out);
            }
            fprintf(out, "\"\n");
        }
    }

    fclose(out);
    free_stmt(program);
    isel_free(&ctx);
    return 1;
}

// ============================================================================
// ELF Object Writer (minimal)
// ============================================================================

int elf_write_object(const char* output_path, CodeBuffer* buf, CodegenTarget target) {
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        fprintf(stderr, "Could not open ELF output \"%s\": %s\n", output_path, strerror(errno));
        return 0;
    }

    // ELF64 header
    uint8_t elf_header[64] = {0};
    // Magic
    elf_header[0] = 0x7f; elf_header[1] = 'E'; elf_header[2] = 'L'; elf_header[3] = 'F';
    elf_header[4] = 2;    // 64-bit
    elf_header[5] = 1;    // little-endian
    elf_header[6] = 1;    // ELF version
    elf_header[7] = 0;    // OS/ABI
    // e_type: ET_REL (1)
    elf_header[16] = 1; elf_header[17] = 0;
    // e_machine
    switch (target) {
        case CODEGEN_TARGET_X86_64:  elf_header[18] = 0x3e; break; // EM_X86_64
        case CODEGEN_TARGET_AARCH64: elf_header[18] = 0xb7; break; // EM_AARCH64
        case CODEGEN_TARGET_RV64:    elf_header[18] = 0xf3; break; // EM_RISCV
    }
    elf_header[19] = 0;
    // e_version
    elf_header[20] = 1;
    // e_ehsize = 64
    elf_header[52] = 64;
    // e_shentsize = 64
    elf_header[58] = 64;

    fwrite(elf_header, 1, 64, out);
    // Write code section
    fwrite(buf->code, 1, buf->code_len, out);

    fclose(out);
    return 1;
}

// ============================================================================
// Machine Code Emission Stubs
// ============================================================================

void codegen_x86_64_emit(VInst* program, CodeBuffer* buf) {
    (void)program;
    (void)buf;
    // TODO: Full x86-64 machine code emission
    // For now, assembly text output is the primary path
}

void codegen_aarch64_emit(VInst* program, CodeBuffer* buf) {
    (void)program;
    (void)buf;
    // TODO: Full AArch64 machine code emission
}

void codegen_rv64_emit(VInst* program, CodeBuffer* buf) {
    (void)program;
    (void)buf;
    // TODO: Full RISC-V 64 machine code emission
}

// ============================================================================
// Public API
// ============================================================================

int compile_source_to_asm(const char* source, const char* input_path,
                          const char* output_path, CodegenTarget target,
                          int opt_level, int debug_info) {
    return write_asm_output(source, input_path, output_path, target, opt_level, debug_info);
}

int compile_source_to_native(const char* source, const char* input_path,
                             const char* output_path, CodegenTarget target,
                             int opt_level, int debug_info) {
    // Generate assembly, then assemble + link (secure temp file)
    char asm_path[] = "/tmp/sage_asm_XXXXXX.s";
    int asm_fd = mkstemps(asm_path, 2);
    if (asm_fd >= 0) close(asm_fd);

    if (!write_asm_output(source, input_path, asm_path, target, opt_level, debug_info)) {
        return 0;
    }

    // Assemble and link with cc
    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "Could not fork for assembly.\n");
        unlink(asm_path);
        return 0;
    }

    if (pid == 0) {
        execlp("cc", "cc", asm_path, "-o", output_path, "-lm", (char*)NULL);
        fprintf(stderr, "Could not execute assembler: %s\n", strerror(errno));
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "Could not wait for assembler.\n");
        unlink(asm_path);
        return 0;
    }

    unlink(asm_path);

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "Assembly/linking failed for target %s.\n", target_name(target));
        return 0;
    }

    return 1;
}
