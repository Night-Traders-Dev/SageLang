#ifndef SAGE_METAL_RV64_VM_H
#define SAGE_METAL_RV64_VM_H

// ============================================================================
// SageMetal RV64 VM — Freestanding RISC-V 64-bit Register-Based VM
// ============================================================================
// Companion to metal_vm.h (stack-based). Executes .sgrv (Sage RISC-V)
// binaries using fixed 32-bit RV64I instructions.
//
// Same constraints as MetalVM: no malloc, no libc, no OS.
// Uses fixed-size static pools for all allocations.
//
// Compile with: -ffreestanding -nostdlib -DSAGE_BARE_METAL -DSAGE_METAL_VM
// ============================================================================

#include "metal_vm.h"  // Reuse MetalValue, MetalArray, MetalDict, etc.

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// RV64I Major Opcode Groups (7-bit)
// ============================================================================

#define RV_OP_LUI       0x37    // 0110111
#define RV_OP_AUIPC     0x17    // 0010111
#define RV_OP_JAL       0x6F    // 1101111
#define RV_OP_JALR      0x67    // 1100111
#define RV_OP_BRANCH    0x63    // 1100011
#define RV_OP_LOAD      0x03    // 0000011
#define RV_OP_STORE     0x23    // 0100011
#define RV_OP_IMM       0x13    // 0010011
#define RV_OP_REG       0x33    // 0110011
#define RV_OP_LDC       0x5B    // 1011011  Custom-2: Load Constant (U-type)
#define RV_OP_VMSYS     0x73    // 1110011  SYSTEM repurposed for VM ops

// ============================================================================
// Funct3 for OP_BRANCH
// ============================================================================

#define RV_F3_BEQ       0x0
#define RV_F3_BNE       0x1
#define RV_F3_BLT       0x4
#define RV_F3_BGE       0x5
#define RV_F3_BLTU      0x6
#define RV_F3_BGEU      0x7

// ============================================================================
// Funct3 for OP_LOAD
// ============================================================================

#define RV_F3_LB        0x0
#define RV_F3_LH        0x1
#define RV_F3_LW        0x2
#define RV_F3_LD        0x3

// ============================================================================
// Funct3 for OP_STORE
// ============================================================================

#define RV_F3_SB        0x0
#define RV_F3_SH        0x1
#define RV_F3_SW        0x2
#define RV_F3_SD        0x3

// ============================================================================
// Funct3 for OP_IMM / OP_REG
// ============================================================================

#define RV_F3_ADD       0x0     // ADD/SUB/MUL (OP_REG), ADDI (OP_IMM)
#define RV_F3_SLL       0x1
#define RV_F3_SLT       0x2
#define RV_F3_SLTU      0x3
#define RV_F3_XOR       0x4     // XOR/DIV
#define RV_F3_SRL       0x5     // SRL/SRA/DIVU
#define RV_F3_OR        0x6     // OR/REM
#define RV_F3_AND       0x7     // AND/REMU

// ============================================================================
// Custom SageVM Opcodes (funct3 within OP_VMSYS)
// ============================================================================

#define RV_F3_VM_OPS    0x0
#define RV_F3_GPU_OPS   0x1
#define RV_F3_OBJ_OPS  0x2

// VM Ops (sub_op via rs1 field)
#define RV_VMO_NOP          0x00
#define RV_VMO_HALT         0x01
#define RV_VMO_PUSH_ENV     0x02
#define RV_VMO_POP_ENV      0x03
#define RV_VMO_CALL         0x04
#define RV_VMO_SETUP_TRY    0x05
#define RV_VMO_END_TRY      0x06
#define RV_VMO_RAISE        0x07
#define RV_VMO_IMPORT       0x08
#define RV_VMO_PRINT        0x09
#define RV_VMO_ARRAY_LEN    0x0A
#define RV_VMO_PRINTM       0x0B
#define RV_VMO_EXEC_AST     0x0C

// Object Ops (sub_op via rs1 field)
#define RV_OBJ_GET_GLOBAL   0x00
#define RV_OBJ_SET_GLOBAL   0x01
#define RV_OBJ_NEW_CLASS    0x02
#define RV_OBJ_INHERIT      0x03
#define RV_OBJ_METHOD_BIND  0x04
#define RV_OBJ_GET_PROP     0x05
#define RV_OBJ_SET_PROP     0x06
#define RV_OBJ_NEW_FUNC     0x07
#define RV_OBJ_ARRAY_NEW    0x08
#define RV_OBJ_DICT_NEW     0x09
#define RV_OBJ_TUPLE_NEW    0x0A
#define RV_OBJ_GET_INDEX    0x0B
#define RV_OBJ_SET_INDEX    0x0C
#define RV_OBJ_SLICE        0x0D

// ============================================================================
// Configuration
// ============================================================================

#ifndef RV64_STACK_SIZE
#define RV64_STACK_SIZE     1024    // Memory stack entries
#endif

#ifndef RV64_MAX_CHUNKS
#define RV64_MAX_CHUNKS     1024    // Maximum function chunks
#endif

#ifndef RV64_CALL_STACK_SIZE
#define RV64_CALL_STACK_SIZE 256    // Call stack depth
#endif

#ifndef RV64_TRY_STACK_SIZE
#define RV64_TRY_STACK_SIZE  128   // Exception handler stack depth
#endif

// ============================================================================
// Decoded Instruction
// ============================================================================

typedef struct {
    int opcode;         // bits [6:0]
    int rd;             // bits [11:7]
    int funct3;         // bits [14:12]
    int rs1;            // bits [19:15]
    int rs2;            // bits [24:20]
    int funct7;         // bits [31:25]
    int imm_i;          // I-type immediate (sign-extended)
    int imm_s;          // S-type immediate (sign-extended)
    int imm_b;          // B-type immediate (sign-extended)
    int imm_u;          // U-type immediate (upper 20 bits)
    int imm_j;          // J-type immediate (sign-extended)
} RV64Instruction;

// ============================================================================
// VM State
// ============================================================================

typedef struct {
    // Register file: 32 × 64-bit
    // Using MetalValue so registers can hold tagged values (numbers, strings, etc.)
    MetalValue x[32];

    // Program counter (byte offset into current chunk)
    int pc;
    int running;

    // Current chunk
    const unsigned char* bytecode;
    int bytecode_length;
    int current_chunk_idx;

    // All chunks
    const unsigned char* chunks[RV64_MAX_CHUNKS];
    int chunk_lengths[RV64_MAX_CHUNKS];
    int chunk_count;

    // Constant pool (shared with MetalVM format)
    MetalValue constants[METAL_CONST_POOL];
    int const_count;

    // Memory stack (for LOAD/STORE operations)
    MetalValue stack[RV64_STACK_SIZE];

    // Global variable storage (dict-based)
    int global_dict_idx;    // Index into dicts[] pool

    // Call stack: [chunk_idx, return_pc, saved_ra]
    struct {
        int chunk_idx;
        int return_pc;
        MetalValue saved_ra;
        int is_constructor;
        MetalValue constructor_instance;
    } call_stack[RV64_CALL_STACK_SIZE];
    int csp;

    // Exception handler stack: [catch_pc, call_stack_depth]
    struct {
        int catch_pc;
        int call_depth;
    } try_stack[RV64_TRY_STACK_SIZE];
    int tsp;

    // Object pools (reuse MetalVM pools)
    MetalArray arrays[METAL_POOL_SIZE / 8];
    int array_count;

    MetalDict dicts[METAL_POOL_SIZE / 16];
    int dict_count;

    MetalFunction functions[256];
    int fn_count;

    // String pool (bump allocator)
    char strings[METAL_STRING_POOL];
    int string_used;

    // Status
    int halted;
    int error;
    const char* error_msg;
    int trace;

    // I/O callbacks (set by host kernel/bootloader)
    void (*write_char)(char c);
    int  (*read_char)(void);
} MetalRV64VM;

// ============================================================================
// Public API
// ============================================================================

// Initialize VM state (zeroes all pools)
void metal_rv64_vm_init(MetalRV64VM* vm);

// Load compiled SGRV binary into VM
int metal_rv64_vm_load_binary(MetalRV64VM* vm, const unsigned char* data, int size);

// Execute until halt or error
int metal_rv64_vm_run(MetalRV64VM* vm);

// Execute a single instruction (for cooperative multitasking)
int metal_rv64_vm_step(MetalRV64VM* vm);

// Decode a 32-bit instruction word
RV64Instruction rv64_decode(unsigned int raw);

#ifdef __cplusplus
}
#endif

#endif // SAGE_METAL_RV64_VM_H
