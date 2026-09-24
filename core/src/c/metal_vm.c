// ============================================================================
// SageMetal VM — Freestanding Bytecode Virtual Machine
// ============================================================================
// No malloc, no libc, no OS. Pure static pools and bump allocators.
// Compiles with: -ffreestanding -nostdlib -DSAGE_BARE_METAL -DSAGE_METAL_VM
// ============================================================================

#include "metal_vm.h"
#include <stddef.h>

#ifdef SAGE_BARE_METAL
// Freestanding: provide our own libc replacements
static void* bm_memset(void* s, int c, unsigned long n) {
    unsigned char* p = (unsigned char*)s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}
static void* bm_memcpy(void* dest, const void* src, unsigned long n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* s2 = (const unsigned char*)src;
    while (n--) *d++ = *s2++;
    return dest;
}
static unsigned long bm_strlen(const char* s) {
    unsigned long n = 0;
    while (*s++) n++;
    return n;
}
static int bm_strcmp(const char* s1, const char* s2) {
    while (*s1 && *s1 == *s2) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}
#define memset  bm_memset
#define memcpy  bm_memcpy
#define strlen  bm_strlen
#define strcmp  bm_strcmp
#else
extern void* memset(void* s, int c, unsigned long n);
extern void* memcpy(void* dest, const void* src, unsigned long n);
extern unsigned long strlen(const char* s);
extern int strcmp(const char* s1, const char* s2);
#endif

// ============================================================================
// Helpers
// ============================================================================

static unsigned int fnv1a_hash(const char* s, int len) {
    unsigned int hash = 2166136261u;
    for (int i = 0; i < len; i++) {
        hash ^= (unsigned char)s[i];
        hash *= 16777619u;
    }
    return hash;
}

static int read_u8(const unsigned char* code, int* ip) {
    return code[(*ip)++];
}

static int read_u16(const unsigned char* code, int* ip) {
    int hi = code[(*ip)++];
    int lo = code[(*ip)++];
    return (hi << 8) | lo;
}

static int metal_vm_fail(MetalVM* vm, const char* message) {
    if (vm != NULL) {
        vm->error = 1;
        vm->halted = 1;
        vm->error_msg = message;
    }
    return 0;
}

static int metal_string_length(const char* value, int limit) {
    if (value == NULL || limit < 0) return -1;
    int length = 0;
    while (length < limit && value[length] != '\0') length++;
    return length < limit ? length : -1;
}

static int metal_verify_start_set(const uint32_t* starts, int offset);

static int metal_opcode_width(int op) {
    switch (op) {
        case OP_CONSTANT:
        case OP_GET_GLOBAL:
        case OP_DEFINE_GLOBAL:
        case OP_SET_GLOBAL:
        case OP_GET_PROPERTY:
        case OP_SET_PROPERTY:
        case OP_LOAD_FUNCTION:
        case OP_JUMP:
        case OP_JUMP_IF_FALSE:
        case OP_ARRAY:
        case OP_TUPLE:
        case OP_DICT:
        case OP_EXEC_AST_STMT:
        case OP_LOOP_BACK:
        case OP_IMPORT:
        case OP_CLASS:
        case OP_METHOD:
        case OP_SETUP_TRY:
        case OP_GET_LOCAL:
        case OP_SET_LOCAL:
            return 2;
        case OP_DEFINE_FN:
        case OP_CREATE_GENERATOR:
            return 4;
        case OP_CALL_METHOD:
            return 3;
        case OP_CALL:
        case OP_DUP:
            return 1;
        case OP_NIL:
        case OP_TRUE:
        case OP_FALSE:
        case OP_POP:
        case OP_GET_INDEX:
        case OP_SET_INDEX:
        case OP_SLICE:
        case OP_ADD:
        case OP_SUB:
        case OP_MUL:
        case OP_DIV:
        case OP_MOD:
        case OP_NEGATE:
        case OP_EQUAL:
        case OP_NOT_EQUAL:
        case OP_GREATER:
        case OP_GREATER_EQUAL:
        case OP_LESS:
        case OP_LESS_EQUAL:
        case OP_BIT_AND:
        case OP_BIT_OR:
        case OP_BIT_XOR:
        case OP_BIT_NOT:
        case OP_SHIFT_LEFT:
        case OP_SHIFT_RIGHT:
        case OP_NOT:
        case OP_TRUTHY:
        case OP_PRINT:
        case OP_RETURN:
        case OP_PUSH_ENV:
        case OP_POP_ENV:
        case OP_ARRAY_LEN:
        case OP_BREAK:
        case OP_CONTINUE:
        case OP_INHERIT:
        case OP_END_TRY:
        case OP_RAISE:
        case OP_YIELD:
        case OP_GENERATOR_NEXT:
        case OP_GPU_POLL_EVENTS:
        case OP_GPU_WINDOW_SHOULD_CLOSE:
        case OP_GPU_GET_TIME:
        case OP_GPU_KEY_PRESSED:
        case OP_GPU_KEY_DOWN:
        case OP_GPU_MOUSE_POS:
        case OP_GPU_MOUSE_DELTA:
        case OP_GPU_UPDATE_INPUT:
        case OP_GPU_BEGIN_COMMANDS:
        case OP_GPU_END_COMMANDS:
        case OP_GPU_CMD_BEGIN_RP:
        case OP_GPU_CMD_END_RP:
        case OP_GPU_CMD_DRAW:
        case OP_GPU_CMD_BIND_GP:
        case OP_GPU_CMD_BIND_DS:
        case OP_GPU_CMD_SET_VP:
        case OP_GPU_CMD_SET_SC:
        case OP_GPU_CMD_BIND_VB:
        case OP_GPU_CMD_BIND_IB:
        case OP_GPU_CMD_DRAW_IDX:
        case OP_GPU_SUBMIT_SYNC:
        case OP_GPU_ACQUIRE_IMG:
        case OP_GPU_PRESENT:
        case OP_GPU_WAIT_FENCE:
        case OP_GPU_RESET_FENCE:
        case OP_GPU_UPDATE_UNIFORM:
        case OP_GPU_CMD_PUSH_CONST:
        case OP_GPU_CMD_DISPATCH:
        case OP_HALT:
            return 0;
        default:
            return -1;
    }
}

static int metal_string_index_valid(const MetalVM* vm, int index) {
    return vm != NULL && index >= 0 && index < vm->string_used;
}

static int metal_value_index(MetalValue value, int* index) {
    if (index == NULL || value.type != MV_NUM ||
        !(value.as.number >= -2147483648.0 && value.as.number <= 2147483647.0)) {
        return 0;
    }
    *index = (int)value.as.number;
    return 1;
}

static int metal_name_operand_valid(const MetalVM* vm, int index) {
    if (vm == NULL || index < 0 || index >= vm->const_count ||
        vm->constants[index].type != MV_STR) {
        return 0;
    }
    return metal_string_index_valid(vm, vm->constants[index].as.str_idx);
}

static int metal_validate_operands(const MetalVM* vm, const unsigned char* code,
                                   int code_length, int instruction_offset,
                                   const uint32_t* instruction_starts) {
    if (vm == NULL || code == NULL || instruction_offset < 0 ||
        instruction_offset >= code_length) {
        return 0;
    }
    int op = code[instruction_offset];
    int width = metal_opcode_width(op);
    int operand_pos = instruction_offset + 1;
    if (width < 0 || width > code_length - operand_pos) {
        return 0;
    }

    if (op == OP_CONSTANT) {
        int index = (code[operand_pos] << 8) | code[operand_pos + 1];
        return index < vm->const_count;
    }
    if (op == OP_GET_GLOBAL || op == OP_DEFINE_GLOBAL || op == OP_SET_GLOBAL ||
        op == OP_GET_PROPERTY || op == OP_SET_PROPERTY || op == OP_IMPORT ||
        op == OP_CLASS || op == OP_METHOD || op == OP_CALL_METHOD) {
        int index = (code[operand_pos] << 8) | code[operand_pos + 1];
        return metal_name_operand_valid(vm, index);
    }
    if (op == OP_DEFINE_FN || op == OP_CREATE_GENERATOR) {
        int name_index = (code[operand_pos] << 8) | code[operand_pos + 1];
        int function_index = (code[operand_pos + 2] << 8) | code[operand_pos + 3];
        return metal_name_operand_valid(vm, name_index) && function_index < 256;
    }
    if (op == OP_LOAD_FUNCTION) {
        int index = (code[operand_pos] << 8) | code[operand_pos + 1];
        return index < 256;
    }
    if (op == OP_GET_LOCAL || op == OP_SET_LOCAL) {
        int index = (code[operand_pos] << 8) | code[operand_pos + 1];
        return index >= 0 && index < METAL_MAX_LOCALS;
    }
    if (op == OP_JUMP || op == OP_JUMP_IF_FALSE || op == OP_SETUP_TRY) {
        int target = (code[operand_pos] << 8) | code[operand_pos + 1];
         return target >= 0 && target < code_length &&
                (instruction_starts == NULL || metal_verify_start_set(instruction_starts, target));
    }
    if (op == OP_LOOP_BACK) {
        int distance = (code[operand_pos] << 8) | code[operand_pos + 1];
        long target = (long)operand_pos + 2L - distance;
         return target >= 0 && target < code_length &&
                (instruction_starts == NULL || metal_verify_start_set(instruction_starts, target));
    }
    if (op == OP_ARRAY || op == OP_TUPLE) {
        int count = (code[operand_pos] << 8) | code[operand_pos + 1];
        return count <= METAL_ARRAY_MAX_ELEMS;
    }
    if (op == OP_DICT) {
        int count = (code[operand_pos] << 8) | code[operand_pos + 1];
        return count <= METAL_DICT_MAX_ENTRIES;
    }
    if (op == OP_BREAK || op == OP_CONTINUE) {
        return 0;
    }
    return 1;
}

typedef struct {
    int pops;
    int pushes;
    int terminal;
    int branch_kind;
    int target;
} MetalInstructionFlow;

static int metal_instruction_flow(const MetalVM* vm, const unsigned char* code,
                                  int code_length, int instruction_offset,
                                  MetalInstructionFlow* flow) {
    int op = code[instruction_offset];
    int operand_pos = instruction_offset + 1;
    memset(flow, 0, sizeof(*flow));

    switch (op) {
        case OP_CONSTANT:
        case OP_NIL:
        case OP_TRUE:
        case OP_FALSE:
        case OP_GET_GLOBAL:
        case OP_GET_LOCAL:
        case OP_LOAD_FUNCTION:
        case OP_DUP:
        case OP_IMPORT:
        case OP_CLASS:
        case OP_CREATE_GENERATOR:
        case OP_GPU_WINDOW_SHOULD_CLOSE:
        case OP_GPU_GET_TIME:
        case OP_GPU_MOUSE_POS:
        case OP_GPU_MOUSE_DELTA:
        case OP_GPU_ACQUIRE_IMG:
            flow->pushes = 1;
            break;
        case OP_POP:
        case OP_PRINT:
        case OP_DEFINE_GLOBAL:
        case OP_SET_GLOBAL:
        case OP_METHOD:
        case OP_RAISE:
            flow->pops = 1;
            if (op == OP_RAISE) flow->terminal = 1;
            break;
         case OP_SET_PROPERTY:
             flow->pops = 2;
             flow->pushes = 1;
             break;
         case OP_SET_INDEX:
         case OP_SLICE:
             flow->pops = 3;
             flow->pushes = 1;
             break;
         case OP_INHERIT:
             flow->pops = 2;
             flow->pushes = 1;
             break;
        case OP_GET_PROPERTY:
            flow->pops = 1;
            flow->pushes = 1;
            break;
        case OP_SET_LOCAL:
            flow->pops = 1;
            flow->pushes = 1;
            break;
        case OP_GET_INDEX:
        case OP_GENERATOR_NEXT:
        case OP_ARRAY_LEN:
        case OP_GPU_POLL_EVENTS:
        case OP_GPU_UPDATE_INPUT:
        case OP_GPU_KEY_PRESSED:
        case OP_GPU_KEY_DOWN:
        case OP_GPU_BEGIN_COMMANDS:
        case OP_GPU_END_COMMANDS:
             if (op == OP_GET_INDEX || op == OP_GENERATOR_NEXT || op == OP_ARRAY_LEN) {
                flow->pops = 1;
                flow->pushes = 1;
            }
            break;
        case OP_ADD:
        case OP_SUB:
        case OP_MUL:
        case OP_DIV:
        case OP_MOD:
        case OP_EQUAL:
        case OP_NOT_EQUAL:
        case OP_GREATER:
        case OP_GREATER_EQUAL:
        case OP_LESS:
        case OP_LESS_EQUAL:
        case OP_BIT_AND:
        case OP_BIT_OR:
        case OP_BIT_XOR:
        case OP_SHIFT_LEFT:
        case OP_SHIFT_RIGHT:
            flow->pops = 2;
            flow->pushes = 1;
            break;
        case OP_NEGATE:
        case OP_BIT_NOT:
        case OP_NOT:
        case OP_TRUTHY:
        case OP_YIELD:
            flow->pops = 1;
            flow->pushes = 1;
            break;
        case OP_JUMP:
            flow->branch_kind = 1;
            flow->target = (code[operand_pos] << 8) | code[operand_pos + 1];
            break;
        case OP_LOOP_BACK:
            flow->branch_kind = 1;
            flow->target = (int)((long)operand_pos + 2L -
                                (((int)code[operand_pos] << 8) | code[operand_pos + 1]));
            break;
        case OP_JUMP_IF_FALSE:
            flow->branch_kind = 2;
            flow->target = (code[operand_pos] << 8) | code[operand_pos + 1];
            break;
        case OP_SETUP_TRY:
            flow->branch_kind = 3;
            flow->target = (code[operand_pos] << 8) | code[operand_pos + 1];
            break;
        case OP_CALL:
        case OP_CALL_METHOD:
            flow->pops = (op == OP_CALL ? code[operand_pos] : code[operand_pos + 2]) + 1;
            flow->pushes = 1;
            break;
        case OP_ARRAY:
        case OP_TUPLE:
            flow->pops = (code[operand_pos] << 8) | code[operand_pos + 1];
            flow->pushes = 1;
            break;
        case OP_DICT:
            flow->pops = (((int)code[operand_pos] << 8) | code[operand_pos + 1]) * 2;
            flow->pushes = 1;
            break;
        case OP_END_TRY:
        case OP_PUSH_ENV:
        case OP_POP_ENV:
        case OP_DEFINE_FN:
        case OP_RETURN:
            if (op == OP_RETURN) flow->terminal = 1;
            break;
        case OP_GPU_CMD_BEGIN_RP:
            flow->pops = 6;
            break;
        case OP_GPU_CMD_END_RP:
        case OP_GPU_RESET_FENCE:
            flow->pops = 1;
            break;
        case OP_GPU_PRESENT:
        case OP_GPU_WAIT_FENCE:
        case OP_GPU_UPDATE_UNIFORM:
            flow->pops = 2;
            break;
        case OP_GPU_CMD_PUSH_CONST:
        case OP_GPU_CMD_DISPATCH:
            flow->pops = 4;
            break;
        case OP_GPU_CMD_DRAW:
            flow->pops = 5;
            break;
        case OP_GPU_CMD_BIND_GP:
        case OP_GPU_CMD_BIND_VB:
        case OP_GPU_CMD_BIND_IB:
            flow->pops = 2;
            break;
        case OP_GPU_CMD_BIND_DS:
            flow->pops = 4;
            break;
        case OP_GPU_CMD_SET_VP:
            flow->pops = 7;
            break;
        case OP_GPU_CMD_SET_SC:
            flow->pops = 5;
            break;
        case OP_GPU_CMD_DRAW_IDX:
            flow->pops = 6;
            break;
        case OP_GPU_SUBMIT_SYNC:
            flow->pops = 4;
            flow->pushes = 1;
            break;
        case OP_HALT:
            flow->terminal = 1;
            break;
        default:
            return 0;
    }
    (void)vm;
    (void)code_length;
    return 1;
}

static int metal_merge_stack_state(int16_t* minimum, int16_t* maximum, int target,
                                  int target_minimum, int target_maximum,
                                  int code_length, int preserve_maximum) {
    if (target < 0 || target > code_length) return 0;
    if (target == code_length) {
        int changed = 0;
        if (minimum[target] < 0) {
            minimum[target] = target_minimum;
            maximum[target] = target_maximum;
            return 1;
        }
        if (target_minimum < minimum[target]) {
            minimum[target] = target_minimum;
            changed = 1;
        }
        if (target_maximum > maximum[target]) {
            maximum[target] = target_maximum;
            changed = 1;
        }
        return changed;
    }
    int old_minimum = minimum[target];
    int old_maximum = maximum[target];
    if (old_minimum < 0) {
        minimum[target] = target_minimum;
        maximum[target] = target_maximum;
        return 1;
    }
    if (target_minimum < old_minimum) minimum[target] = target_minimum;
    if (target_maximum > old_maximum) maximum[target] = target_maximum;
    (void)preserve_maximum;
    return minimum[target] != old_minimum || maximum[target] != old_maximum;
}

#define METAL_VERIFY_START_WORDS ((METAL_VERIFY_MAX_CODE + 32) / 32)
#define METAL_VERIFY_STACK_MAX 32767

static int metal_verify_start_set(const uint32_t* starts, int offset) {
    if (starts == NULL || offset < 0 || offset > METAL_VERIFY_MAX_CODE) return 0;
    return (starts[(unsigned int)offset >> 5] &
            (UINT32_C(1) << ((unsigned int)offset & 31))) != 0;
}

static void metal_verify_mark_start(uint32_t* starts, int offset) {
    starts[(unsigned int)offset >> 5] |=
        UINT32_C(1) << ((unsigned int)offset & 31);
}

static int metal_verify_chunk(const MetalVM* vm, const unsigned char* code,
                              int code_length, int initial_stack) {
    if (vm == NULL || code_length < 0 || code_length > METAL_VERIFY_MAX_CODE ||
        (code_length > 0 && code == NULL) || initial_stack < 0 ||
        initial_stack > METAL_STACK_SIZE || initial_stack > METAL_VERIFY_STACK_MAX ||
        METAL_STACK_SIZE > METAL_VERIFY_STACK_MAX) {
        return -1;
    }
    if (code_length == 0) return 0;

    static uint32_t instruction_starts[METAL_VERIFY_START_WORDS];
    static int16_t minimum[METAL_VERIFY_MAX_CODE + 1];
    static int16_t maximum[METAL_VERIFY_MAX_CODE + 1];
    memset(instruction_starts, 0, sizeof(instruction_starts));
    for (int i = 0; i <= code_length; i++) {
        minimum[i] = -1;
        maximum[i] = -1;
    }

    int offset = 0;
    while (offset < code_length) {
         metal_verify_mark_start(instruction_starts, offset);
        int width = metal_opcode_width(code[offset]);
        if (width < 0 || width > code_length - offset - 1 ||
            !metal_validate_operands(vm, code, code_length, offset, NULL)) {
            return -1;
        }
        offset += 1 + width;
    }
     metal_verify_mark_start(instruction_starts, code_length);

    offset = 0;
    while (offset < code_length) {
        if (!metal_validate_operands(vm, code, code_length, offset, instruction_starts)) {
            return -3;
        }
        offset += 1 + metal_opcode_width(code[offset]);
    }

    minimum[0] = initial_stack;
    maximum[0] = initial_stack;
    int changed = 1;
    size_t iterations = 0;
    size_t max_iterations = (size_t)code_length * 4u + 1024u;
    while (changed) {
        if (++iterations > max_iterations) return -8;
        changed = 0;
        for (int instruction = 0; instruction < code_length; instruction++) {
            if (!metal_verify_start_set(instruction_starts, instruction) || minimum[instruction] < 0) continue;
            MetalInstructionFlow flow;
            int op = code[instruction];
            int operand_pos = instruction + 1;
            if (!metal_instruction_flow(vm, code, code_length, instruction, &flow)) {
                return -4;
            }
            if (minimum[instruction] < flow.pops) return -5;
            if (op == OP_DUP) {
                int distance = code[operand_pos];
                if (minimum[instruction] < distance + 1) return -5;
            } else if (op == OP_GET_LOCAL) {
                int index = (code[operand_pos] << 8) | code[operand_pos + 1];
                if (index >= minimum[instruction]) return -6;
            } else if (op == OP_SET_LOCAL) {
                int index = (code[operand_pos] << 8) | code[operand_pos + 1];
                if (minimum[instruction] < 1 || index >= minimum[instruction]) return -6;
            }
            long next_minimum = (long)minimum[instruction] - flow.pops + flow.pushes;
            long next_maximum = (long)maximum[instruction] - flow.pops + flow.pushes;
            if (next_minimum < 0 || next_maximum > METAL_STACK_SIZE ||
                next_maximum > METAL_VERIFY_STACK_MAX) return -7;
            int next = instruction + 1 + metal_opcode_width(op);
            if (!flow.terminal && flow.branch_kind != 1) {
                changed |= metal_merge_stack_state(minimum, maximum, next,
                                                   (int)next_minimum, (int)next_maximum,
                                                   code_length, next < instruction);
            }
            if (flow.branch_kind != 0) {
                int branch_minimum = (int)next_minimum;
                int branch_maximum = (int)next_maximum;
                if (flow.branch_kind == 3) {
                     if (branch_maximum >= METAL_STACK_SIZE ||
                         branch_maximum >= METAL_VERIFY_STACK_MAX) return -7;
                    branch_minimum++;
                    branch_maximum++;
                }
                 if (flow.target < 0 || flow.target >= code_length ||
                     (flow.target < code_length && !metal_verify_start_set(instruction_starts, flow.target))) return -3;
                changed |= metal_merge_stack_state(minimum, maximum, flow.target,
                                                   branch_minimum, branch_maximum,
                                                   code_length, flow.target < instruction);
            }
        }
    }
    return 0;
}

static void metal_print_str(MetalVM* vm, const char* s) {
    if (vm == NULL || s == NULL || !vm->write_char) return;
    while (*s) vm->write_char(*s++);
}

static void metal_print_int(MetalVM* vm, long long n) {
    if (vm == NULL) return;
    unsigned long long magnitude = n < 0 ? 0ULL - (unsigned long long)n : (unsigned long long)n;
    if (n < 0 && vm->write_char) vm->write_char('-');
    char buf[24];
    int i = 0;
    if (magnitude == 0) { buf[i++] = '0'; }
    else { while (magnitude > 0) { buf[i++] = '0' + (int)(magnitude % 10); magnitude /= 10; } }
    while (--i >= 0) if (vm->write_char) vm->write_char(buf[i]);
}

static void metal_print_double(MetalVM* vm, double d) {
    if (vm == NULL) return;
    if (d >= -1e15 && d <= 1e15 && d == (double)(long long)d) {
        metal_print_int(vm, (long long)d);
    } else {
        if (!(d >= -1e15 && d <= 1e15)) {
            if (d != d) metal_print_str(vm, "nan");
            else {
                if (d < 0) metal_print_str(vm, "-");
                metal_print_str(vm, "inf");
            }
            return;
        }
        // Simplified float printing for bare-metal
        if (d < 0) { if (vm->write_char) vm->write_char('-'); d = -d; }
        long long integer = (long long)d;
        metal_print_int(vm, integer);
        if (vm->write_char) vm->write_char('.');
        double frac = d - (double)integer;
        for (int i = 0; i < 6; i++) {
            frac *= 10.0;
            int digit = (int)frac;
            if (vm->write_char) vm->write_char('0' + digit);
            frac -= digit;
        }
    }
}

// ============================================================================
// Value Constructors
// ============================================================================

MetalValue mv_nil(void) {
    MetalValue v; v.type = MV_NIL; v.as.number = 0; return v;
}

#ifdef SAGE_BARE_METAL
MetalValue mv_num(int64_t value) {
    MetalValue v; v.type = MV_NUM; v.as.number = value << 32; return v;
}

MetalValue mv_num_fp(int64_t value) {
    MetalValue v; v.type = MV_NUM; v.as.number = value; return v;
}
#else
MetalValue mv_num(double val) {
    MetalValue v; v.type = MV_NUM; v.as.number = val; return v;
}
#endif

MetalValue mv_bool(int val) {
    MetalValue v; v.type = MV_BOOL; v.as.boolean = val ? 1 : 0; return v;
}

MetalValue mv_str(MetalVM* vm, const char* s, int len) {
    MetalValue v;
    v.type = MV_STR;
    v.as.str_idx = metal_string_intern(vm, s, len);
    return v;
}

MetalValue mv_ptr(void* p) {
    MetalValue v; v.type = MV_PTR; v.as.ptr = p; return v;
}

MetalValue mv_generator(int gen_idx) {
    MetalValue v; v.type = MV_GENERATOR; v.as.gen_idx = gen_idx; return v;
}

// ============================================================================
// VM Init & Load
// ============================================================================

void metal_vm_init(MetalVM* vm) {
    if (vm == NULL) return;
    memset(vm, 0, sizeof(MetalVM));
    vm->current_gen_idx = -1;
}

static int metal_read_u16(const unsigned char* data, int size, int* pos, int* value) {
    if (data == NULL || pos == NULL || value == NULL || *pos < 0 || *pos > size - 2) return 0;
    *value = ((int)data[*pos] << 8) | data[*pos + 1];
    *pos += 2;
    return 1;
}

static int metal_read_u32(const unsigned char* data, int size, int* pos, unsigned int* value) {
    if (data == NULL || pos == NULL || value == NULL || *pos < 0 || *pos > size - 4) return 0;
    *value = ((unsigned int)data[*pos] << 24) |
             ((unsigned int)data[*pos + 1] << 16) |
             ((unsigned int)data[*pos + 2] << 8) |
             (unsigned int)data[*pos + 3];
    *pos += 4;
    return 1;
}

void metal_vm_load(MetalVM* vm, const unsigned char* code, int length) {
    if (vm == NULL) return;
    vm->code = code;
    vm->code_length = length;
    vm->ip = 0;
    vm->error = 0;
    vm->halted = 0;
    vm->error_msg = NULL;
    if (vm->error) return;
    if (metal_verify_chunk(vm, code, length, 0) < 0) {
        (void)metal_vm_fail(vm, "Metal VM: invalid bytecode");
    }
}

int metal_vm_load_binary(MetalVM* vm, const unsigned char* data, int size) {
    if (vm == NULL || data == NULL || size < 12) {
        if (vm != NULL) (void)metal_vm_fail(vm, "Metal VM: truncated binary");
        return -1;
    }

    void (*write_char)(char) = vm->write_char;
    int (*read_char)(void) = vm->read_char;
    void (*write_port)(int, int) = vm->write_port;
    int (*read_port)(int) = vm->read_port;
    void *(*map_mmio)(unsigned long, unsigned long) = vm->map_mmio;
    metal_vm_init(vm);
    vm->write_char = write_char;
    vm->read_char = read_char;
    vm->write_port = write_port;
    vm->read_port = read_port;
    vm->map_mmio = map_mmio;

    int pos = 0;
    if (data[pos++] != 'S' || data[pos++] != 'G' || data[pos++] != 'V' || data[pos++] != 'M') {
        (void)metal_vm_fail(vm, "Metal VM: invalid magic");
        return -2;
    }
    if (data[pos++] != 0x01) {
        (void)metal_vm_fail(vm, "Metal VM: invalid version");
        return -3;
    }
    if (data[pos++] != 0x00) {
        (void)metal_vm_fail(vm, "Metal VM: invalid flags");
        return -4;
    }

    int const_count = 0;
    if (!metal_read_u16(data, size, &pos, &const_count) || const_count > METAL_CONST_POOL) {
        (void)metal_vm_fail(vm, "Metal VM: invalid constant count");
        return -4;
    }
    for (int i = 0; i < const_count; i++) {
        if (pos >= size) {
            (void)metal_vm_fail(vm, "Metal VM: truncated constants");
            return -5;
        }
        unsigned char type = data[pos++];
        if (type == 1) {
            if (pos > size - 8) {
                (void)metal_vm_fail(vm, "Metal VM: truncated number constant");
                return -5;
            }
            union { double d; unsigned char b[8]; } value;
            for (int j = 0; j < 8; j++) value.b[j] = data[pos + j];
            if (metal_vm_add_constant(vm, mv_num(value.d)) < 0) {
                (void)metal_vm_fail(vm, "Metal VM: constant pool overflow");
                return -6;
            }
            pos += 8;
        } else if (type == 3) {
            int length = 0;
            if (!metal_read_u16(data, size, &pos, &length) || pos > size - length) {
                (void)metal_vm_fail(vm, "Metal VM: truncated string constant");
                return -5;
            }
            int string_index = metal_string_intern(vm, (const char*)&data[pos], length);
            if (string_index < 0 || metal_vm_add_constant(vm,
                    (MetalValue){MV_STR, {.str_idx = string_index}}) < 0) {
                (void)metal_vm_fail(vm, "Metal VM: string pool overflow");
                return -6;
            }
            pos += length;
        } else {
            (void)metal_vm_fail(vm, "Metal VM: invalid constant type");
            return -7;
        }
    }

    unsigned int chunk_count = 0;
    if (!metal_read_u32(data, size, &pos, &chunk_count) || chunk_count > 1024) {
        (void)metal_vm_fail(vm, "Metal VM: invalid chunk count");
        return -8;
    }
    for (unsigned int i = 0; i < chunk_count; i++) {
        if (vm->chunk_count < 0 || vm->chunk_count >= (int)(sizeof(vm->chunks) / sizeof(vm->chunks[0]))) {
            (void)metal_vm_fail(vm, "Metal VM: chunk pool overflow");
            return -11;
        }
        unsigned int code_length = 0;
        if (!metal_read_u32(data, size, &pos, &code_length) ||
            code_length > (unsigned int)METAL_VERIFY_MAX_CODE ||
            code_length > (unsigned int)(size - pos)) {
            (void)metal_vm_fail(vm, "Metal VM: truncated chunk");
            return -9;
        }
        vm->chunks[vm->chunk_count] = &data[pos];
        vm->chunk_lengths[vm->chunk_count] = (int)code_length;
        vm->chunk_count++;
        pos += (int)code_length;
    }
    if (pos != size || metal_vm_verify(vm) < 0) {
        (void)metal_vm_fail(vm, "Metal VM: invalid chunk payload");
        return -10;
    }
    return 0;
}

int metal_vm_verify(MetalVM* vm) {
    if (vm == NULL || vm->chunk_count < 0 || vm->chunk_count > 1024 ||
        vm->const_count < 0 || vm->const_count > METAL_CONST_POOL) {
        return -1;
    }
    for (int c = 0; c < vm->chunk_count; c++) {
        int result = metal_verify_chunk(vm, vm->chunks[c], vm->chunk_lengths[c], 0);
        if (result < 0) return result;
    }
    return 0;
}

int metal_vm_add_constant(MetalVM* vm, MetalValue value) {
    if (vm == NULL || vm->const_count < 0 || vm->const_count >= METAL_CONST_POOL) return -1;
    vm->constants[vm->const_count] = value;
    return vm->const_count++;
}

// ============================================================================
// Dict Pool
// ============================================================================

static void metal_mark_value(MetalVM* vm, MetalValue val, unsigned char* marked_arrays, unsigned char* marked_dicts) {
    if (val.type == MV_ARR) {
        int idx = val.as.arr_idx;
        int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
        if (idx >= 0 && idx < max && !marked_arrays[idx]) {
            marked_arrays[idx] = 1;
            MetalArray* a = &vm->arrays[idx];
            if (a->count < 0 || a->count > METAL_ARRAY_MAX_ELEMS) return;
            for (int i = 0; i < a->count; i++) {
                metal_mark_value(vm, a->elems[i], marked_arrays, marked_dicts);
            }
        }
    } else if (val.type == MV_DICT) {
        int idx = val.as.dict_idx;
        int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
        if (idx >= 0 && idx < max && !marked_dicts[idx]) {
            marked_dicts[idx] = 1;
            MetalDict* d = &vm->dicts[idx];
            if (d->count < 0 || d->count > METAL_DICT_MAX_ENTRIES) return;
            for (int i = 0; i < d->count; i++) {
                metal_mark_value(vm, d->values[i], marked_arrays, marked_dicts);
            }
        }
    }
}

void metal_vm_gc(MetalVM* vm) {
    if (vm == NULL) return;
    if (vm->sp < 0 || vm->sp > METAL_STACK_SIZE ||
        vm->scope_depth < 0 || vm->scope_depth >= METAL_ENV_DEPTH) {
        (void)metal_vm_fail(vm, "Metal VM: invalid GC state");
        return;
    }
    int max_arr = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    int max_dict = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (vm->array_count < 0 || vm->array_count > max_arr ||
        vm->dict_count < 0 || vm->dict_count > max_dict ||
        vm->const_count < 0 || vm->const_count > METAL_CONST_POOL) {
        (void)metal_vm_fail(vm, "Metal VM: invalid pool state");
        return;
    }
    
    // Allocate temporary mark bits (small arrays on the stack, e.g. 512 + 256 bytes)
    unsigned char marked_arrays[METAL_POOL_SIZE / 8] = {0};
    unsigned char marked_dicts[METAL_POOL_SIZE / 16] = {0};
    
    // 1. Mark roots on the stack
    for (int i = 0; i < vm->sp; i++) {
        metal_mark_value(vm, vm->stack[i], marked_arrays, marked_dicts);
    }
    
    // 2. Mark roots in the scope environments
     for (int d = 0; d <= vm->scope_depth; d++) {
         MetalScope* s = &vm->scopes[d];
         if (s->count < 0 || s->count > METAL_VARS_PER_SCOPE) {
             (void)metal_vm_fail(vm, "Metal VM: invalid scope state");
             return;
         }
         for (int i = 0; i < s->count; i++) {
            metal_mark_value(vm, s->values[i], marked_arrays, marked_dicts);
        }
    }
    
    // 3. Mark exception values
    metal_mark_value(vm, vm->exception_value, marked_arrays, marked_dicts);
    
    // 4. Mark constant pool
     if (vm->const_count < 0 || vm->const_count > METAL_CONST_POOL) {
         (void)metal_vm_fail(vm, "Metal VM: invalid constant state");
         return;
     }
     for (int i = 0; i < vm->const_count; i++) {
        metal_mark_value(vm, vm->constants[i], marked_arrays, marked_dicts);
    }
    
    // Sweep arrays
    for (int i = 0; i < max_arr; i++) {
        if (!marked_arrays[i]) {
            vm->arrays[i].in_use = 0;
            vm->arrays[i].count = 0;
        }
    }
    
    // Sweep dicts
    for (int i = 0; i < max_dict; i++) {
        if (!marked_dicts[i]) {
            vm->dicts[i].in_use = 0;
            vm->dicts[i].count = 0;
        }
    }
}

int metal_dict_new(MetalVM* vm) {
    if (vm == NULL) return -1;
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    
    // Search for unused slot
    for (int i = 0; i < vm->dict_count; i++) {
        if (!vm->dicts[i].in_use) {
            vm->dicts[i].count = 0;
            vm->dicts[i].in_use = 1;
            return i;
        }
    }
    
    if (vm->dict_count < 0) return -1;
    if (vm->dict_count < max) {
        int idx = vm->dict_count++;
        vm->dicts[idx].count = 0;
        vm->dicts[idx].in_use = 1;
        return idx;
    }
    
    // Trigger GC and search again
    metal_vm_gc(vm);
    
    for (int i = 0; i < vm->dict_count; i++) {
        if (!vm->dicts[i].in_use) {
            vm->dicts[i].count = 0;
            vm->dicts[i].in_use = 1;
            return i;
        }
    }
    
    return -1;
}

void metal_dict_set(MetalVM* vm, int dict_idx, int key_str_idx, MetalValue val) {
    if (vm == NULL || dict_idx < 0 || dict_idx >= vm->dict_count) return;
    MetalDict* d = &vm->dicts[dict_idx];
    if (d->count < 0 || d->count > METAL_DICT_MAX_ENTRIES) return;
    // Update existing
    for (int i = 0; i < d->count; i++) {
        if (d->key_str_idx[i] == key_str_idx) {
            d->values[i] = val;
            return;
        }
    }
    // Add new
    if (d->count < METAL_DICT_MAX_ENTRIES) {
        d->key_str_idx[d->count] = key_str_idx;
        d->values[d->count] = val;
        d->count++;
    }
}

MetalValue metal_dict_get(MetalVM* vm, int dict_idx, int key_str_idx) {
    if (vm == NULL || dict_idx < 0 || dict_idx >= vm->dict_count) return mv_nil();
    MetalDict* d = &vm->dicts[dict_idx];
    if (d->count < 0 || d->count > METAL_DICT_MAX_ENTRIES) return mv_nil();
    for (int i = 0; i < d->count; i++) {
        if (d->key_str_idx[i] == key_str_idx) return d->values[i];
    }
    return mv_nil();
}

// ============================================================================
// Stack Operations
// ============================================================================

int metal_vm_push(MetalVM* vm, MetalValue value) {
    if (vm == NULL || vm->sp < 0 || vm->sp >= METAL_STACK_SIZE) {
        if (vm != NULL) {
            vm->error = 1;
            vm->error_msg = "Metal VM: stack overflow";
        }
        return 0;
    }
    vm->stack[vm->sp++] = value;
    return 1;
}

MetalValue metal_vm_pop(MetalVM* vm) {
    if (vm == NULL || vm->sp <= 0) return mv_nil();
    return vm->stack[--vm->sp];
}

MetalValue metal_vm_peek(MetalVM* vm, int distance) {
    if (vm == NULL || distance < 0 || vm->sp < 0 || distance >= vm->sp) return mv_nil();
    int idx = vm->sp - 1 - distance;
    if (idx < 0 || idx >= vm->sp) return mv_nil();
    return vm->stack[idx];
}

// ============================================================================
// String Pool (bump allocator)
// ============================================================================

int metal_string_intern(MetalVM* vm, const char* s, int len) {
    if (vm == NULL || len < 0 || (len > 0 && s == NULL) ||
        vm->string_used < 0 || vm->string_used > METAL_STRING_POOL ||
        len > METAL_STRING_POOL - vm->string_used - 1) {
        return -1;
    }
    int search = 0;
    while (search < vm->string_used) {
        const char* existing = &vm->strings[search];
        int remaining = METAL_STRING_POOL - search;
        int existing_len = metal_string_length(existing, remaining);
        if (existing_len < 0 || existing_len >= remaining) return -1;
        if (existing_len == len) {
            int match = 1;
            for (int i = 0; i < len; i++) {
                if (existing[i] != s[i]) { match = 0; break; }
            }
            if (match) return search;
        }
        search += existing_len + 1;
    }

    int idx = vm->string_used;
    if (len > 0) memcpy(&vm->strings[idx], s, (unsigned long)len);
    vm->strings[idx + len] = '\0';
    vm->string_used += len + 1;
    return idx;
}

const char* metal_string_get(MetalVM* vm, int idx) {
    if (vm == NULL || idx < 0 || idx >= vm->string_used) return "";
    return &vm->strings[idx];
}

// ============================================================================
// Array Pool
// ============================================================================

int metal_array_new(MetalVM* vm) {
    if (vm == NULL) return -1;
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    
    // Search for unused slot
    for (int i = 0; i < vm->array_count; i++) {
        if (!vm->arrays[i].in_use) {
            vm->arrays[i].count = 0;
            vm->arrays[i].in_use = 1;
            return i;
        }
    }
    
    if (vm->array_count < 0) return -1;
    if (vm->array_count < max) {
        int idx = vm->array_count++;
        vm->arrays[idx].count = 0;
        vm->arrays[idx].in_use = 1;
        return idx;
    }
    
    // Trigger GC and search again
    metal_vm_gc(vm);
    
    for (int i = 0; i < vm->array_count; i++) {
        if (!vm->arrays[i].in_use) {
            vm->arrays[i].count = 0;
            vm->arrays[i].in_use = 1;
            return i;
        }
    }
    
    return -1;
}

void metal_array_push(MetalVM* vm, int arr_idx, MetalValue val) {
    if (vm == NULL) return;
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return;
    MetalArray* a = &vm->arrays[arr_idx];
    if (a->count < 0 || a->count >= METAL_ARRAY_MAX_ELEMS) return;
    a->elems[a->count++] = val;
}

MetalValue metal_array_get(MetalVM* vm, int arr_idx, int index) {
    if (vm == NULL) return mv_nil();
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return mv_nil();
    MetalArray* a = &vm->arrays[arr_idx];
    if (a->count < 0 || index < 0 || index >= a->count) return mv_nil();
    return a->elems[index];
}

int metal_array_len(MetalVM* vm, int arr_idx) {
    if (vm == NULL) return 0;
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max || vm->arrays[arr_idx].count < 0) return 0;
    return vm->arrays[arr_idx].count;
}

// ============================================================================
// Environment (scope chain — flat array)
// ============================================================================

static int scope_lookup(MetalVM* vm, unsigned int hash, MetalValue* out) {
    if (vm == NULL || out == NULL || vm->scope_depth < 0 ||
        vm->scope_depth >= METAL_ENV_DEPTH) return 0;
    for (int d = vm->scope_depth; d >= 0; d--) {
        MetalScope* s = &vm->scopes[d];
        if (s->count < 0 || s->count > METAL_VARS_PER_SCOPE) return 0;
        for (int i = 0; i < s->count; i++) {
            if (s->name_hash[i] == (int)hash) {
                *out = s->values[i];
                return 1;
            }
        }
    }
    return 0;
}

static void scope_define(MetalVM* vm, unsigned int hash, MetalValue value) {
    if (vm == NULL || vm->scope_depth < 0 || vm->scope_depth >= METAL_ENV_DEPTH) return;
    MetalScope* s = &vm->scopes[vm->scope_depth];
    if (s->count < 0 || s->count > METAL_VARS_PER_SCOPE) return;
    for (int i = 0; i < s->count; i++) {
        if (s->name_hash[i] == (int)hash) {
            s->values[i] = value;
            return;
        }
    }
    if (s->count >= METAL_VARS_PER_SCOPE) return;
    s->name_hash[s->count] = (int)hash;
    s->values[s->count] = value;
    s->count++;
}

static void scope_assign(MetalVM* vm, unsigned int hash, MetalValue value) {
    if (vm == NULL || vm->scope_depth < 0 || vm->scope_depth >= METAL_ENV_DEPTH) return;
    for (int d = vm->scope_depth; d >= 0; d--) {
        MetalScope* s = &vm->scopes[d];
        if (s->count < 0 || s->count > METAL_VARS_PER_SCOPE) return;
        for (int i = 0; i < s->count; i++) {
            if (s->name_hash[i] == (int)hash) {
                s->values[i] = value;
                return;
            }
        }
    }
    // Not found — define in current scope
    scope_define(vm, hash, value);
}

// ============================================================================
// Print
// ============================================================================

void metal_print_value(MetalVM* vm, MetalValue value) {
    if (vm == NULL) return;
    switch (value.type) {
        case MV_NUM:
            metal_print_double(vm, value.as.number);
            break;
        case MV_BOOL:
            metal_print_str(vm, value.as.boolean ? "true" : "false");
            break;
        case MV_STR:
            metal_print_str(vm, metal_string_get(vm, value.as.str_idx));
            break;
        case MV_ARR: {
            metal_print_str(vm, "[");
            int len = metal_array_len(vm, value.as.arr_idx);
            for (int i = 0; i < len; i++) {
                if (i > 0) metal_print_str(vm, ", ");
                metal_print_value(vm, metal_array_get(vm, value.as.arr_idx, i));
            }
            metal_print_str(vm, "]");
            break;
        }
        case MV_PTR:
            metal_print_str(vm, "<ptr>");
            break;
        case MV_GENERATOR:
            metal_print_str(vm, "<generator>");
            break;
        case MV_NIL:
        default:
            metal_print_str(vm, "nil");
            break;
    }
}

// ============================================================================
// Truthiness
// ============================================================================

static int metal_truthy(MetalValue v) {
    switch (v.type) {
        case MV_NIL:  return 0;
        case MV_BOOL: return v.as.boolean;
        case MV_NUM:  return v.as.number != 0.0;
        default:      return 1;
    }
}

void metal_vm_jit_compile(MetalVM* vm, int fn_idx) {
    (void)vm;
    MetalFunction* f = &vm->functions[fn_idx];
    
#ifdef SAGE_BARE_METAL
    // Bare-metal: code is already in executable memory (no W^X), just use the chunk directly
    (void)f;
    return;
#else
    // Allocate space for JIT code in the vm's heap or using malloc
    extern void* malloc(unsigned long size);
    unsigned char* code_buf = (unsigned char*)malloc(64);
    if (!code_buf) return;
    
    int pos = 0;
    
    // Compile basic function prologue (x86-64):
    // push rbp
    // mov rbp, rsp
    code_buf[pos++] = 0x55;
    code_buf[pos++] = 0x48; code_buf[pos++] = 0x89; code_buf[pos++] = 0xe5;
    
    // Return a nil value: type = 0 (MV_NIL), number = 0.0
    // MetalValue struct size is 16 bytes. Let's return it in RAX/RDX:
    // mov rax, 0 (type)
    code_buf[pos++] = 0x48; code_buf[pos++] = 0xc7; code_buf[pos++] = 0xc0;
    code_buf[pos++] = 0x00; code_buf[pos++] = 0x00; code_buf[pos++] = 0x00; code_buf[pos++] = 0x00;
    // mov rdx, 0 (payload)
    code_buf[pos++] = 0x48; code_buf[pos++] = 0xc7; code_buf[pos++] = 0xc2;
    code_buf[pos++] = 0x00; code_buf[pos++] = 0x00; code_buf[pos++] = 0x00; code_buf[pos++] = 0x00;
    
    // pop rbp
    code_buf[pos++] = 0x5d;
    // ret
    code_buf[pos++] = 0xc3;
    
    f->native_code = (void*)code_buf;
    f->jit_compiled = 1;
#endif
}

static int metal_step_preflight(MetalVM* vm, int op, int instruction_offset) {
    if (!metal_validate_operands(vm, vm->code, vm->code_length,
                                 instruction_offset, NULL)) {
        return metal_vm_fail(vm, "Metal VM: invalid instruction");
    }
    MetalInstructionFlow flow;
    if (!metal_instruction_flow(vm, vm->code, vm->code_length,
                                instruction_offset, &flow)) {
        return metal_vm_fail(vm, "Metal VM: invalid opcode");
    }
    if (vm->sp < 0 || vm->sp > METAL_STACK_SIZE || vm->sp < flow.pops) {
        return metal_vm_fail(vm, "Metal VM: stack underflow");
    }
    int operand_pos = instruction_offset + 1;
    if (op == OP_DUP) {
        int distance = vm->code[operand_pos];
        if (distance >= vm->sp) return metal_vm_fail(vm, "Metal VM: invalid duplicate");
    } else if (op == OP_GET_LOCAL) {
        int index = (vm->code[operand_pos] << 8) | vm->code[operand_pos + 1];
        if (index >= vm->sp) return metal_vm_fail(vm, "Metal VM: invalid local index");
    } else if (op == OP_SET_LOCAL) {
        int index = (vm->code[operand_pos] << 8) | vm->code[operand_pos + 1];
        if (vm->sp < 1 || index >= vm->sp) return metal_vm_fail(vm, "Metal VM: invalid local index");
    } else if (op == OP_ARRAY || op == OP_TUPLE) {
        int count = (vm->code[operand_pos] << 8) | vm->code[operand_pos + 1];
        if (count > vm->sp) return metal_vm_fail(vm, "Metal VM: stack underflow");
    } else if (op == OP_DICT) {
        int count = (vm->code[operand_pos] << 8) | vm->code[operand_pos + 1];
        if (count * 2 > vm->sp) return metal_vm_fail(vm, "Metal VM: stack underflow");
    }
    if (flow.branch_kind == 3 && vm->sp >= METAL_STACK_SIZE) {
        return metal_vm_fail(vm, "Metal VM: exception stack overflow");
    }
    return 1;
}

int metal_vm_step(MetalVM* vm) {
    if (vm == NULL) return 0;
    if (vm->const_count < 0 || vm->const_count > METAL_CONST_POOL ||
        vm->string_used < 0 || vm->string_used > METAL_STRING_POOL ||
        vm->array_count < 0 || vm->array_count > (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0])) ||
        vm->dict_count < 0 || vm->dict_count > (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0])) ||
        vm->hsp < 0 || vm->hsp > 128) {
        return metal_vm_fail(vm, "Metal VM: invalid runtime state");
    }
    if (vm->halted || vm->error || vm->ip < 0 ||
        vm->code_length < 0 || vm->ip >= vm->code_length ||
        (vm->code_length > 0 && vm->code == NULL)) return 0;

    int instruction_offset = vm->ip;
    int op = read_u8(vm->code, &vm->ip);
    if (!metal_step_preflight(vm, op, instruction_offset)) return 0;

    switch (op) {
        case OP_HALT:
            vm->halted = 1;
            return 0;

        case OP_CONSTANT: {
            int idx = read_u16(vm->code, &vm->ip);
            if (idx < vm->const_count)
                metal_vm_push(vm, vm->constants[idx]);
            break;
        }

        case OP_NIL:   metal_vm_push(vm, mv_nil()); break;
        case OP_TRUE:  metal_vm_push(vm, mv_bool(1)); break;
        case OP_FALSE: metal_vm_push(vm, mv_bool(0)); break;
        case OP_POP:   metal_vm_pop(vm); break;
        case OP_GET_LOCAL: {
            int index = read_u16(vm->code, &vm->ip);
            if (!metal_vm_push(vm, vm->stack[index])) return 0;
            break;
        }
        case OP_SET_LOCAL: {
            int index = read_u16(vm->code, &vm->ip);
            vm->stack[index] = vm->stack[vm->sp - 1];
            break;
        }
         case OP_DUP: {
             int distance = read_u8(vm->code, &vm->ip);
             MetalValue value = metal_vm_peek(vm, distance);
             if (!metal_vm_push(vm, value)) return 0;
             break;
         }

        case OP_DEFINE_GLOBAL: {
             int name_idx = read_u16(vm->code, &vm->ip);
             MetalValue val = metal_vm_pop(vm);
             const char* name = metal_string_get(vm, vm->constants[name_idx].as.str_idx);
             int name_len = metal_string_length(name, METAL_STRING_POOL);
             if (name_len < 0) return metal_vm_fail(vm, "Metal VM: invalid string");
             unsigned int hash = fnv1a_hash(name, name_len);
             scope_define(vm, hash, val);
            break;
        }

        case OP_GET_GLOBAL: {
             int name_idx = read_u16(vm->code, &vm->ip);
             const char* name = metal_string_get(vm, vm->constants[name_idx].as.str_idx);
             int name_len = metal_string_length(name, METAL_STRING_POOL);
             if (name_len < 0) return metal_vm_fail(vm, "Metal VM: invalid string");
             unsigned int hash = fnv1a_hash(name, name_len);
             MetalValue val;
            if (scope_lookup(vm, hash, &val))
                metal_vm_push(vm, val);
            else
                metal_vm_push(vm, mv_nil());
            break;
        }

        case OP_SET_GLOBAL: {
             int name_idx = read_u16(vm->code, &vm->ip);
             MetalValue val = metal_vm_pop(vm);
             const char* name = metal_string_get(vm, vm->constants[name_idx].as.str_idx);
             int name_len = metal_string_length(name, METAL_STRING_POOL);
             if (name_len < 0) return metal_vm_fail(vm, "Metal VM: invalid string");
             unsigned int hash = fnv1a_hash(name, name_len);
             scope_assign(vm, hash, val);
            break;
        }

        // Arithmetic
        case OP_ADD: {
            MetalValue b = metal_vm_pop(vm);
            MetalValue a = metal_vm_pop(vm);
            if (a.type == MV_NUM && b.type == MV_NUM) {
                metal_vm_push(vm, mv_num(a.as.number + b.as.number));
            } else if (a.type == MV_STR && b.type == MV_STR) {
                 const char* s1 = metal_string_get(vm, a.as.str_idx);
                 const char* s2 = metal_string_get(vm, b.as.str_idx);
                 int len1 = metal_string_length(s1, METAL_STRING_POOL);
                 int len2 = metal_string_length(s2, METAL_STRING_POOL);
                 if (len1 < 0 || len2 < 0) {
                     return metal_vm_fail(vm, "Metal VM: invalid string");
                 }
                 char concat_buf[1024];
                if (len1 + len2 < 1024) {
                    memcpy(concat_buf, s1, len1);
                    memcpy(concat_buf + len1, s2, len2);
                    int new_idx = metal_string_intern(vm, concat_buf, len1 + len2);
                    if (new_idx < 0) {
                        (void)metal_vm_fail(vm, "Metal VM: string pool overflow");
                        return 0;
                    }
                    MetalValue res;
                    res.type = MV_STR;
                    res.as.str_idx = new_idx;
                    metal_vm_push(vm, res);
                } else {
                    vm->error = 1;
                    vm->error_msg = "String concatenation buffer overflow";
                    metal_vm_push(vm, mv_nil());
                }
            } else {
                metal_vm_push(vm, mv_nil());
            }
            break;
        }
        case OP_SUB: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num(a.as.number - b.as.number));
            break;
        }
        case OP_MUL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num(a.as.number * b.as.number));
            break;
        }
        case OP_DIV: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            if (b.as.number == 0.0) { vm->error = 1; vm->error_msg = "division by zero"; return 0; }
            metal_vm_push(vm, mv_num(a.as.number / b.as.number));
            break;
        }
        case OP_MOD: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            if (b.as.number == 0.0) { vm->error = 1; vm->error_msg = "modulo by zero"; return 0; }
            long long la = (long long)a.as.number, lb = (long long)b.as.number;
            metal_vm_push(vm, mv_num((double)(la % lb)));
            break;
        }
        case OP_NEGATE: {
            MetalValue a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num(-a.as.number));
            break;
        }

        // Comparison
        case OP_EQUAL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            int eq = (a.type == b.type) && (a.type == MV_NUM ? a.as.number == b.as.number :
                     a.type == MV_BOOL ? a.as.boolean == b.as.boolean :
                     a.type == MV_STR ? strcmp(metal_string_get(vm, a.as.str_idx), metal_string_get(vm, b.as.str_idx)) == 0 :
                     a.type == MV_NIL ? 1 : 0);
            metal_vm_push(vm, mv_bool(eq));
            break;
        }
        case OP_NOT_EQUAL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            int eq = (a.type == b.type) && (a.type == MV_NUM ? a.as.number == b.as.number :
                     a.type == MV_BOOL ? a.as.boolean == b.as.boolean :
                     a.type == MV_STR ? strcmp(metal_string_get(vm, a.as.str_idx), metal_string_get(vm, b.as.str_idx)) == 0 :
                     a.type == MV_NIL ? 1 : 0);
            metal_vm_push(vm, mv_bool(!eq));
            break;
        }
        case OP_GREATER: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            if (a.type == MV_STR && b.type == MV_STR) {
                metal_vm_push(vm, mv_bool(strcmp(metal_string_get(vm, a.as.str_idx), metal_string_get(vm, b.as.str_idx)) > 0));
            } else {
                metal_vm_push(vm, mv_bool(a.as.number > b.as.number));
            }
            break;
        }
        case OP_GREATER_EQUAL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            if (a.type == MV_STR && b.type == MV_STR) {
                metal_vm_push(vm, mv_bool(strcmp(metal_string_get(vm, a.as.str_idx), metal_string_get(vm, b.as.str_idx)) >= 0));
            } else {
                metal_vm_push(vm, mv_bool(a.as.number >= b.as.number));
            }
            break;
        }
        case OP_LESS: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            if (a.type == MV_STR && b.type == MV_STR) {
                metal_vm_push(vm, mv_bool(strcmp(metal_string_get(vm, a.as.str_idx), metal_string_get(vm, b.as.str_idx)) < 0));
            } else {
                metal_vm_push(vm, mv_bool(a.as.number < b.as.number));
            }
            break;
        }
        case OP_LESS_EQUAL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            if (a.type == MV_STR && b.type == MV_STR) {
                metal_vm_push(vm, mv_bool(strcmp(metal_string_get(vm, a.as.str_idx), metal_string_get(vm, b.as.str_idx)) <= 0));
            } else {
                metal_vm_push(vm, mv_bool(a.as.number <= b.as.number));
            }
            break;
        }
        case OP_NOT: {
            MetalValue a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(!metal_truthy(a)));
            break;
        }
        case OP_TRUTHY: {
            MetalValue a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(metal_truthy(a)));
            break;
        }
        case OP_PRINT: {
            MetalValue value = metal_vm_pop(vm);
            metal_print_value(vm, value);
            if (vm->write_char) vm->write_char('\n');
            break;
        }

        // Bitwise
        case OP_BIT_AND: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num((double)((long long)a.as.number & (long long)b.as.number)));
            break;
        }
        case OP_BIT_OR: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num((double)((long long)a.as.number | (long long)b.as.number)));
            break;
        }
        case OP_BIT_XOR: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num((double)((long long)a.as.number ^ (long long)b.as.number)));
            break;
        }
        case OP_BIT_NOT: {
            MetalValue a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num((double)(~(long long)a.as.number)));
            break;
        }
        case OP_SHIFT_LEFT: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num((double)((long long)a.as.number << (int)b.as.number)));
            break;
        }
        case OP_SHIFT_RIGHT: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_num((double)((long long)a.as.number >> (int)b.as.number)));
            break;
        }

        // Control flow
        case OP_JUMP: {
            int offset = read_u16(vm->code, &vm->ip);
            vm->ip = offset;
            break;
        }
        case OP_JUMP_IF_FALSE: {
            int offset = read_u16(vm->code, &vm->ip);
            if (vm->sp <= 0) return metal_vm_fail(vm, "Metal VM: stack underflow");
            MetalValue cond = metal_vm_peek(vm, 0);
            if (!metal_truthy(cond)) vm->ip = offset;
            break;
        }
        case OP_LOOP_BACK: {
            int offset = read_u16(vm->code, &vm->ip);
            vm->ip -= offset;
            break;
        }

        // Scope
        case OP_PUSH_ENV:
            if (vm->scope_depth < METAL_ENV_DEPTH - 1) {
                vm->scope_depth++;
                vm->scopes[vm->scope_depth].count = 0;
            }
            break;
        case OP_POP_ENV:
            if (vm->scope_depth > 0) vm->scope_depth--;
            break;

        // Arrays & Tuples
        case OP_ARRAY:
        case OP_TUPLE: {
            int count = read_u16(vm->code, &vm->ip);
            int arr = metal_array_new(vm);
            if (arr < 0) return metal_vm_fail(vm, "Metal VM: array pool overflow");
            if (vm->sp >= count) {
                for (int i = count - 1; i >= 0; i--) {
                    MetalValue elem = vm->stack[vm->sp - count + i];
                    metal_array_push(vm, arr, elem);
                }
                vm->sp -= count;
            }
            MetalValue v; v.type = MV_ARR; v.as.arr_idx = arr;
            metal_vm_push(vm, v);
            break;
        }

        case OP_DICT: {
            int count = read_u16(vm->code, &vm->ip);
            int dict = metal_dict_new(vm);
            if (dict < 0) return metal_vm_fail(vm, "Metal VM: dictionary pool overflow");
            if (vm->sp >= count * 2) {
                for (int i = 0; i < count; i++) {
                    MetalValue val = metal_vm_pop(vm);
                    MetalValue key = metal_vm_pop(vm);
                    if (key.type == MV_STR) {
                        metal_dict_set(vm, dict, key.as.str_idx, val);
                    }
                }
            }
            MetalValue v; v.type = MV_DICT; v.as.dict_idx = dict;
            metal_vm_push(vm, v);
            break;
        }

        case OP_SLICE: {
            MetalValue end = metal_vm_pop(vm);
            MetalValue start = metal_vm_pop(vm);
            MetalValue obj = metal_vm_pop(vm);
            (void)end; (void)start; (void)obj;
            // Bare-metal slice: return nil for now or implement array subset
            metal_vm_push(vm, mv_nil());
            break;
        }

        case OP_DEFINE_FN: {
            int name_idx = read_u16(vm->code, &vm->ip);
            int fn_idx = read_u16(vm->code, &vm->ip);
            (void)name_idx; (void)fn_idx;
            // Function definition handled by loader/compiler for now
            break;
        }

        // Generator opcodes
        case OP_CREATE_GENERATOR: {
            int name_idx = read_u16(vm->code, &vm->ip);
            int fn_idx = read_u16(vm->code, &vm->ip);
            (void)name_idx;
            if (vm->gen_count < METAL_GENERATOR_MAX) {
                int gi = vm->gen_count++;
                vm->generators[gi].fn_idx = fn_idx;
                vm->generators[gi].saved_ip = 0;
                vm->generators[gi].is_exhausted = 0;
                metal_vm_push(vm, mv_generator(gi));
            } else {
                metal_vm_push(vm, mv_nil());
            }
            break;
        }
        case OP_YIELD: {
            // Value to yield is on stack. Save IP to current generator.
             if (vm->current_gen_idx >= 0 && vm->current_gen_idx < vm->gen_count) {
                 MetalGenerator* gen = &vm->generators[vm->current_gen_idx];
                gen->saved_ip = vm->ip;
                gen->is_exhausted = 0;
                vm->current_gen_idx = -1;
            }
            // Pop call frame to return to caller
            if (vm->csp > 0) {
                vm->csp--;
                vm->ip = vm->call_stack[vm->csp].ip;
                vm->code = vm->call_stack[vm->csp].code;
                vm->code_length = vm->call_stack[vm->csp].code_length;
                // Yielded value remains on stack as "return value"
            }
            break;
        }
        case OP_GENERATOR_NEXT: {
            MetalValue gen_val = metal_vm_pop(vm);
            if (gen_val.type != MV_GENERATOR) {
                metal_vm_push(vm, mv_nil());
                break;
            }
            int gi = gen_val.as.gen_idx;
             if (gi < 0 || gi >= vm->gen_count || gi >= METAL_GENERATOR_MAX) {
                metal_vm_push(vm, mv_nil());
                break;
            }
            MetalGenerator* gen = &vm->generators[gi];
            if (gen->is_exhausted) {
                metal_vm_push(vm, mv_nil());
                break;
            }
            if (gen->saved_ip == 0) {
                // First call - invoke function
                 if (gen->fn_idx >= 0 && gen->fn_idx < vm->fn_count &&
                     gen->fn_idx < 256) {
                    MetalFunction* f = &vm->functions[gen->fn_idx];
                     vm->current_gen_idx = gi;
                     if (vm->csp < 0 || vm->csp >= METAL_CALL_STACK_SIZE) {
                         return metal_vm_fail(vm, "Metal VM: call stack overflow");
                     }
                     {
                        vm->call_stack[vm->csp].ip = vm->ip;
                        vm->call_stack[vm->csp].code = vm->code;
                        vm->call_stack[vm->csp].code_length = vm->code_length;
                         vm->csp++;
                         if (vm->chunk_count < 1 || vm->chunks[0] == NULL ||
                             f->code_offset < 0 || f->code_length < 0 ||
                             f->code_length > vm->chunk_lengths[0] ||
                             f->code_offset > vm->chunk_lengths[0] - f->code_length) {
                             vm->csp--;
                             return metal_vm_fail(vm, "Metal VM: invalid generator code");
                         }
                         vm->code = vm->chunks[0];
                         vm->ip = f->code_offset;
                         vm->code_length = f->code_length;
                    }
                } else {
                    metal_vm_push(vm, mv_nil());
                }
             } else {
                 if (gen->fn_idx < 0 || gen->fn_idx >= vm->fn_count ||
                     gen->fn_idx >= 256) {
                     return metal_vm_fail(vm, "Metal VM: invalid generator function");
                 }
                 // Resume - set IP to saved position
                  vm->current_gen_idx = gi;
                  if (vm->csp < 0 || vm->csp >= METAL_CALL_STACK_SIZE) {
                      return metal_vm_fail(vm, "Metal VM: call stack overflow");
                  }
                   MetalFunction* f = &vm->functions[gen->fn_idx];
                   if (vm->chunk_count < 1 || vm->chunks[0] == NULL ||
                       f->code_length < 0 || f->code_length > vm->chunk_lengths[0] ||
                       gen->saved_ip < 0 || gen->saved_ip > f->code_length ||
                       (gen->saved_ip % 4) != 0) {
                       return metal_vm_fail(vm, "Metal VM: invalid generator resume state");
                   }
                   vm->call_stack[vm->csp].ip = vm->ip;
                   vm->call_stack[vm->csp].code = vm->code;
                   vm->call_stack[vm->csp].code_length = vm->code_length;
                   vm->csp++;
                   vm->code = vm->chunks[0];
                   vm->ip = gen->saved_ip;
                   vm->code_length = f->code_length;
                   gen->saved_ip = 0;
            }
            break;
        }

        // OOP
        case OP_CLASS: {
            int name_idx = read_u16(vm->code, &vm->ip);
            (void)name_idx;
             int dict = metal_dict_new(vm);
             if (dict < 0) return metal_vm_fail(vm, "Metal VM: dictionary pool overflow");
             MetalValue v; v.type = MV_DICT; v.as.dict_idx = dict;
            // Mark as class if needed
            metal_vm_push(vm, v);
            break;
        }

        case OP_METHOD: {
            int name_idx = read_u16(vm->code, &vm->ip);
            MetalValue fn = metal_vm_pop(vm);
            MetalValue cls = metal_vm_peek(vm, 0);
            if (cls.type == MV_DICT) {
                metal_dict_set(vm, cls.as.dict_idx, vm->constants[name_idx].as.str_idx, fn);
            }
            break;
        }

        case OP_INHERIT: {
            MetalValue cls = metal_vm_pop(vm);
            MetalValue parent = metal_vm_pop(vm);
            if (cls.type == MV_DICT && parent.type == MV_DICT &&
                cls.as.dict_idx >= 0 && cls.as.dict_idx < vm->dict_count &&
                parent.as.dict_idx >= 0 && parent.as.dict_idx < vm->dict_count) {
                MetalDict* pd = &vm->dicts[parent.as.dict_idx];
                for (int i = 0; i < pd->count; i++) {
                    metal_dict_set(vm, cls.as.dict_idx, pd->key_str_idx[i], pd->values[i]);
                }
            }
            metal_vm_push(vm, cls);
            break;
        }

        case OP_GET_PROPERTY: {
            int name_idx = read_u16(vm->code, &vm->ip);
            MetalValue obj = metal_vm_pop(vm);
            if (obj.type == MV_DICT) {
                metal_vm_push(vm, metal_dict_get(vm, obj.as.dict_idx, vm->constants[name_idx].as.str_idx));
            } else {
                metal_vm_push(vm, mv_nil());
            }
            break;
        }

        case OP_SET_PROPERTY: {
            int name_idx = read_u16(vm->code, &vm->ip);
            MetalValue val = metal_vm_pop(vm);
            MetalValue obj = metal_vm_pop(vm);
            if (obj.type == MV_DICT) {
                metal_dict_set(vm, obj.as.dict_idx, vm->constants[name_idx].as.str_idx, val);
            }
            metal_vm_push(vm, val);
            break;
        }

        case OP_CALL_METHOD: {
            int name_idx = read_u16(vm->code, &vm->ip);
            int argc = read_u8(vm->code, &vm->ip);
            (void)argc;
            MetalValue obj = metal_vm_peek(vm, argc); // Obj is below args
            if (obj.type == MV_DICT) {
                MetalValue fn = metal_dict_get(vm, obj.as.dict_idx, vm->constants[name_idx].as.str_idx);
                // Call fn...
                if (fn.type == MV_FN) {
                   // ... similar to OP_CALL but push 'self' ...
                }
            }
            break;
        }

        // Exceptions
        case OP_SETUP_TRY: {
             int handler = read_u16(vm->code, &vm->ip);
              if (handler >= vm->code_length || vm->hsp < 0 || vm->hsp >= 128 ||
                 vm->sp < 0 || vm->sp > METAL_STACK_SIZE) {
                 return metal_vm_fail(vm, "Metal VM: invalid exception handler");
             }
             if (vm->hsp < 128) {
                vm->handlers[vm->hsp].ip = handler;
                vm->handlers[vm->hsp].stack_size = vm->sp;
                vm->hsp++;
            }
            break;
        }

        case OP_END_TRY:
            if (vm->hsp > 0) vm->hsp--;
            break;

        case OP_RAISE: {
            MetalValue val = metal_vm_pop(vm);
            vm->exception_value = val;
            vm->is_throwing = 1;
             if (vm->hsp > 0) {
                 vm->hsp--;
                 if (vm->handlers[vm->hsp].ip < 0 ||
                     vm->handlers[vm->hsp].ip > vm->code_length ||
                     vm->handlers[vm->hsp].stack_size < 0 ||
                     vm->handlers[vm->hsp].stack_size >= METAL_STACK_SIZE) {
                     return metal_vm_fail(vm, "Metal VM: invalid exception handler");
                 }
                 vm->ip = vm->handlers[vm->hsp].ip;
                 vm->sp = vm->handlers[vm->hsp].stack_size;
                 metal_vm_push(vm, vm->exception_value);
                vm->is_throwing = 0;
            } else {
                vm->error = 1;
                vm->error_msg = "Unhandled exception";
                return 0;
            }
            break;
        }

        case OP_IMPORT: {
            int name_idx = read_u16(vm->code, &vm->ip);
            (void)name_idx;
            // Native bridge should handle dynamic loading
            metal_vm_push(vm, mv_nil());
            break;
        }

        case OP_EXEC_AST_STMT: {
            int idx = read_u16(vm->code, &vm->ip);
            (void)idx;
            // Bridged to host AST interpreter
            metal_vm_push(vm, mv_nil());
            break;
        }

        // GPU Opcodes (Stubbed/Bridged)
        case OP_GPU_POLL_EVENTS:
        case OP_GPU_WINDOW_SHOULD_CLOSE:
        case OP_GPU_GET_TIME:
        case OP_GPU_KEY_PRESSED:
        case OP_GPU_KEY_DOWN:
        case OP_GPU_MOUSE_POS:
        case OP_GPU_MOUSE_DELTA:
        case OP_GPU_UPDATE_INPUT:
        case OP_GPU_BEGIN_COMMANDS:
        case OP_GPU_END_COMMANDS:
        case OP_GPU_CMD_BEGIN_RP:
        case OP_GPU_CMD_END_RP:
        case OP_GPU_CMD_DRAW:
        case OP_GPU_CMD_BIND_GP:
        case OP_GPU_CMD_BIND_DS:
        case OP_GPU_CMD_SET_VP:
        case OP_GPU_CMD_SET_SC:
        case OP_GPU_CMD_BIND_VB:
        case OP_GPU_CMD_BIND_IB:
        case OP_GPU_CMD_DRAW_IDX:
        case OP_GPU_SUBMIT_SYNC:
        case OP_GPU_ACQUIRE_IMG:
        case OP_GPU_PRESENT:
        case OP_GPU_WAIT_FENCE:
        case OP_GPU_RESET_FENCE:
        case OP_GPU_UPDATE_UNIFORM:
        case OP_GPU_CMD_PUSH_CONST:
        case OP_GPU_CMD_DISPATCH:
            // GPU opcodes require host implementation (sgpu_*)
            break;

        case OP_CALL: {
            int arg_count = read_u8(vm->code, &vm->ip);
            MetalValue fn = metal_vm_pop(vm);
            if (fn.type == MV_FN) {
                if (fn.as.fn_idx < 0 || fn.as.fn_idx >= vm->fn_count ||
                    fn.as.fn_idx >= 256 || arg_count > 16) {
                    return metal_vm_fail(vm, "Metal VM: invalid function call");
                }
                MetalFunction* f = &vm->functions[fn.as.fn_idx];
                f->call_count++;
                
                // Trigger JIT compilation when a function gets hot
                if (f->call_count >= 5 && !f->jit_compiled) {
                    metal_vm_jit_compile(vm, fn.as.fn_idx);
                }
                
                if (f->jit_compiled && f->native_code) {
                    // Collect arguments for JIT/AOT call
                     MetalValue args[16];
                     for (int i = 0; i < arg_count; i++) {
                         args[arg_count - 1 - i] = metal_vm_pop(vm);
                     }
                    typedef MetalValue (*MetalJitFn)(MetalVM*, int, MetalValue*);
                    MetalJitFn native_fn = (MetalJitFn)(intptr_t)f->native_code;
                    MetalValue ret_val = native_fn(vm, arg_count, args);
                    metal_vm_push(vm, ret_val);
                } else {
                     if (vm->csp < 0 || vm->csp >= METAL_CALL_STACK_SIZE) {
                         return metal_vm_fail(vm, "Metal VM: call stack overflow");
                     }
                     {
                        vm->call_stack[vm->csp].ip = vm->ip;
                        vm->call_stack[vm->csp].code = vm->code;
                        vm->call_stack[vm->csp].code_length = vm->code_length;
                         vm->csp++;
                         if (vm->chunk_count < 1 || vm->chunks[0] == NULL ||
                             f->code_offset < 0 || f->code_length < 0 ||
                             f->code_length > vm->chunk_lengths[0] ||
                             f->code_offset > vm->chunk_lengths[0] - f->code_length) {
                             vm->csp--;
                             return metal_vm_fail(vm, "Metal VM: invalid function code");
                         }
                         vm->code = vm->chunks[0];
                         vm->ip = f->code_offset;
                         vm->code_length = f->code_length;
                    }
                }
            } else {
                // For now, allow calling native functions if we add them
            }
            break;
        }
        case OP_ARRAY_LEN: {
            MetalValue a = metal_vm_pop(vm);
            if (a.type == MV_ARR)
                metal_vm_push(vm, mv_num((double)metal_array_len(vm, a.as.arr_idx)));
            else
                metal_vm_push(vm, mv_num(0));
            break;
        }
         case OP_GET_INDEX: {
             MetalValue idx = metal_vm_pop(vm);
             MetalValue obj = metal_vm_pop(vm);
             int index = 0;
             if (obj.type == MV_ARR && metal_value_index(idx, &index))
                 metal_vm_push(vm, metal_array_get(vm, obj.as.arr_idx, index));
             else
                 metal_vm_push(vm, mv_nil());
             break;
         }
         case OP_SET_INDEX: {
             MetalValue val = metal_vm_pop(vm);
             MetalValue idx = metal_vm_pop(vm);
             MetalValue obj = metal_vm_pop(vm);
             int index = 0;
             if (obj.type == MV_ARR && metal_value_index(idx, &index)) {
                 int ai = obj.as.arr_idx;
                 int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
                 if (ai >= 0 && ai < max && vm->arrays[ai].count >= 0 &&
                     index >= 0 && index < vm->arrays[ai].count)
                     vm->arrays[ai].elems[index] = val;
             }
             if (!metal_vm_push(vm, val)) return 0;
             break;
         }

        case OP_RETURN:
            // Mark generator exhausted if returning from generator context
            if (vm->current_gen_idx >= 0) {
                vm->generators[vm->current_gen_idx].is_exhausted = 1;
                vm->current_gen_idx = -1;
            }
            if (vm->csp > 0) {
                vm->csp--;
                vm->ip = vm->call_stack[vm->csp].ip;
                vm->code = vm->call_stack[vm->csp].code;
                vm->code_length = vm->call_stack[vm->csp].code_length;
                return 1;
            }
            return 0;

        default:
            vm->error = 1;
            vm->error_msg = "Metal VM: unknown opcode";
            return 0;
    }

    return 1; // Continue execution
}

int metal_vm_run(MetalVM* vm) {
    if (vm == NULL) return -1;
    while (metal_vm_step(vm)) {
    }
    return vm->error ? -1 : 0;
}
