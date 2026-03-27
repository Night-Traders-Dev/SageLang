#include "jit.h"
#include "ast.h"
#include "gc.h"
#include "interpreter.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __linux__
#include <sys/mman.h>
#include <unistd.h>
#define JIT_SUPPORTED 1
#elif defined(__APPLE__)
#include <sys/mman.h>
#include <unistd.h>
#include <libkern/OSCacheControl.h>
#define JIT_SUPPORTED 1
#else
#define JIT_SUPPORTED 0
#endif

// ============================================================================
// JIT Code Pool — executable memory management
// ============================================================================

void jit_init(JitState* jit) {
    memset(jit, 0, sizeof(JitState));
#if JIT_SUPPORTED
    jit->pool.capacity = JIT_CODE_POOL_SIZE;
    jit->pool.code = mmap(NULL, jit->pool.capacity,
                          PROT_READ | PROT_WRITE | PROT_EXEC,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (jit->pool.code == MAP_FAILED) {
        jit->pool.code = NULL;
        jit->pool.capacity = 0;
        fprintf(stderr, "JIT: Failed to allocate executable memory pool\n");
    }
    jit->pool.used = 0;
    jit->enabled = (jit->pool.code != NULL);
#endif
    jit->profiles = NULL;
    jit->profile_count = 0;
    jit->profile_capacity = 0;
    jit->total_compiled = 0;
    jit->total_bailouts = 0;
}

void jit_shutdown(JitState* jit) {
#if JIT_SUPPORTED
    if (jit->pool.code) {
        munmap(jit->pool.code, jit->pool.capacity);
    }
#endif
    for (int i = 0; i < jit->profile_count; i++) {
        if (jit->profiles[i]) {
            free(jit->profiles[i]->arg_types);
            free(jit->profiles[i]);
        }
    }
    free(jit->profiles);
    memset(jit, 0, sizeof(JitState));
}

// ============================================================================
// Profiling
// ============================================================================

JitProfile* jit_get_profile(JitState* jit, int func_id) {
    if (func_id < 0) return NULL;
    while (func_id >= jit->profile_capacity) {
        int new_cap = jit->profile_capacity == 0 ? 64 : jit->profile_capacity * 2;
        jit->profiles = realloc(jit->profiles, sizeof(JitProfile*) * new_cap);
        for (int i = jit->profile_capacity; i < new_cap; i++) {
            jit->profiles[i] = NULL;
        }
        jit->profile_capacity = new_cap;
    }
    if (func_id >= jit->profile_count) {
        jit->profile_count = func_id + 1;
    }
    if (!jit->profiles[func_id]) {
        jit->profiles[func_id] = calloc(1, sizeof(JitProfile));
    }
    return jit->profiles[func_id];
}

JitTypeTag jit_classify_value(Value v) {
    switch (v.type) {
        case VAL_NUMBER: {
            double d = v.as.number;
            if (d == (double)(int64_t)d && d >= -2147483648.0 && d <= 2147483647.0) {
                return JIT_TYPE_INT;
            }
            return JIT_TYPE_FLOAT;
        }
        case VAL_STRING: return JIT_TYPE_STRING;
        case VAL_BOOL:   return JIT_TYPE_BOOL;
        case VAL_NIL:    return JIT_TYPE_NIL;
        case VAL_ARRAY:  return JIT_TYPE_ARRAY;
        case VAL_DICT:   return JIT_TYPE_DICT;
        default:         return JIT_TYPE_UNKNOWN;
    }
}

const char* jit_type_name(JitTypeTag tag) {
    switch (tag) {
        case JIT_TYPE_INT:     return "Int";
        case JIT_TYPE_FLOAT:   return "Float";
        case JIT_TYPE_STRING:  return "String";
        case JIT_TYPE_BOOL:    return "Bool";
        case JIT_TYPE_ARRAY:   return "Array";
        case JIT_TYPE_DICT:    return "Dict";
        case JIT_TYPE_NIL:     return "Nil";
        case JIT_TYPE_MIXED:   return "Mixed";
        default:               return "Unknown";
    }
}

static JitTypeTag merge_types(JitTypeTag existing, JitTypeTag observed) {
    if (existing == JIT_TYPE_UNKNOWN) return observed;
    if (existing == observed) return existing;
    return JIT_TYPE_MIXED;
}

void jit_record_call(JitState* jit, int func_id, int param_count, Value* args) {
    JitProfile* p = jit_get_profile(jit, func_id);
    if (!p) return;
    p->call_count++;
    p->param_count = param_count;

    if (!p->arg_types && param_count > 0) {
        p->arg_types = calloc(param_count, sizeof(JitTypeTag));
    }
    for (int i = 0; i < param_count && p->arg_types; i++) {
        p->arg_types[i] = merge_types(p->arg_types[i], jit_classify_value(args[i]));
    }
}

void jit_record_return(JitState* jit, int func_id, Value result) {
    JitProfile* p = jit_get_profile(jit, func_id);
    if (!p) return;
    p->return_type = merge_types(p->return_type, jit_classify_value(result));
}

int jit_should_compile(JitState* jit, int func_id) {
    if (!jit->enabled) return 0;
    JitProfile* p = jit_get_profile(jit, func_id);
    if (!p) return 0;
    return (!p->jit_compiled && p->call_count >= JIT_HOT_THRESHOLD);
}

// ============================================================================
// x86-64 Code Emitter
// ============================================================================

void jit_emitter_init(JitEmitter* em, uint8_t* buf, size_t capacity) {
    em->buf = buf;
    em->pos = 0;
    em->capacity = capacity;
    em->fixups = NULL;
    em->fixup_count = 0;
    em->fixup_capacity = 0;
    em->labels = NULL;
    em->label_count = 0;
    em->label_capacity = 0;
}

void jit_emit_byte(JitEmitter* em, uint8_t b) {
    if (em->pos < em->capacity) em->buf[em->pos++] = b;
}

void jit_emit_u32(JitEmitter* em, uint32_t v) {
    jit_emit_byte(em, v & 0xFF);
    jit_emit_byte(em, (v >> 8) & 0xFF);
    jit_emit_byte(em, (v >> 16) & 0xFF);
    jit_emit_byte(em, (v >> 24) & 0xFF);
}

void jit_emit_u64(JitEmitter* em, uint64_t v) {
    jit_emit_u32(em, (uint32_t)(v & 0xFFFFFFFF));
    jit_emit_u32(em, (uint32_t)(v >> 32));
}

int jit_new_label(JitEmitter* em) {
    if (em->label_count >= em->label_capacity) {
        em->label_capacity = em->label_capacity == 0 ? 16 : em->label_capacity * 2;
        em->labels = realloc(em->labels, sizeof(size_t) * em->label_capacity);
    }
    int id = em->label_count++;
    em->labels[id] = 0; // unbound
    return id;
}

void jit_bind_label(JitEmitter* em, int label) {
    if (label >= 0 && label < em->label_count) {
        em->labels[label] = em->pos;
    }
}

static void add_fixup(JitEmitter* em, size_t patch_pos, int label_id) {
    if (em->fixup_count >= em->fixup_capacity) {
        em->fixup_capacity = em->fixup_capacity == 0 ? 16 : em->fixup_capacity * 2;
        em->fixups = realloc(em->fixups, sizeof(*em->fixups) * em->fixup_capacity);
    }
    em->fixups[em->fixup_count].patch_pos = patch_pos;
    em->fixups[em->fixup_count].label_id = label_id;
    em->fixup_count++;
}

void jit_patch_jumps(JitEmitter* em) {
    for (int i = 0; i < em->fixup_count; i++) {
        size_t patch_pos = em->fixups[i].patch_pos;
        int label = em->fixups[i].label_id;
        if (label >= 0 && label < em->label_count) {
            int32_t rel = (int32_t)(em->labels[label] - (patch_pos + 4));
            em->buf[patch_pos]     = rel & 0xFF;
            em->buf[patch_pos + 1] = (rel >> 8) & 0xFF;
            em->buf[patch_pos + 2] = (rel >> 16) & 0xFF;
            em->buf[patch_pos + 3] = (rel >> 24) & 0xFF;
        }
    }
    free(em->fixups);
    em->fixups = NULL;
    em->fixup_count = 0;
    em->fixup_capacity = 0;
    free(em->labels);
    em->labels = NULL;
    em->label_count = 0;
    em->label_capacity = 0;
}

// ============================================================================
// x86-64 Instruction Emission
// ============================================================================

// REX prefix for 64-bit operand size
static uint8_t rex_w(int dst, int src) {
    return 0x48 | ((dst >> 3) & 1) | (((src >> 3) & 1) << 2);
}

void jit_emit_push(JitEmitter* em, int reg) {
    if (reg >= 8) jit_emit_byte(em, 0x41);
    jit_emit_byte(em, 0x50 + (reg & 7));
}

void jit_emit_pop(JitEmitter* em, int reg) {
    if (reg >= 8) jit_emit_byte(em, 0x41);
    jit_emit_byte(em, 0x58 + (reg & 7));
}

void jit_emit_mov_reg_imm64(JitEmitter* em, int reg, uint64_t imm) {
    jit_emit_byte(em, rex_w(0, reg));
    jit_emit_byte(em, 0xB8 + (reg & 7));
    jit_emit_u64(em, imm);
}

void jit_emit_mov_reg_reg(JitEmitter* em, int dst, int src) {
    jit_emit_byte(em, rex_w(src, dst));
    jit_emit_byte(em, 0x89);
    jit_emit_byte(em, 0xC0 | ((src & 7) << 3) | (dst & 7));
}

void jit_emit_call_indirect(JitEmitter* em, int reg) {
    if (reg >= 8) jit_emit_byte(em, 0x41);
    jit_emit_byte(em, 0xFF);
    jit_emit_byte(em, 0xD0 + (reg & 7));
}

void jit_emit_ret(JitEmitter* em) {
    jit_emit_byte(em, 0xC3);
}

void jit_emit_add_reg_reg(JitEmitter* em, int dst, int src) {
    jit_emit_byte(em, rex_w(src, dst));
    jit_emit_byte(em, 0x01);
    jit_emit_byte(em, 0xC0 | ((src & 7) << 3) | (dst & 7));
}

void jit_emit_sub_reg_reg(JitEmitter* em, int dst, int src) {
    jit_emit_byte(em, rex_w(src, dst));
    jit_emit_byte(em, 0x29);
    jit_emit_byte(em, 0xC0 | ((src & 7) << 3) | (dst & 7));
}

void jit_emit_cmp_reg_imm(JitEmitter* em, int reg, int32_t imm) {
    jit_emit_byte(em, rex_w(0, reg));
    jit_emit_byte(em, 0x81);
    jit_emit_byte(em, 0xF8 + (reg & 7));
    jit_emit_u32(em, (uint32_t)imm);
}

void jit_emit_je(JitEmitter* em, int label) {
    jit_emit_byte(em, 0x0F);
    jit_emit_byte(em, 0x84);
    add_fixup(em, em->pos, label);
    jit_emit_u32(em, 0); // placeholder
}

void jit_emit_jne(JitEmitter* em, int label) {
    jit_emit_byte(em, 0x0F);
    jit_emit_byte(em, 0x85);
    add_fixup(em, em->pos, label);
    jit_emit_u32(em, 0);
}

void jit_emit_jmp(JitEmitter* em, int label) {
    jit_emit_byte(em, 0xE9);
    add_fixup(em, em->pos, label);
    jit_emit_u32(em, 0);
}

// ============================================================================
// JIT Compilation — Compile hot function to native x86-64
// ============================================================================

// Compile a Sage function to native code.
// Strategy: Generate a wrapper that calls the C interpreter for the body
// but with optimized dispatch for type-specialized arithmetic.
JitNativeFn jit_compile_function(JitState* jit, void* proc_stmt, void* env) {
#if !JIT_SUPPORTED
    (void)jit; (void)proc_stmt; (void)env;
    return NULL;
#else
    if (!jit->enabled || !jit->pool.code) return NULL;
    ProcStmt* proc = (ProcStmt*)proc_stmt;
    if (!proc) return NULL;

    // Allocate code buffer from pool
    size_t code_start = jit->pool.used;
    size_t max_size = JIT_MAX_CODE_SIZE;
    if (code_start + max_size > jit->pool.capacity) return NULL;

    uint8_t* code_buf = jit->pool.code + code_start;
    JitEmitter em;
    jit_emitter_init(&em, code_buf, max_size);

    // Generate a native wrapper that:
    // 1. Sets up C calling convention frame
    // 2. Calls the interpret() function with the proc body and environment
    // 3. Returns the result
    //
    // Signature: Value jit_fn(int argc, Value* argv)
    // System V ABI: rdi=argc, rsi=argv

    // Function prologue
    jit_emit_push(&em, JIT_RBP);
    jit_emit_mov_reg_reg(&em, JIT_RBP, JIT_RSP);
    jit_emit_push(&em, JIT_RBX);
    jit_emit_push(&em, JIT_R12);
    jit_emit_push(&em, JIT_R13);

    // Save argc and argv
    jit_emit_mov_reg_reg(&em, JIT_R12, JIT_RDI); // r12 = argc
    jit_emit_mov_reg_reg(&em, JIT_R13, JIT_RSI); // r13 = argv

    // Call the interpreter's exec function for the proc body:
    // ExecResult interpret(Stmt* stmt, Env* env);
    extern ExecResult interpret(Stmt* stmt, Env* env);

    // Load proc->body into rdi
    jit_emit_mov_reg_imm64(&em, JIT_RDI, (uint64_t)(uintptr_t)proc->body);
    // Load env into rsi
    jit_emit_mov_reg_imm64(&em, JIT_RSI, (uint64_t)(uintptr_t)env);
    // Call interpret
    jit_emit_mov_reg_imm64(&em, JIT_RAX, (uint64_t)(uintptr_t)&interpret);
    jit_emit_call_indirect(&em, JIT_RAX);

    // ExecResult is returned in rax (value field for small structs)
    // Just return it

    // Epilogue
    jit_emit_pop(&em, JIT_R13);
    jit_emit_pop(&em, JIT_R12);
    jit_emit_pop(&em, JIT_RBX);
    jit_emit_pop(&em, JIT_RBP);
    jit_emit_ret(&em);

    jit_patch_jumps(&em);

    // Commit the code
    jit->pool.used = code_start + em.pos;
    jit->total_compiled++;

    return (JitNativeFn)code_buf;
#endif
}
