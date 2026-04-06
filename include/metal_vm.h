#ifndef SAGE_METAL_VM_H
#define SAGE_METAL_VM_H

// ============================================================================
// SageMetal VM — Freestanding Bytecode Virtual Machine
// ============================================================================
// A minimal bytecode interpreter that runs on bare-metal (no OS, no libc,
// no malloc). Uses fixed-size static pools for all allocations.
//
// Designed for: kernels, bootloaders, embedded systems, OS development
// Targets: x86-64, aarch64, rv64 (freestanding)
//
// Compile with: -ffreestanding -nostdlib -DSAGE_BARE_METAL -DSAGE_METAL_VM
// ============================================================================

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Configuration — tune for your target's memory constraints
// ============================================================================

#ifndef METAL_STACK_SIZE
#define METAL_STACK_SIZE      512     // Value stack depth
#endif

#ifndef METAL_POOL_SIZE
#define METAL_POOL_SIZE       4096    // Object pool entries
#endif

#ifndef METAL_STRING_POOL
#define METAL_STRING_POOL     32768   // String storage bytes
#endif

#ifndef METAL_HEAP_SIZE
#define METAL_HEAP_SIZE       65536   // General heap bytes (bump allocator)
#endif

#ifndef METAL_CONST_POOL
#define METAL_CONST_POOL      1024    // Constant pool entries
#endif

#ifndef METAL_ENV_DEPTH
#define METAL_ENV_DEPTH       64      // Maximum scope chain depth
#endif

#ifndef METAL_VARS_PER_SCOPE
#define METAL_VARS_PER_SCOPE  32      // Variables per scope level
#endif

// ============================================================================
// Value representation — compact 16-byte tagged union
// ============================================================================

typedef enum {
    MV_NIL = 0,
    MV_NUM,         // IEEE 754 double
    MV_BOOL,        // 0 or 1
    MV_STR,         // Index into string pool
    MV_ARR,         // Index into array pool
    MV_DICT,        // Index into dict pool
    MV_FN,          // Index into function table
    MV_PTR,         // Raw pointer (for MMIO, DMA)
} MetalValueType;

typedef struct {
    MetalValueType type;
    union {
        double number;
        int boolean;
        int str_idx;        // String pool index
        int arr_idx;        // Array pool index
        int dict_idx;       // Dict pool index
        int fn_idx;         // Function table index
        void* ptr;          // Raw pointer for bare-metal I/O
    } as;
} MetalValue;

// ============================================================================
// Metal Array — fixed-capacity array in pool
// ============================================================================

#define METAL_ARRAY_MAX_ELEMS 256

typedef struct {
    MetalValue elems[METAL_ARRAY_MAX_ELEMS];
    int count;
    int in_use;
} MetalArray;

// ============================================================================
// Metal Dict — fixed-capacity key-value store in pool
// ============================================================================

#define METAL_DICT_MAX_ENTRIES 64

typedef struct {
    int key_str_idx[METAL_DICT_MAX_ENTRIES];    // String pool indices for keys
    MetalValue values[METAL_DICT_MAX_ENTRIES];
    int count;
    int in_use;
} MetalDict;

// ============================================================================
// Metal Function — bytecode function reference
// ============================================================================

typedef struct {
    int code_offset;    // Offset into bytecode stream
    int code_length;    // Length of function bytecode
    int param_count;    // Number of parameters
    int scope_depth;    // Scope depth at definition
} MetalFunction;

// ============================================================================
// Metal Environment — flat scope chain (no linked lists, no malloc)
// ============================================================================

typedef struct {
    int name_hash[METAL_VARS_PER_SCOPE];    // FNV-1a hash of variable name
    MetalValue values[METAL_VARS_PER_SCOPE];
    int count;
} MetalScope;

// ============================================================================
// Metal VM State — all static, zero dynamic allocation
// ============================================================================

typedef struct {
    // Value stack
    MetalValue stack[METAL_STACK_SIZE];
    int sp;                                  // Stack pointer

    // Bytecode
    const unsigned char* code;               // Bytecode stream
    int code_length;
    int ip;                                  // Instruction pointer

    // Constant pool
    MetalValue constants[METAL_CONST_POOL];
    int const_count;

    // Scope chain (flat array, not linked list)
    MetalScope scopes[METAL_ENV_DEPTH];
    int scope_depth;

    // Object pools (no malloc — fixed-size arenas)
    MetalArray arrays[METAL_POOL_SIZE / 8];
    int array_count;

    MetalDict dicts[METAL_POOL_SIZE / 16];
    int dict_count;

    MetalFunction functions[256];
    int fn_count;

    // String pool (bump allocator)
    char strings[METAL_STRING_POOL];
    int string_used;

    // General-purpose heap (bump allocator for misc)
    unsigned char heap[METAL_HEAP_SIZE];
    int heap_used;

    // Status
    int halted;
    int error;
    const char* error_msg;

    // I/O callbacks (set by the host kernel/bootloader)
    void (*write_char)(char c);              // Serial/console output
    int  (*read_char)(void);                 // Serial/console input (-1 if none)
    void (*write_port)(int port, int val);   // Port I/O (x86)
    int  (*read_port)(int port);             // Port I/O (x86)
    void* (*map_mmio)(unsigned long phys, unsigned long size); // MMIO mapping
} MetalVM;

// ============================================================================
// Public API
// ============================================================================

// Initialize VM state (zeroes all pools)
void metal_vm_init(MetalVM* vm);

// Load bytecode into VM
void metal_vm_load(MetalVM* vm, const unsigned char* code, int length);

// Add a constant to the constant pool
int metal_vm_add_constant(MetalVM* vm, MetalValue value);

// Execute bytecode until halt or error
int metal_vm_run(MetalVM* vm);

// Execute a single instruction (for cooperative multitasking)
int metal_vm_step(MetalVM* vm);

// Value constructors
MetalValue mv_nil(void);
MetalValue mv_num(double v);
MetalValue mv_bool(int v);
MetalValue mv_str(MetalVM* vm, const char* s, int len);
MetalValue mv_ptr(void* p);

// Stack operations
int metal_vm_push(MetalVM* vm, MetalValue value);
MetalValue metal_vm_pop(MetalVM* vm);
MetalValue metal_vm_peek(MetalVM* vm, int distance);

// String pool
int metal_string_intern(MetalVM* vm, const char* s, int len);
const char* metal_string_get(MetalVM* vm, int idx);

// Array pool
int metal_array_new(MetalVM* vm);
void metal_array_push(MetalVM* vm, int arr_idx, MetalValue val);
MetalValue metal_array_get(MetalVM* vm, int arr_idx, int index);
int metal_array_len(MetalVM* vm, int arr_idx);

// Print (uses write_char callback)
void metal_print_value(MetalVM* vm, MetalValue value);

#ifdef __cplusplus
}
#endif

#endif // SAGE_METAL_VM_H
