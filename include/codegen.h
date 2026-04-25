#ifndef SAGE_CODEGEN_H
#define SAGE_CODEGEN_H

#include <stddef.h>
#include <stdint.h>

// ============================================================================
// Target Architecture
// ============================================================================

typedef enum {
    CODEGEN_TARGET_X86_64,
    CODEGEN_TARGET_AARCH64,
    CODEGEN_TARGET_RV64,
} CodegenTarget;

typedef enum {
    CODEGEN_PROFILE_HOSTED,
    CODEGEN_PROFILE_BARE_METAL,
    CODEGEN_PROFILE_OSDEV,
    CODEGEN_PROFILE_UEFI,
} CodegenProfile;

typedef struct {
    CodegenTarget target;
    CodegenProfile profile;
} CodegenTargetSpec;

// ============================================================================
// Virtual Instruction IR (target-independent)
// ============================================================================

typedef enum {
    VINST_NOP,
    VINST_LOAD_IMM,        // vreg = immediate double
    VINST_LOAD_STRING,     // vreg = string literal
    VINST_LOAD_BOOL,       // vreg = boolean
    VINST_LOAD_NIL,        // vreg = nil
    VINST_LOAD_GLOBAL,     // vreg = global[name]
    VINST_STORE_GLOBAL,    // global[name] = vreg
    VINST_LOAD_LOCAL,      // vreg = local[slot]
    VINST_STORE_LOCAL,     // local[slot] = vreg
    VINST_ADD,             // vreg = vreg + vreg
    VINST_SUB,             // vreg = vreg - vreg
    VINST_MUL,             // vreg = vreg * vreg
    VINST_DIV,             // vreg = vreg / vreg
    VINST_MOD,             // vreg = vreg % vreg
    VINST_NEG,             // vreg = -vreg
    VINST_NOT,             // vreg = !vreg
    VINST_EQ,              // vreg = (vreg == vreg)
    VINST_NEQ,             // vreg = (vreg != vreg)
    VINST_LT,              // vreg = (vreg < vreg)
    VINST_GT,              // vreg = (vreg > vreg)
    VINST_LTE,             // vreg = (vreg <= vreg)
    VINST_GTE,             // vreg = (vreg >= vreg)
    VINST_AND,             // vreg = vreg && vreg
    VINST_OR,              // vreg = vreg || vreg
    VINST_CALL,            // vreg = call func(args...)
    VINST_CALL_BUILTIN,    // vreg = call builtin(args...)
    VINST_RET,             // return vreg
    VINST_BRANCH,          // if vreg goto label_true else label_false
    VINST_JUMP,            // goto label
    VINST_LABEL,           // label:
    VINST_PRINT,           // print vreg
    VINST_ARRAY_NEW,       // vreg = new array(count)
    VINST_ARRAY_SET,       // array[idx] = vreg
    VINST_INDEX,           // vreg = array[idx]
    VINST_PHI,             // vreg = phi(vreg_a, label_a, vreg_b, label_b)
} VInstKind;

typedef struct VInst {
    VInstKind kind;
    int dest;               // destination virtual register
    int src1, src2;         // source virtual registers
    double imm_number;
    char* imm_string;
    int imm_bool;
    char* label;            // for VINST_LABEL, VINST_JUMP, VINST_BRANCH
    char* label_false;      // for VINST_BRANCH (false target)
    char* func_name;        // for VINST_CALL
    int* call_args;         // virtual regs for call arguments
    int call_arg_count;
    struct VInst* next;
} VInst;

// ============================================================================
// Code Buffer - holds emitted machine code bytes
// ============================================================================

typedef struct {
    uint8_t* code;
    size_t code_len;
    size_t code_cap;
    // Data section for string literals etc.
    uint8_t* data;
    size_t data_len;
    size_t data_cap;
} CodeBuffer;

void codebuf_init(CodeBuffer* buf);
void codebuf_free(CodeBuffer* buf);
void codebuf_emit8(CodeBuffer* buf, uint8_t byte);
void codebuf_emit16(CodeBuffer* buf, uint16_t val);
void codebuf_emit32(CodeBuffer* buf, uint32_t val);
void codebuf_emit64(CodeBuffer* buf, uint64_t val);
void codebuf_emit_data(CodeBuffer* buf, const uint8_t* data, size_t len);

// ============================================================================
// VInst construction helpers
// ============================================================================

VInst* vinst_new(VInstKind kind);
void vinst_free_list(VInst* head);

// ============================================================================
// Instruction Selection (AST -> VInst IR)
// ============================================================================

typedef struct {
    VInst* head;
    VInst* tail;
    int next_vreg;
    int next_label;
    // String literal pool
    char** string_pool;
    int string_pool_count;
    int string_pool_cap;
    // Number pool for constants
    double* number_pool;
    int number_pool_count;
    int number_pool_cap;
    // Loop label stack for break/continue
    char* loop_cond_labels[64];
    char* loop_end_labels[64];
    int loop_depth;
    char* current_module;
    char** imported_modules;
    int imported_module_count;
} ISelContext;

void isel_init(ISelContext* ctx);
void isel_free(ISelContext* ctx);
VInst* isel_compile(const char* source, const char* input_path, int opt_level, int debug_info);

// ============================================================================
// Target-specific code emission
// ============================================================================

void codegen_x86_64_emit(VInst* program, CodeBuffer* buf);
void codegen_aarch64_emit(VInst* program, CodeBuffer* buf);
void codegen_rv64_emit(VInst* program, CodeBuffer* buf);

// ============================================================================
// ELF object file writer
// ============================================================================

int elf_write_object(const char* output_path, CodeBuffer* buf, CodegenTarget target);

// ============================================================================
// High-level API
// ============================================================================

int compile_source_to_asm(const char* source, const char* input_path,
                          const char* output_path, CodegenTargetSpec spec,
                          int opt_level, int debug_info);

int compile_source_to_native(const char* source, const char* input_path,
                             const char* output_path, CodegenTargetSpec spec,
                             int opt_level, int debug_info);

// Detect host target
CodegenTarget codegen_detect_host_target(void);
const char* codegen_profile_name(CodegenProfile profile);

#endif
