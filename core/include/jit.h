#ifndef SAGE_JIT_H
#define SAGE_JIT_H

#include "value.h"
#include <stdint.h>
#include <stddef.h>

// ============================================================================
// JIT Compiler for Sage
//
// Architecture: Method-level JIT with profiling counters.
// - Profiling: Counts function entries and loop iterations
// - Compilation: Hot functions compiled to x86-64 machine code
// - Integration: JIT code callable from interpreter/VM via function pointer
// - Tiered: Interpreter → Profiled Bytecode → JIT Native
// ============================================================================

// JIT compilation thresholds
#define JIT_HOT_THRESHOLD       100   // Calls before JIT compilation
#define JIT_LOOP_HOT_THRESHOLD  50    // Loop iterations before OSR
#define JIT_MAX_CODE_SIZE       (1024 * 1024)  // 1MB per function
#define JIT_CODE_POOL_SIZE      (16 * 1024 * 1024)  // 16MB total

// Type feedback tags for specialization
typedef enum {
    JIT_TYPE_UNKNOWN  = 0,
    JIT_TYPE_INT      = 1,   // Observed only integers (doubles with no fractional part)
    JIT_TYPE_FLOAT    = 2,   // Observed floats
    JIT_TYPE_STRING   = 3,
    JIT_TYPE_BOOL     = 4,
    JIT_TYPE_ARRAY    = 5,
    JIT_TYPE_DICT     = 6,
    JIT_TYPE_NIL      = 7,
    JIT_TYPE_MIXED    = 8,   // Multiple types observed — can't specialize
} JitTypeTag;

// Per-function profiling data
typedef struct {
    int call_count;           // Number of times function was called
    int jit_compiled;         // 1 if already JIT compiled
    void* native_code;        // Pointer to JIT-compiled machine code
    size_t native_size;       // Size of compiled code
    JitTypeTag* arg_types;    // Observed argument types (per parameter)
    JitTypeTag return_type;   // Observed return type
    int param_count;
} JitProfile;

// x86-64 code buffer
typedef struct {
    uint8_t* code;            // Executable memory (mmap'd)
    size_t capacity;
    size_t used;
} JitCodePool;

// x86-64 code emitter
typedef struct {
    uint8_t* buf;
    size_t pos;
    size_t capacity;
    // Fixup table for forward jumps
    struct { size_t patch_pos; int label_id; } *fixups;
    int fixup_count;
    int fixup_capacity;
    // Label positions
    size_t* labels;
    int label_count;
    int label_capacity;
} JitEmitter;

// JIT compiler state
typedef struct {
    JitCodePool pool;
    JitProfile** profiles;    // Indexed by function ID
    int profile_count;
    int profile_capacity;
    int enabled;
    int total_compiled;
    int total_bailouts;
} JitState;

// Lifecycle
void jit_init(JitState* jit);
void jit_shutdown(JitState* jit);

// Profiling
JitProfile* jit_get_profile(JitState* jit, int func_id);
void jit_record_call(JitState* jit, int func_id, int param_count, Value* args);
void jit_record_return(JitState* jit, int func_id, Value result);
int jit_should_compile(JitState* jit, int func_id);

// Type feedback
JitTypeTag jit_classify_value(Value v);
const char* jit_type_name(JitTypeTag tag);

// Code emission (x86-64)
void jit_emitter_init(JitEmitter* em, uint8_t* buf, size_t capacity);
void jit_emit_byte(JitEmitter* em, uint8_t b);
void jit_emit_u32(JitEmitter* em, uint32_t v);
void jit_emit_u64(JitEmitter* em, uint64_t v);
int  jit_new_label(JitEmitter* em);
void jit_bind_label(JitEmitter* em, int label);
void jit_patch_jumps(JitEmitter* em);

// x86-64 instruction helpers
void jit_emit_push(JitEmitter* em, int reg);
void jit_emit_pop(JitEmitter* em, int reg);
void jit_emit_mov_reg_imm64(JitEmitter* em, int reg, uint64_t imm);
void jit_emit_mov_reg_reg(JitEmitter* em, int dst, int src);
void jit_emit_call_indirect(JitEmitter* em, int reg);
void jit_emit_ret(JitEmitter* em);
void jit_emit_add_reg_reg(JitEmitter* em, int dst, int src);
void jit_emit_sub_reg_reg(JitEmitter* em, int dst, int src);
void jit_emit_cmp_reg_imm(JitEmitter* em, int reg, int32_t imm);
void jit_emit_je(JitEmitter* em, int label);
void jit_emit_jne(JitEmitter* em, int label);
void jit_emit_jmp(JitEmitter* em, int label);

// Compilation
typedef Value (*JitNativeFn)(int argc, Value* argv);
JitNativeFn jit_compile_function(JitState* jit, void* proc_stmt, void* env);

// x86-64 register names
#define JIT_RAX 0
#define JIT_RCX 1
#define JIT_RDX 2
#define JIT_RBX 3
#define JIT_RSP 4
#define JIT_RBP 5
#define JIT_RSI 6
#define JIT_RDI 7
#define JIT_R8  8
#define JIT_R9  9
#define JIT_R10 10
#define JIT_R11 11
#define JIT_R12 12
#define JIT_R13 13
#define JIT_R14 14
#define JIT_R15 15

#endif // SAGE_JIT_H
