// ============================================================================
// SageMetal VM — Freestanding Bytecode Virtual Machine
// ============================================================================
// No malloc, no libc, no OS. Pure static pools and bump allocators.
// Compiles with: -ffreestanding -nostdlib -DSAGE_BARE_METAL -DSAGE_METAL_VM
// ============================================================================

#include "metal_vm.h"

// Bare-metal libc stubs (from bare_metal.c or provided by host)
extern void* memset(void* s, int c, unsigned long n);
extern void* memcpy(void* dest, const void* src, unsigned long n);
extern unsigned long strlen(const char* s);
extern int strcmp(const char* s1, const char* s2);

// Bytecode opcodes — subset matching src/vm/bytecode.h
#define OP_CONSTANT       0
#define OP_NIL            1
#define OP_TRUE           2
#define OP_FALSE          3
#define OP_POP            4
#define OP_DUP            5
#define OP_GET_GLOBAL     6
#define OP_DEFINE_GLOBAL  7
#define OP_SET_GLOBAL     8
#define OP_ADD            14
#define OP_SUB            15
#define OP_MUL            16
#define OP_DIV            17
#define OP_MOD            18
#define OP_NEGATE         19
#define OP_EQUAL          20
#define OP_NOT_EQUAL      21
#define OP_GREATER        22
#define OP_GREATER_EQ     23
#define OP_LESS           24
#define OP_LESS_EQ        25
#define OP_NOT            26
#define OP_TRUTHY         27
#define OP_BIT_AND        28
#define OP_BIT_OR         29
#define OP_BIT_XOR        30
#define OP_BIT_NOT        31
#define OP_SHIFT_LEFT     32
#define OP_SHIFT_RIGHT    33
#define OP_JUMP           34
#define OP_JUMP_IF_FALSE  35
#define OP_LOOP_BACK      36
#define OP_CALL           37
#define OP_RETURN         38
#define OP_PRINT          39
#define OP_ARRAY          40
#define OP_ARRAY_LEN      41
#define OP_GET_INDEX      42
#define OP_SET_INDEX      43
#define OP_PUSH_ENV       48
#define OP_POP_ENV        49
#define OP_BREAK          50
#define OP_CONTINUE       51
#define OP_DEFINE_FN      52
#define OP_HALT           0xFF

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

static void metal_print_str(MetalVM* vm, const char* s) {
    if (!vm->write_char) return;
    while (*s) vm->write_char(*s++);
}

static void metal_print_int(MetalVM* vm, long long n) {
    if (n < 0) { if (vm->write_char) vm->write_char('-'); n = -n; }
    char buf[24];
    int i = 0;
    if (n == 0) { buf[i++] = '0'; }
    else { while (n > 0) { buf[i++] = '0' + (int)(n % 10); n /= 10; } }
    while (--i >= 0) if (vm->write_char) vm->write_char(buf[i]);
}

static void metal_print_double(MetalVM* vm, double d) {
    if (d == (double)(long long)d && d >= -1e15 && d <= 1e15) {
        metal_print_int(vm, (long long)d);
    } else {
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

MetalValue mv_num(double val) {
    MetalValue v; v.type = MV_NUM; v.as.number = val; return v;
}

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

// ============================================================================
// VM Init & Load
// ============================================================================

void metal_vm_init(MetalVM* vm) {
    memset(vm, 0, sizeof(MetalVM));
}

void metal_vm_load(MetalVM* vm, const unsigned char* code, int length) {
    vm->code = code;
    vm->code_length = length;
    vm->ip = 0;
}

int metal_vm_add_constant(MetalVM* vm, MetalValue value) {
    if (vm->const_count >= METAL_CONST_POOL) return -1;
    vm->constants[vm->const_count] = value;
    return vm->const_count++;
}

// ============================================================================
// Stack Operations
// ============================================================================

int metal_vm_push(MetalVM* vm, MetalValue value) {
    if (vm->sp >= METAL_STACK_SIZE) {
        vm->error = 1;
        vm->error_msg = "Metal VM: stack overflow";
        return 0;
    }
    vm->stack[vm->sp++] = value;
    return 1;
}

MetalValue metal_vm_pop(MetalVM* vm) {
    if (vm->sp <= 0) return mv_nil();
    return vm->stack[--vm->sp];
}

MetalValue metal_vm_peek(MetalVM* vm, int distance) {
    int idx = vm->sp - 1 - distance;
    if (idx < 0 || idx >= vm->sp) return mv_nil();
    return vm->stack[idx];
}

// ============================================================================
// String Pool (bump allocator)
// ============================================================================

int metal_string_intern(MetalVM* vm, const char* s, int len) {
    // Check if already interned
    int search = 0;
    while (search < vm->string_used) {
        const char* existing = &vm->strings[search];
        int existing_len = (int)strlen(existing);
        if (existing_len == len && memcpy(0, 0, 0) == 0) { // memcmp substitute
            int match = 1;
            for (int i = 0; i < len; i++) {
                if (existing[i] != s[i]) { match = 0; break; }
            }
            if (match) return search;
        }
        search += existing_len + 1;
    }

    // Allocate new
    if (vm->string_used + len + 1 > METAL_STRING_POOL) return -1;
    int idx = vm->string_used;
    memcpy(&vm->strings[idx], s, (unsigned long)len);
    vm->strings[idx + len] = '\0';
    vm->string_used += len + 1;
    return idx;
}

const char* metal_string_get(MetalVM* vm, int idx) {
    if (idx < 0 || idx >= vm->string_used) return "";
    return &vm->strings[idx];
}

// ============================================================================
// Array Pool
// ============================================================================

int metal_array_new(MetalVM* vm) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (vm->array_count >= max) return -1;
    int idx = vm->array_count++;
    vm->arrays[idx].count = 0;
    vm->arrays[idx].in_use = 1;
    return idx;
}

void metal_array_push(MetalVM* vm, int arr_idx, MetalValue val) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return;
    MetalArray* a = &vm->arrays[arr_idx];
    if (a->count >= METAL_ARRAY_MAX_ELEMS) return;
    a->elems[a->count++] = val;
}

MetalValue metal_array_get(MetalVM* vm, int arr_idx, int index) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return mv_nil();
    MetalArray* a = &vm->arrays[arr_idx];
    if (index < 0 || index >= a->count) return mv_nil();
    return a->elems[index];
}

int metal_array_len(MetalVM* vm, int arr_idx) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return 0;
    return vm->arrays[arr_idx].count;
}

// ============================================================================
// Environment (scope chain — flat array)
// ============================================================================

static int scope_lookup(MetalVM* vm, unsigned int hash, MetalValue* out) {
    for (int d = vm->scope_depth; d >= 0; d--) {
        MetalScope* s = &vm->scopes[d];
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
    MetalScope* s = &vm->scopes[vm->scope_depth];
    // Check if exists in current scope
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
    for (int d = vm->scope_depth; d >= 0; d--) {
        MetalScope* s = &vm->scopes[d];
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

// ============================================================================
// Main Dispatch Loop
// ============================================================================

int metal_vm_step(MetalVM* vm) {
    if (vm->halted || vm->error || vm->ip >= vm->code_length) return 0;

    int op = read_u8(vm->code, &vm->ip);

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
        case OP_DUP:   metal_vm_push(vm, metal_vm_peek(vm, 0)); break;

        case OP_DEFINE_GLOBAL: {
            int name_idx = read_u16(vm->code, &vm->ip);
            MetalValue val = metal_vm_pop(vm);
            const char* name = metal_string_get(vm, vm->constants[name_idx].as.str_idx);
            unsigned int hash = fnv1a_hash(name, (int)strlen(name));
            scope_define(vm, hash, val);
            break;
        }

        case OP_GET_GLOBAL: {
            int name_idx = read_u16(vm->code, &vm->ip);
            const char* name = metal_string_get(vm, vm->constants[name_idx].as.str_idx);
            unsigned int hash = fnv1a_hash(name, (int)strlen(name));
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
            unsigned int hash = fnv1a_hash(name, (int)strlen(name));
            scope_assign(vm, hash, val);
            break;
        }

        // Arithmetic
        case OP_ADD: {
            MetalValue b = metal_vm_pop(vm);
            MetalValue a = metal_vm_pop(vm);
            if (a.type == MV_NUM && b.type == MV_NUM)
                metal_vm_push(vm, mv_num(a.as.number + b.as.number));
            else
                metal_vm_push(vm, mv_nil());
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
                     a.type == MV_NIL ? 1 : 0);
            metal_vm_push(vm, mv_bool(eq));
            break;
        }
        case OP_NOT_EQUAL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            int eq = (a.type == b.type) && (a.type == MV_NUM ? a.as.number == b.as.number :
                     a.type == MV_BOOL ? a.as.boolean == b.as.boolean :
                     a.type == MV_NIL ? 1 : 0);
            metal_vm_push(vm, mv_bool(!eq));
            break;
        }
        case OP_GREATER: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(a.as.number > b.as.number));
            break;
        }
        case OP_GREATER_EQ: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(a.as.number >= b.as.number));
            break;
        }
        case OP_LESS: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(a.as.number < b.as.number));
            break;
        }
        case OP_LESS_EQ: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(a.as.number <= b.as.number));
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
            MetalValue cond = metal_vm_pop(vm);
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

        // I/O
        case OP_PRINT: {
            MetalValue val = metal_vm_pop(vm);
            metal_print_value(vm, val);
            if (vm->write_char) vm->write_char('\n');
            break;
        }

        // Arrays
        case OP_ARRAY: {
            int count = read_u8(vm->code, &vm->ip);
            int arr = metal_array_new(vm);
            // Elements are on stack in reverse order
            for (int i = count - 1; i >= 0; i--) {
                MetalValue elem = vm->stack[vm->sp - count + i];
                metal_array_push(vm, arr, elem);
            }
            vm->sp -= count;
            MetalValue v; v.type = MV_ARR; v.as.arr_idx = arr;
            metal_vm_push(vm, v);
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
            if (obj.type == MV_ARR)
                metal_vm_push(vm, metal_array_get(vm, obj.as.arr_idx, (int)idx.as.number));
            else
                metal_vm_push(vm, mv_nil());
            break;
        }
        case OP_SET_INDEX: {
            MetalValue val = metal_vm_pop(vm);
            MetalValue idx = metal_vm_pop(vm);
            MetalValue obj = metal_vm_pop(vm);
            if (obj.type == MV_ARR) {
                int ai = obj.as.arr_idx;
                int ii = (int)idx.as.number;
                int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
                if (ai >= 0 && ai < max && ii >= 0 && ii < vm->arrays[ai].count)
                    vm->arrays[ai].elems[ii] = val;
            }
            metal_vm_push(vm, val);
            break;
        }

        case OP_RETURN:
            // For bare-metal, return pops the current function's result
            // The calling convention is handled by the compiler
            return 0; // Signal return to caller

        default:
            // Unknown opcode — halt
            vm->error = 1;
            vm->error_msg = "Metal VM: unknown opcode";
            return 0;
    }

    return 1; // Continue execution
}

int metal_vm_run(MetalVM* vm) {
    while (metal_vm_step(vm)) {
        // Continue executing
    }
    return vm->error ? -1 : 0;
}
