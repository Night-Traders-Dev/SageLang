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

int metal_vm_load_binary(MetalVM* vm, const unsigned char* data, int size) {
    if (size < 8) return -1;
    int pos = 0;

    // Magic: SGVM
    if (data[pos++] != 'S' || data[pos++] != 'G' || data[pos++] != 'V' || data[pos++] != 'M')
        return -2;

    // Version
    if (data[pos++] != 0x01) return -3;

    // Flags
    pos++;

    // Constant Count
    int const_count = (data[pos] << 8) | data[pos + 1];
    pos += 2;

    for (int i = 0; i < const_count; i++) {
        unsigned char type = data[pos++];
        if (type == 1) { // MV_NUM
            union { double d; unsigned char b[8]; } u;
            for (int j = 0; j < 8; j++) u.b[j] = data[pos + 7 - j];
            metal_vm_add_constant(vm, mv_num(u.d));
            pos += 8;
        } else if (type == 3) { // MV_STR
            int len = (data[pos] << 8) | data[pos + 1];
            pos += 2;
            int str_idx = metal_string_intern(vm, (const char*)&data[pos], len);
            metal_vm_add_constant(vm, (MetalValue){MV_STR, {.str_idx = str_idx}});
            pos += len;
        } else {
            return -4;
        }
    }

    // Chunk Count
    int chunk_count = (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3];
    pos += 4;

    for (int i = 0; i < chunk_count; i++) {
        int code_len = (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3];
        pos += 4;
        if (pos + code_len > size) return -5;
        if (vm->chunk_count < 1024) {
            vm->chunks[vm->chunk_count] = &data[pos];
            vm->chunk_lengths[vm->chunk_count] = code_len;
            vm->chunk_count++;
        }
        pos += code_len;
    }

    return 0;
}

int metal_vm_verify(MetalVM* vm) {
    for (int c = 0; c < vm->chunk_count; c++) {
        int ip = 0;
        const unsigned char* code = vm->chunks[c];
        int code_length = vm->chunk_lengths[c];
        while (ip < code_length) {
            unsigned char op = code[ip++];
            switch (op) {
                case OP_CONSTANT:
                case OP_GET_GLOBAL:
                case OP_DEFINE_GLOBAL:
                case OP_SET_GLOBAL: {
                    if (ip + 2 > code_length) return -1;
                    int idx = (code[ip] << 8) | code[ip + 1];
                    if (idx >= vm->const_count) return -2;
                    ip += 2;
                    break;
                }
                case OP_JUMP:
                case OP_JUMP_IF_FALSE: {
                    if (ip + 2 > code_length) return -1;
                    int target = (code[ip] << 8) | code[ip + 1];
                    if (target >= code_length) return -3;
                    ip += 2;
                    break;
                }
                case OP_CALL: {
                    if (ip + 1 > code_length) return -1;
                    ip += 1;
                    break;
                }
                case OP_ARRAY: {
                    if (ip + 2 > code_length) return -1;
                    ip += 2;
                    break;
                }
                case OP_DEFINE_FN: {
                    if (ip + 4 > code_length) return -1;
                    ip += 4;
                    break;
                }
                case OP_LOOP_BACK: {
                    if (ip + 2 > code_length) return -1;
                    int offset = (code[ip] << 8) | code[ip + 1];
                    if (ip + 2 - offset < 0) return -3;
                    ip += 2;
                    break;
                }
                case OP_HALT:
                case OP_NIL:
                case OP_TRUE:
                case OP_FALSE:
                case OP_POP:
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
                case OP_DUP:
                case OP_ARRAY_LEN:
                case OP_GET_INDEX:
                case OP_SET_INDEX:
                case OP_BREAK:
                case OP_CONTINUE:
                    break;
                default:
                    return -4;
            }
        }
    }
    return 0;
}

int metal_vm_add_constant(MetalVM* vm, MetalValue value) {
    if (vm->const_count >= METAL_CONST_POOL) return -1;
    vm->constants[vm->const_count] = value;
    return vm->const_count++;
}

// ============================================================================
// Dict Pool
// ============================================================================

int metal_dict_new(MetalVM* vm) {
    if (vm->dict_count >= (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]))) return -1;
    int idx = vm->dict_count++;
    vm->dicts[idx].count = 0;
    vm->dicts[idx].in_use = 1;
    return idx;
}

void metal_dict_set(MetalVM* vm, int dict_idx, int key_str_idx, MetalValue val) {
    if (dict_idx < 0 || dict_idx >= vm->dict_count) return;
    MetalDict* d = &vm->dicts[dict_idx];
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
    if (dict_idx < 0 || dict_idx >= vm->dict_count) return mv_nil();
    MetalDict* d = &vm->dicts[dict_idx];
    for (int i = 0; i < d->count; i++) {
        if (d->key_str_idx[i] == key_str_idx) return d->values[i];
    }
    return mv_nil();
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
        case OP_GREATER_EQUAL: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(a.as.number >= b.as.number));
            break;
        }
        case OP_LESS: {
            MetalValue b = metal_vm_pop(vm), a = metal_vm_pop(vm);
            metal_vm_push(vm, mv_bool(a.as.number < b.as.number));
            break;
        }
        case OP_LESS_EQUAL: {
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

        // Arrays & Tuples
        case OP_ARRAY:
        case OP_TUPLE: {
            int count = read_u16(vm->code, &vm->ip);
            int arr = metal_array_new(vm);
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

        // OOP
        case OP_CLASS: {
            int name_idx = read_u16(vm->code, &vm->ip);
            (void)name_idx;
            int dict = metal_dict_new(vm);
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
            if (cls.type == MV_DICT && parent.type == MV_DICT) {
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
            (void)arg_count;
            MetalValue fn = metal_vm_pop(vm);
            if (fn.type == MV_FN) {
                if (vm->csp < METAL_CALL_STACK_SIZE) {
                    vm->call_stack[vm->csp].ip = vm->ip;
                    vm->call_stack[vm->csp].code = vm->code;
                    vm->call_stack[vm->csp].code_length = vm->code_length;
                    vm->csp++;

                    MetalFunction* f = &vm->functions[fn.as.fn_idx];
                    vm->code = vm->chunks[0]; // Assuming all code is in chunks
                    // Actually, functions might need better mapping
                    vm->ip = f->code_offset;
                    vm->code_length = f->code_length;
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
            if (vm->csp > 0) {
                vm->csp--;
                vm->ip = vm->call_stack[vm->csp].ip;
                vm->code = vm->call_stack[vm->csp].code;
                vm->code_length = vm->call_stack[vm->csp].code_length;
                return 1;
            }
            return 0;

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
