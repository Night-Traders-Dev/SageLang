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
// Bytecode opcodes — matching src/vm/bytecode.h
// ============================================================================

#define OP_CONSTANT       0
#define OP_NIL            1
#define OP_TRUE           2
#define OP_FALSE          3
#define OP_POP            4
#define OP_GET_GLOBAL     5
#define OP_DEFINE_GLOBAL  6
#define OP_SET_GLOBAL     7
#define OP_DEFINE_FN      8
#define OP_GET_PROPERTY   9
#define OP_SET_PROPERTY   10
#define OP_GET_INDEX      11
#define OP_SET_INDEX      12
#define OP_LOAD_FUNCTION  13
#define OP_SLICE          14
#define OP_ADD            15
#define OP_SUB            16
#define OP_MUL            17
#define OP_DIV            18
#define OP_MOD            19
#define OP_NEGATE         20
#define OP_EQUAL          21
#define OP_NOT_EQUAL      22
#define OP_GREATER        23
#define OP_GREATER_EQUAL  24
#define OP_LESS           25
#define OP_LESS_EQUAL     26
#define OP_BIT_AND        27
#define OP_BIT_OR         28
#define OP_BIT_XOR        29
#define OP_BIT_NOT        30
#define OP_SHIFT_LEFT     31
#define OP_SHIFT_RIGHT    32
#define OP_NOT            33
#define OP_TRUTHY         34
#define OP_JUMP           35
#define OP_JUMP_IF_FALSE  36
#define OP_CALL           37
#define OP_CALL_METHOD    38
#define OP_ARRAY          39
#define OP_TUPLE          40
#define OP_DICT           41
#define OP_PRINT          42
#define OP_EXEC_AST_STMT  43
#define OP_RETURN         44
#define OP_PUSH_ENV       45
#define OP_POP_ENV        46
#define OP_DUP            47
#define OP_ARRAY_LEN      48
#define OP_BREAK          49
#define OP_CONTINUE       50
#define OP_LOOP_BACK      51
#define OP_IMPORT         52
#define OP_CLASS          53
#define OP_METHOD         54
#define OP_INHERIT        55
#define OP_SETUP_TRY      56
#define OP_END_TRY        57
#define OP_RAISE          58

// GPU hot-path opcodes (Phase 16)
#define OP_GPU_POLL_EVENTS         59
#define OP_GPU_WINDOW_SHOULD_CLOSE 60
#define OP_GPU_GET_TIME            61
#define OP_GPU_KEY_PRESSED         62
#define OP_GPU_KEY_DOWN            63
#define OP_GPU_MOUSE_POS           64
#define OP_GPU_MOUSE_DELTA         65
#define OP_GPU_UPDATE_INPUT        66
#define OP_GPU_BEGIN_COMMANDS      67
#define OP_GPU_END_COMMANDS        68
#define OP_GPU_CMD_BEGIN_RP        69
#define OP_GPU_CMD_END_RP          70
#define OP_GPU_CMD_DRAW            71
#define OP_GPU_CMD_BIND_GP         72
#define OP_GPU_CMD_BIND_DS         73
#define OP_GPU_CMD_SET_VP          74
#define OP_GPU_CMD_SET_SC          75
#define OP_GPU_CMD_BIND_VB         76
#define OP_GPU_CMD_BIND_IB         77
#define OP_GPU_CMD_DRAW_IDX        78
#define OP_GPU_SUBMIT_SYNC         79
#define OP_GPU_ACQUIRE_IMG         80
#define OP_GPU_PRESENT             81
#define OP_GPU_WAIT_FENCE          82
#define OP_GPU_RESET_FENCE         83
#define OP_GPU_UPDATE_UNIFORM      84
#define OP_GPU_CMD_PUSH_CONST      85
#define OP_GPU_CMD_DISPATCH         86

#define OP_HALT           0xFF

// ============================================================================
// Configuration — tune for your target's memory constraints
// ============================================================================

#ifndef METAL_STACK_SIZE
#define METAL_STACK_SIZE      4096    // Value stack depth
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
#define METAL_ENV_DEPTH       1024    // Maximum scope chain depth
#endif

#ifndef METAL_VARS_PER_SCOPE
#define METAL_VARS_PER_SCOPE  128     // Variables per scope level
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
    int call_count;     // JIT profiling: entry execution count
    int jit_compiled;   // 1 if JIT compiled, 0 otherwise
    void* native_code;  // Pointer to JIT compiled native machine code
} MetalFunction;

// ============================================================================
// Metal Environment — flat scope chain (no linked lists, no malloc)
// ============================================================================

typedef struct {
    int name_hash[METAL_VARS_PER_SCOPE];    // FNV-1a hash of variable name
    MetalValue values[METAL_VARS_PER_SCOPE];
    int count;
} MetalScope;

#ifndef METAL_CALL_STACK_SIZE
#define METAL_CALL_STACK_SIZE 256     // Call stack depth
#endif

// ============================================================================
// Value representation — compact 16-byte tagged union
// ============================================================================

typedef struct {
    // Value stack
    MetalValue stack[METAL_STACK_SIZE];
    int sp;                                  // Stack pointer

    // Call stack (for functions/chunks)
    struct {
        int ip;
        const unsigned char* code;
        int code_length;
    } call_stack[METAL_CALL_STACK_SIZE];
    int csp;

    // Bytecode (current chunk)
    const unsigned char* code;
    int code_length;
    int ip;                                  // Instruction pointer

    // Constant pool
    MetalValue constants[METAL_CONST_POOL];
    int const_count;

    // Chunks (top-level segments)
    const unsigned char* chunks[1024];
    int chunk_lengths[1024];
    int chunk_count;

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

    // Exception handling
    struct {
        int ip;
        int stack_size;
    } handlers[128];
    int hsp;
    MetalValue exception_value;

    // Status
    int halted;
    int error;
    int is_throwing;
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

// Load compiled SGVM binary into VM
int metal_vm_load_binary(MetalVM* vm, const unsigned char* data, int size);

// Verify bytecode for safety and integrity
int metal_vm_verify(MetalVM* vm);

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
