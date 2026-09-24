#include "metal_rv64_vm.h"
#include <stddef.h>

#ifdef SAGE_BARE_METAL
// Freestanding: provide our own libc replacements
static void* rv_memset(void* s, int c, unsigned long n) {
    unsigned char* p = (unsigned char*)s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}
static void* rv_memcpy(void* dest, const void* src, unsigned long n) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* s2 = (const unsigned char*)src;
    while (n--) *d++ = *s2++;
    return dest;
}
static unsigned long rv_strlen(const char* s) {
    unsigned long n = 0;
    while (*s++) n++;
    return n;
}
static int rv_strcmp(const char* s1, const char* s2) {
    while (*s1 && *s1 == *s2) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}
#define memset  rv_memset
#define memcpy  rv_memcpy
#define strlen  rv_strlen
#define strcmp  rv_strcmp
#else
extern void* memset(void* s, int c, unsigned long n);
extern void* memcpy(void* dest, const void* src, unsigned long n);
extern unsigned long strlen(const char* s);
extern int strcmp(const char* s1, const char* s2);
#endif

static int metal_rv64_read_u16(const unsigned char* data, int size, int* pos, int* value) {
    if (data == NULL || pos == NULL || value == NULL || *pos < 0 || *pos > size - 2) return 0;
    *value = ((int)data[*pos] << 8) | data[*pos + 1];
    *pos += 2;
    return 1;
}

static int metal_rv64_read_u32(const unsigned char* data, int size, int* pos, unsigned int* value) {
    if (data == NULL || pos == NULL || value == NULL || *pos < 0 || *pos > size - 4) return 0;
    *value = ((unsigned int)data[*pos] << 24) |
             ((unsigned int)data[*pos + 1] << 16) |
             ((unsigned int)data[*pos + 2] << 8) |
             (unsigned int)data[*pos + 3];
    *pos += 4;
    return 1;
}

static int metal_rv64_fail(MetalRV64VM* vm, const char* message) {
    if (vm != NULL) {
        vm->error = 1;
        vm->running = 0;
        vm->error_msg = message;
    }
    return 0;
}

// ============================================================================
// Helpers / Internals
// ============================================================================

static int metal_rv64_bounded_strlen(const char* text, int limit);

static void metal_rv64_print_str(MetalRV64VM* vm, const char* s) {
    if (vm == NULL || s == NULL || !vm->write_char) return;
    int length = metal_rv64_bounded_strlen(s, METAL_STRING_POOL);
    if (length < 0) return;
    for (int i = 0; i < length; i++) vm->write_char(s[i]);
}

static void metal_rv64_print_int(MetalRV64VM* vm, long long n) {
    if (vm == NULL) return;
    unsigned long long magnitude = n < 0 ? 0ULL - (unsigned long long)n : (unsigned long long)n;
    if (n < 0 && vm->write_char) vm->write_char('-');
    char buf[24];
    int i = 0;
    if (magnitude == 0) { buf[i++] = '0'; }
    else { while (magnitude > 0) { buf[i++] = '0' + (int)(magnitude % 10); magnitude /= 10; } }
    while (--i >= 0) if (vm->write_char) vm->write_char(buf[i]);
}

static void metal_rv64_print_double(MetalRV64VM* vm, double d) {
    if (d >= -1e15 && d <= 1e15 && d == (double)(long long)d) {
        metal_rv64_print_int(vm, (long long)d);
    } else {
        if (!(d >= -1e15 && d <= 1e15)) {
            if (d != d) metal_rv64_print_str(vm, "nan");
            else {
                if (d < 0) metal_rv64_print_str(vm, "-");
                metal_rv64_print_str(vm, "inf");
            }
            return;
        }
        if (d < 0) { if (vm->write_char) vm->write_char('-'); d = -d; }
        long long integer = (long long)d;
        metal_rv64_print_int(vm, integer);
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

static int metal_rv64_bounded_strlen(const char* text, int limit) {
    if (text == NULL || limit < 0) return -1;
    int length = 0;
    while (length < limit && text[length] != '\0') length++;
    return length;
}

static int metal_rv64_string_intern(MetalRV64VM* vm, const char* s, int len) {
    if (vm == NULL || len < 0 || (len > 0 && s == NULL) ||
        vm->string_used < 0 || vm->string_used > METAL_STRING_POOL ||
        len > METAL_STRING_POOL - vm->string_used - 1) {
        return -1;
    }
    int search = 0;
    while (search < vm->string_used) {
        const char* existing = &vm->strings[search];
        int existing_len = metal_rv64_bounded_strlen(existing, METAL_STRING_POOL - search);
        if (existing_len >= METAL_STRING_POOL - search) return -1;
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

static int metal_rv64_intern_checked(MetalRV64VM* vm, const char* text, int length) {
    int index = metal_rv64_string_intern(vm, text, length);
    if (index < 0) (void)metal_rv64_fail(vm, "SGRV string pool overflow");
    return index;
}

static const char* metal_rv64_string_get(const MetalRV64VM* vm, int idx) {
    if (vm == NULL || idx < 0 || idx >= vm->string_used) return "";
    return &vm->strings[idx];
}

static int metal_rv64_string_compare(const char* left, const char* right) {
    int left_len = metal_rv64_bounded_strlen(left, METAL_STRING_POOL);
    int right_len = metal_rv64_bounded_strlen(right, METAL_STRING_POOL);
    if (left_len < 0 || right_len < 0) return -1;
    int common = left_len < right_len ? left_len : right_len;
    for (int i = 0; i < common; i++) {
        if (left[i] != right[i]) return (unsigned char)left[i] - (unsigned char)right[i];
    }
    return left_len - right_len;
}

static int metal_rv64_array_new(MetalRV64VM* vm) {
    if (vm == NULL) return -1;
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (vm->array_count < 0 || vm->array_count >= max) return -1;
    int idx = vm->array_count++;
    vm->arrays[idx].count = 0;
    vm->arrays[idx].in_use = 1;
    return idx;
}

static void metal_rv64_array_push(MetalRV64VM* vm, int arr_idx, MetalValue val) {
    if (vm == NULL) return;
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return;
    MetalArray* a = &vm->arrays[arr_idx];
    if (a->count < 0 || a->count >= METAL_ARRAY_MAX_ELEMS) return;
    a->elems[a->count++] = val;
}

static MetalValue metal_rv64_array_get(MetalRV64VM* vm, int arr_idx, int index) {
    if (vm == NULL) return mv_nil();
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return mv_nil();
    MetalArray* a = &vm->arrays[arr_idx];
    if (a->count < 0 || a->count > METAL_ARRAY_MAX_ELEMS ||
        index < 0 || index >= a->count) return mv_nil();
    return a->elems[index];
}

static int metal_rv64_array_len(MetalRV64VM* vm, int arr_idx) {
    if (vm == NULL) return 0;
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max || vm->arrays[arr_idx].count < 0) return 0;
    return vm->arrays[arr_idx].count;
}

static int metal_rv64_dict_new(MetalRV64VM* vm) {
    if (vm == NULL) return -1;
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (vm->dict_count < 0 || vm->dict_count >= max) return -1;
    int idx = vm->dict_count++;
    vm->dicts[idx].count = 0;
    vm->dicts[idx].in_use = 1;
    return idx;
}

static void metal_rv64_dict_set(MetalRV64VM* vm, int dict_idx, int key_str_idx, MetalValue val) {
    if (vm == NULL) return;
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (dict_idx < 0 || dict_idx >= max) return;
    MetalDict* d = &vm->dicts[dict_idx];
    if (d->count < 0 || d->count > METAL_DICT_MAX_ENTRIES) return;
    for (int i = 0; i < d->count; i++) {
        if (d->key_str_idx[i] == key_str_idx) {
            d->values[i] = val;
            return;
        }
    }
    if (d->count < METAL_DICT_MAX_ENTRIES) {
        d->key_str_idx[d->count] = key_str_idx;
        d->values[d->count] = val;
        d->count++;
    }
}

static MetalValue metal_rv64_dict_get(MetalRV64VM* vm, int dict_idx, int key_str_idx) {
    if (vm == NULL) return mv_nil();
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (dict_idx < 0 || dict_idx >= max) return mv_nil();
    MetalDict* d = &vm->dicts[dict_idx];
    if (d->count < 0 || d->count > METAL_DICT_MAX_ENTRIES) return mv_nil();
    for (int i = 0; i < d->count; i++) {
        if (d->key_str_idx[i] == key_str_idx) return d->values[i];
    }
    return mv_nil();
}

static void metal_rv64_print_value(MetalRV64VM* vm, MetalValue value) {
    if (vm == NULL) return;
    switch (value.type) {
        case MV_NUM:
            metal_rv64_print_double(vm, value.as.number);
            break;
        case MV_BOOL:
            metal_rv64_print_str(vm, value.as.boolean ? "true" : "false");
            break;
        case MV_STR:
            metal_rv64_print_str(vm, metal_rv64_string_get(vm, value.as.str_idx));
            break;
        case MV_ARR: {
            metal_rv64_print_str(vm, "[");
            int len = metal_rv64_array_len(vm, value.as.arr_idx);
            for (int i = 0; i < len; i++) {
                if (i > 0) metal_rv64_print_str(vm, ", ");
                metal_rv64_print_value(vm, metal_rv64_array_get(vm, value.as.arr_idx, i));
            }
            metal_rv64_print_str(vm, "]");
            break;
        }
        case MV_PTR:
            metal_rv64_print_str(vm, "<ptr>");
            break;
        case MV_NIL:
        default:
            metal_rv64_print_str(vm, "nil");
            break;
    }
}

// ============================================================================
// Public API Implementation
// ============================================================================

void metal_rv64_vm_init(MetalRV64VM* vm) {
    if (vm == NULL) return;
    memset(vm, 0, sizeof(MetalRV64VM));
    vm->global_dict_idx = metal_rv64_dict_new(vm);
}

int metal_rv64_vm_load_binary(MetalRV64VM* vm, const unsigned char* data, int size) {
    if (vm == NULL || data == NULL || size < 14) {
        if (vm != NULL) (void)metal_rv64_fail(vm, "SGRV binary is truncated");
        return -1;
    }
    void (*write_char)(char) = vm->write_char;
    int (*read_char)(void) = vm->read_char;
    int trace = vm->trace;
    metal_rv64_vm_init(vm);
    vm->write_char = write_char;
    vm->read_char = read_char;
    vm->trace = trace;
    int pos = 0;

    // Magic: SGRV
    if (data[pos++] != 'S' || data[pos++] != 'G' || data[pos++] != 'R' || data[pos++] != 'V') {
        (void)metal_rv64_fail(vm, "Invalid SGRV magic");
        return -2;
    }

    // Version: 2 bytes (expecting 0x00 0x01)
    if (data[pos++] != 0x00 || data[pos++] != 0x01) {
        (void)metal_rv64_fail(vm, "Invalid SGRV version");
        return -3;
    }

    int function_count = 0;
    int const_count = 0;
    if (!metal_rv64_read_u16(data, size, &pos, &function_count) ||
        !metal_rv64_read_u16(data, size, &pos, &const_count) ||
        function_count > 256 || const_count > METAL_CONST_POOL) {
        (void)metal_rv64_fail(vm, "Invalid SGRV table count");
        return -4;
    }
    vm->fn_count = function_count;

    for (int i = 0; i < const_count; i++) {
        if (pos >= size) {
            (void)metal_rv64_fail(vm, "Truncated SGRV constant pool");
            return -5;
        }
        unsigned char type = data[pos++];
        if (type == 1) {
            if (pos > size - 8) {
                (void)metal_rv64_fail(vm, "Truncated SGRV number constant");
                return -5;
            }
             union { double d; unsigned char b[8]; } u;
             for (int j = 0; j < 8; j++) u.b[7 - j] = data[pos + j];
            vm->constants[vm->const_count++] = mv_num(u.d);
            pos += 8;
        } else if (type == 3) {
            int len = 0;
            if (!metal_rv64_read_u16(data, size, &pos, &len) || pos > size - len) {
                (void)metal_rv64_fail(vm, "Truncated SGRV string constant");
                return -5;
            }
            int str_idx = metal_rv64_intern_checked(vm, (const char*)&data[pos], len);
            if (str_idx < 0) {
                (void)metal_rv64_fail(vm, "SGRV string pool overflow");
                return -6;
            }
            vm->constants[vm->const_count++] = (MetalValue){MV_STR, {.str_idx = str_idx}};
            pos += len;
        } else {
            (void)metal_rv64_fail(vm, "Invalid SGRV constant type");
            return -7;
        }
    }

    unsigned int chunk_count = 0;
    if (!metal_rv64_read_u32(data, size, &pos, &chunk_count) ||
        chunk_count > RV64_MAX_CHUNKS || function_count > (int)chunk_count) {
        (void)metal_rv64_fail(vm, "Invalid SGRV chunk count");
        return -8;
    }

    for (unsigned int i = 0; i < chunk_count; i++) {
        unsigned int code_length = 0;
        if (!metal_rv64_read_u32(data, size, &pos, &code_length) ||
            code_length > (unsigned int)RV64_MAX_CHUNK_BYTES ||
            (code_length % 4) != 0 ||
            code_length > (unsigned int)(size - pos)) {
            (void)metal_rv64_fail(vm, "Invalid SGRV chunk length");
            return -9;
        }
        vm->chunks[vm->chunk_count] = &data[pos];
        vm->chunk_lengths[vm->chunk_count] = (int)code_length;
        vm->chunk_count++;
        pos += (int)code_length;
    }
    if (pos != size || metal_rv64_vm_verify(vm) < 0) {
        (void)metal_rv64_fail(vm, "Invalid SGRV chunk payload");
        return -10;
    }
    vm->current_chunk_idx = chunk_count > 0 ? 0 : -1;
    vm->bytecode = chunk_count > 0 ? vm->chunks[0] : NULL;
    vm->bytecode_length = chunk_count > 0 ? vm->chunk_lengths[0] : 0;
    vm->pc = 0;
    vm->verified = 1;
    return 0;
}

RV64Instruction rv64_decode(unsigned int raw) {
    RV64Instruction inst;
    inst.opcode = raw & 0x7F;
    inst.rd = (raw >> 7) & 0x1F;
    inst.funct3 = (raw >> 12) & 0x07;
    inst.rs1 = (raw >> 15) & 0x1F;
    inst.rs2 = (raw >> 20) & 0x1F;
    inst.funct7 = (raw >> 25) & 0x7F;

    // Immediate decoding
    // I-type
    int imm_i_raw = (raw >> 20) & 0xFFF;
    inst.imm_i = (imm_i_raw & 0x800) ? (imm_i_raw | ~0xFFF) : imm_i_raw;

    // S-type
    int imm_s_raw = ((raw >> 7) & 0x1F) | (((raw >> 25) & 0x7F) << 5);
    inst.imm_s = (imm_s_raw & 0x800) ? (imm_s_raw | ~0xFFF) : imm_s_raw;

    // B-type
    int imm_b_raw = (((raw >> 7) & 0x01) << 11) |
                    (((raw >> 8) & 0x0F) << 1) |
                    (((raw >> 25) & 0x3F) << 5) |
                    (((raw >> 31) & 0x01) << 12);
    inst.imm_b = (imm_b_raw & 0x1000) ? (imm_b_raw | ~0x1FFF) : imm_b_raw;

    // U-type
    inst.imm_u = raw & 0xFFFFF000;

    // J-type
    int imm_j_raw = (((raw >> 12) & 0xFF) << 12) |
                    (((raw >> 20) & 0x01) << 11) |
                    (((raw >> 21) & 0x3FF) << 1) |
                    (((raw >> 31) & 0x01) << 20);
    inst.imm_j = (imm_j_raw & 0x100000) ? (imm_j_raw | ~0x1FFFFF) : imm_j_raw;

    return inst;
}

static int metal_rv64_target_valid(int pc, int length, int offset) {
    long target = (long)pc + offset;
    return target >= 0 && target < length && (target % 4) == 0;
}

int metal_rv64_vm_verify(MetalRV64VM* vm) {
    if (vm == NULL || vm->chunk_count < 0 || vm->chunk_count > RV64_MAX_CHUNKS ||
        vm->const_count < 0 || vm->const_count > METAL_CONST_POOL ||
        vm->fn_count < 0 || vm->fn_count > 256 ||
        vm->global_dict_idx < 0 || vm->global_dict_idx >= vm->dict_count) {
        return -1;
    }
    for (int c = 0; c < vm->chunk_count; c++) {
        int length = vm->chunk_lengths[c];
        if (length < 0 || length > RV64_MAX_CHUNK_BYTES ||
            (length % 4) != 0 || (length > 0 && vm->chunks[c] == NULL)) {
            return -2;
        }
        for (int pc = 0; pc < length; pc += 4) {
            const unsigned char* code = vm->chunks[c];
            unsigned int raw = (unsigned int)code[pc] |
                               ((unsigned int)code[pc + 1] << 8) |
                               ((unsigned int)code[pc + 2] << 16) |
                               ((unsigned int)code[pc + 3] << 24);
            RV64Instruction inst = rv64_decode(raw);
            switch (inst.opcode) {
                 case RV_OP_LUI:
                 case RV_OP_AUIPC:
                     break;
                 case RV_OP_JAL:
                     if (!metal_rv64_target_valid(pc, length, inst.imm_j)) return -3;
                     break;
                case RV_OP_JALR:
                    if (inst.funct3 != 0) return -3;
                    break;
                case RV_OP_BRANCH:
                    if (inst.funct3 != RV_F3_BEQ && inst.funct3 != RV_F3_BNE &&
                        inst.funct3 != RV_F3_BLT && inst.funct3 != RV_F3_BGE &&
                        inst.funct3 != RV_F3_BLTU && inst.funct3 != RV_F3_BGEU) return -3;
                    if (!metal_rv64_target_valid(pc, length, inst.imm_b)) return -3;
                    break;
                case RV_OP_LOAD:
                    if (inst.funct3 > RV_F3_LD) return -3;
                    break;
                case RV_OP_STORE:
                    if (inst.funct3 > RV_F3_SD) return -3;
                    break;
                 case RV_OP_IMM:
                     if (inst.funct3 == RV_F3_SLL) {
                         if (inst.funct7 != 0) return -3;
                     } else if (inst.funct3 == RV_F3_SRL) {
                         if (inst.funct7 != 0 && inst.funct7 != 0x20) return -3;
                     }
                     break;
                 case RV_OP_REG:
                     if (inst.funct7 == 0x01) {
                         if (inst.funct3 != RV_F3_ADD && inst.funct3 != RV_F3_XOR &&
                             inst.funct3 != RV_F3_OR && inst.funct3 != RV_F3_AND) return -3;
                     } else if (inst.funct7 == 0x20) {
                         if (inst.funct3 != RV_F3_ADD && inst.funct3 != RV_F3_SRL) return -3;
                     } else if (inst.funct7 != 0) return -3;
                     break;
                 case RV_OP_LDC: {
                     unsigned int index = ((unsigned int)inst.imm_u >> 12) & 0xFFFFFu;
                    if (index >= (unsigned int)vm->const_count) return -4;
                    break;
                }
                 case RV_OP_VMSYS:
                     if (inst.funct3 > RV_F3_OBJ_OPS) return -3;
                     if (inst.funct3 == RV_F3_VM_OPS) {
                         if (inst.rs1 > RV_VMO_TRUTHY) return -3;
                         if (inst.rs1 == RV_VMO_CMP_BINARY) {
                             if (inst.funct7 > RV_CMP_GE) return -3;
                         } else if (inst.rs1 != RV_VMO_SETUP_TRY && inst.funct7 != 0) {
                             return -3;
                         }
                     } else if (inst.funct3 == RV_F3_OBJ_OPS) {
                         if (inst.rs1 > RV_OBJ_SLICE || inst.funct7 != 0) return -3;
                     }
                     break;
                default:
                    return -3;
            }
        }
    }
    return 0;
}

static int metal_rv64_number_index(const MetalRV64VM* vm, MetalValue value, int* index) {
    if (vm == NULL || index == NULL || value.type != MV_NUM) return 0;
    double number = (double)value.as.number;
    if (!(number >= -2147483648.0 && number <= 2147483647.0)) return 0;
    long long result = (long long)number;
    if (result < -2147483648LL || result > 2147483647LL) return 0;
    *index = (int)result;
    return 1;
}

static int metal_rv64_unsigned_index(double value, unsigned long long* result) {
    if (result == NULL || !(value >= 0.0) || !(value < 18446744073709551616.0)) return 0;
    *result = (unsigned long long)value;
    return 1;
}

static int metal_rv64_truthy(MetalValue value) {
    if (value.type == MV_NIL) return 0;
    if (value.type == MV_BOOL) return value.as.boolean != 0;
    if (value.type == MV_NUM) return value.as.number != 0.0;
    return 1;
}

static int metal_rv64_compare(const MetalRV64VM* vm, MetalValue left, MetalValue right, int comparison) {
    if (left.type == MV_NUM && right.type == MV_NUM) {
        switch (comparison) {
            case RV_CMP_EQ: return left.as.number == right.as.number;
            case RV_CMP_NEQ: return left.as.number != right.as.number;
            case RV_CMP_LT: return left.as.number < right.as.number;
            case RV_CMP_GT: return left.as.number > right.as.number;
            case RV_CMP_LE: return left.as.number <= right.as.number;
            case RV_CMP_GE: return left.as.number >= right.as.number;
            default: return 0;
        }
    }
    if (left.type == MV_STR && right.type == MV_STR) {
        int order = metal_rv64_string_compare(metal_rv64_string_get(vm, left.as.str_idx),
                                               metal_rv64_string_get(vm, right.as.str_idx));
        switch (comparison) {
            case RV_CMP_EQ: return order == 0;
            case RV_CMP_NEQ: return order != 0;
            case RV_CMP_LT: return order < 0;
            case RV_CMP_GT: return order > 0;
            case RV_CMP_LE: return order <= 0;
            case RV_CMP_GE: return order >= 0;
            default: return 0;
        }
    }
    if ((left.type == MV_BOOL && right.type == MV_NUM) ||
        (left.type == MV_NUM && right.type == MV_BOOL)) {
        int a = left.type == MV_BOOL ? left.as.boolean != 0 : left.as.number != 0.0;
        int b = right.type == MV_BOOL ? right.as.boolean != 0 : right.as.number != 0.0;
        switch (comparison) {
            case RV_CMP_EQ: return a == b;
            case RV_CMP_NEQ: return a != b;
            case RV_CMP_LT: return a < b;
            case RV_CMP_GT: return a > b;
            case RV_CMP_LE: return a <= b;
            case RV_CMP_GE: return a >= b;
            default: return 0;
        }
    }
    if (comparison == RV_CMP_EQ) return left.type == right.type;
    if (comparison == RV_CMP_NEQ) return left.type != right.type;
    return 0;
}

// ============================================================================
// Execution Handlers
// ============================================================================

static void handle_branch(MetalRV64VM* vm, RV64Instruction inst) {
    MetalValue rs1_val = vm->x[inst.rs1];
    MetalValue rs2_val = vm->x[inst.rs2];
    int take = 0;

    // We do simple float/boolean comparisons based on type
    if (rs1_val.type == MV_NUM && rs2_val.type == MV_NUM) {
        double a = rs1_val.as.number;
        double b = rs2_val.as.number;
        switch (inst.funct3) {
            case RV_F3_BEQ: take = (a == b); break;
            case RV_F3_BNE: take = (a != b); break;
            case RV_F3_BLT: take = (a < b); break;
            case RV_F3_BGE: take = (a >= b); break;
            case RV_F3_BLTU: {
                unsigned long long ua = 0, ub = 0;
                take = metal_rv64_unsigned_index(a, &ua) &&
                       metal_rv64_unsigned_index(b, &ub) && ua < ub;
                break;
            }
            case RV_F3_BGEU: {
                unsigned long long ua = 0, ub = 0;
                int valid_a = metal_rv64_unsigned_index(a, &ua);
                int valid_b = metal_rv64_unsigned_index(b, &ub);
                take = valid_a && valid_b ? ua >= ub : !valid_a && valid_b;
                break;
            }
        }
    } else if (rs1_val.type == MV_STR && rs2_val.type == MV_STR) {
        const char* a = metal_rv64_string_get(vm, rs1_val.as.str_idx);
        const char* b = metal_rv64_string_get(vm, rs2_val.as.str_idx);
        int cmp = metal_rv64_string_compare(a, b);
        switch (inst.funct3) {
            case RV_F3_BEQ: take = (cmp == 0); break;
            case RV_F3_BNE: take = (cmp != 0); break;
            case RV_F3_BLT: take = (cmp < 0); break;
            case RV_F3_BGE: take = (cmp >= 0); break;
        }
    } else if ((rs1_val.type == MV_BOOL && rs2_val.type == MV_NUM) ||
               (rs1_val.type == MV_NUM && rs2_val.type == MV_BOOL)) {
        int a = rs1_val.type == MV_BOOL ? rs1_val.as.boolean != 0 : rs1_val.as.number != 0.0;
        int b = rs2_val.type == MV_BOOL ? rs2_val.as.boolean != 0 : rs2_val.as.number != 0.0;
        switch (inst.funct3) {
            case RV_F3_BEQ: take = (a == b); break;
            case RV_F3_BNE: take = (a != b); break;
            case RV_F3_BLT: take = (a < b); break;
            case RV_F3_BGE: take = (a >= b); break;
        }
    } else if (rs1_val.type == MV_BOOL && rs2_val.type == MV_BOOL) {
        int a = rs1_val.as.boolean;
        int b = rs2_val.as.boolean;
        switch (inst.funct3) {
            case RV_F3_BEQ: take = (a == b); break;
            case RV_F3_BNE: take = (a != b); break;
        }
    } else if (rs1_val.type == MV_NIL && rs2_val.type == MV_NIL) {
        switch (inst.funct3) {
            case RV_F3_BEQ: take = 1; break;
            case RV_F3_BNE: take = 0; break;
        }
    } else {
        // Mismatched or other types: only BEQ/BNE valid
        switch (inst.funct3) {
            case RV_F3_BEQ: take = 0; break;
            case RV_F3_BNE: take = 1; break;
        }
    }

    if (take) {
        long target = (long)vm->pc + inst.imm_b;
        if (target < 0 || target >= vm->bytecode_length ||
            (target % 4) != 0) {
            (void)metal_rv64_fail(vm, "RISC-V branch target out of bounds");
            return;
        }
        vm->pc = (int)target;
    } else {
        vm->pc += 4;
    }
}

static void handle_imm(MetalRV64VM* vm, RV64Instruction inst) {
    MetalValue rs1_val = vm->x[inst.rs1];
    int imm = inst.imm_i;
    double val = (rs1_val.type == MV_NUM) ? rs1_val.as.number : 0.0;

    switch (inst.funct3) {
        case RV_F3_ADD: // ADDI
            if (imm == 0) {
                vm->x[inst.rd] = rs1_val;
            } else {
                vm->x[inst.rd] = mv_num(val + imm);
            }
            break;
        case RV_F3_SLT: // SLTI
            vm->x[inst.rd] = mv_bool(val < imm);
            break;
        case RV_F3_XOR: // XORI
            if (imm == 0) {
                vm->x[inst.rd] = rs1_val;
            } else {
                vm->x[inst.rd] = mv_num((double)((long long)val ^ imm));
            }
            break;
        case RV_F3_OR: // ORI
            if (imm == 0) {
                vm->x[inst.rd] = rs1_val;
            } else {
                vm->x[inst.rd] = mv_num((double)((long long)val | imm));
            }
            break;
        case RV_F3_AND: // ANDI
            if (imm == -1) {
                vm->x[inst.rd] = rs1_val;
            } else {
                vm->x[inst.rd] = mv_num((double)((long long)val & imm));
            }
            break;
        case RV_F3_SLL: // SLLI
            vm->x[inst.rd] = mv_num((double)((long long)val << (imm & 0x3F)));
            break;
        case RV_F3_SRL: // SRLI / SRAI
            if (inst.funct7 == 0x20) {
                // SRAI
                vm->x[inst.rd] = mv_num((double)((long long)val >> (imm & 0x3F)));
            } else {
                // SRLI
                vm->x[inst.rd] = mv_num((double)((unsigned long long)val >> (imm & 0x3F)));
            }
            break;
        default:
            vm->x[inst.rd] = mv_nil();
            break;
    }
    vm->pc += 4;
}

static void handle_reg(MetalRV64VM* vm, RV64Instruction inst) {
    MetalValue rs1_val = vm->x[inst.rs1];
    MetalValue rs2_val = vm->x[inst.rs2];
    double v1 = (rs1_val.type == MV_NUM) ? rs1_val.as.number : 0.0;
    double v2 = (rs2_val.type == MV_NUM) ? rs2_val.as.number : 0.0;

    if (inst.funct7 == 0x01) { // RV64M Extension (Mul/Div/Rem)
        switch (inst.funct3) {
            case RV_F3_ADD: // MUL
                vm->x[inst.rd] = mv_num(v1 * v2);
                break;
            case RV_F3_XOR: // DIV
                if (v2 != 0.0) vm->x[inst.rd] = mv_num((double)((long long)v1 / (long long)v2));
                else { vm->x[inst.rd] = mv_num(0); vm->error = 1; vm->error_msg = "division by zero"; }
                break;
            case RV_F3_OR: // REM
                if (v2 != 0.0) vm->x[inst.rd] = mv_num((double)((long long)v1 % (long long)v2));
                else { vm->x[inst.rd] = mv_num(0); vm->error = 1; vm->error_msg = "modulo by zero"; }
                break;
            default:
                vm->x[inst.rd] = mv_nil();
                break;
        }
        vm->pc += 4;
        return;
    }

    switch (inst.funct3) {
        case RV_F3_ADD:
            if (inst.funct7 == 0x20) { // SUB
                if (inst.rs2 == 0) {
                    vm->x[inst.rd] = rs1_val;
                } else {
                    vm->x[inst.rd] = mv_num(v1 - v2);
                }
            } else { // ADD
                if (inst.rs2 == 0) {
                    vm->x[inst.rd] = rs1_val;
                } else if (inst.rs1 == 0) {
                    vm->x[inst.rd] = rs2_val;
                } else if (rs1_val.type == MV_STR && rs2_val.type == MV_STR) {
                     const char* s1 = metal_rv64_string_get(vm, rs1_val.as.str_idx);
                     const char* s2 = metal_rv64_string_get(vm, rs2_val.as.str_idx);
                     int len1 = metal_rv64_bounded_strlen(s1, METAL_STRING_POOL);
                     int len2 = metal_rv64_bounded_strlen(s2, METAL_STRING_POOL);
                     char concat_buf[1024];
                     if (len1 < 0 || len2 < 0 || len1 > 1024 || len2 > 1024 - len1) {
                         (void)metal_rv64_fail(vm, "String concatenation buffer overflow");
                         vm->x[inst.rd] = mv_nil();
                     } else {
                         memcpy(concat_buf, s1, len1);
                         memcpy(concat_buf + len1, s2, len2);
                         int new_idx = metal_rv64_intern_checked(vm, concat_buf, len1 + len2);
                         if (new_idx < 0) {
                             (void)metal_rv64_fail(vm, "SGRV string pool overflow");
                             vm->x[inst.rd] = mv_nil();
                         } else {
                             vm->x[inst.rd] = (MetalValue){MV_STR, {.str_idx = new_idx}};
                         }
                     }
                } else {
                    vm->x[inst.rd] = mv_num(v1 + v2);
                }
            }
            break;
        case RV_F3_SLL:
            vm->x[inst.rd] = mv_num((double)((long long)v1 << ((int)v2 & 0x3F)));
            break;
        case RV_F3_SLT:
            if (rs1_val.type == MV_STR && rs2_val.type == MV_STR) {
                const char* a = metal_rv64_string_get(vm, rs1_val.as.str_idx);
                const char* b = metal_rv64_string_get(vm, rs2_val.as.str_idx);
                vm->x[inst.rd] = mv_bool(metal_rv64_string_compare(a, b) < 0);
            } else {
                vm->x[inst.rd] = mv_bool(v1 < v2);
            }
            break;
        case RV_F3_XOR:
            vm->x[inst.rd] = mv_num((double)((long long)v1 ^ (long long)v2));
            break;
        case RV_F3_SRL:
            if (inst.funct7 == 0x20) { // SRA
                vm->x[inst.rd] = mv_num((double)((long long)v1 >> ((int)v2 & 0x3F)));
            } else { // SRL
                vm->x[inst.rd] = mv_num((double)((unsigned long long)v1 >> ((int)v2 & 0x3F)));
            }
            break;
        case RV_F3_OR:
            vm->x[inst.rd] = mv_num((double)((long long)v1 | (long long)v2));
            break;
        case RV_F3_AND:
            vm->x[inst.rd] = mv_num((double)((long long)v1 & (long long)v2));
            break;
        default:
            vm->x[inst.rd] = mv_nil();
            break;
    }
    vm->pc += 4;
}

static void handle_ldc(MetalRV64VM* vm, RV64Instruction inst) {
    int idx = (int)(((unsigned int)inst.imm_u >> 12) & 0xFFFFFu);
    if (idx >= 0 && idx < vm->const_count) {
        vm->x[inst.rd] = vm->constants[idx];
    } else {
        vm->error = 1;
        vm->error_msg = "Constant pool access violation";
        vm->x[inst.rd] = mv_nil();
    }
    vm->pc += 4;
}

static void handle_load(MetalRV64VM* vm, RV64Instruction inst) {
    int base = 0;
    if (!metal_rv64_number_index(vm, vm->x[inst.rs1], &base)) {
        vm->x[inst.rd] = mv_nil();
        (void)metal_rv64_fail(vm, "Load address is not a valid number");
        return;
    }
    long address = (long)base + inst.imm_i;
    if (address >= 0 && address < RV64_STACK_SIZE) {
        vm->x[inst.rd] = vm->stack[address];
    } else {
        vm->x[inst.rd] = mv_nil();
        (void)metal_rv64_fail(vm, "Load access violation");
        return;
    }
    vm->pc += 4;
}

static void handle_store(MetalRV64VM* vm, RV64Instruction inst) {
    int base = 0;
    if (!metal_rv64_number_index(vm, vm->x[inst.rs1], &base)) {
        (void)metal_rv64_fail(vm, "Store address is not a valid number");
        return;
    }
    long address = (long)base + inst.imm_s;
    MetalValue val = vm->x[inst.rs2];
    if (address >= 0 && address < RV64_STACK_SIZE) {
        vm->stack[address] = val;
    } else {
        (void)metal_rv64_fail(vm, "Store access violation");
        return;
    }
    vm->pc += 4;
}

static int metal_rv64_name_index(const MetalRV64VM* vm, MetalValue value, int* string_index) {
    int index = -1;
    if (!metal_rv64_number_index(vm, value, &index) || string_index == NULL ||
        index < 0 || index >= vm->const_count ||
        vm->constants[index].type != MV_STR ||
        vm->constants[index].as.str_idx < 0 ||
        vm->constants[index].as.str_idx >= vm->string_used) {
        return 0;
    }
    *string_index = vm->constants[index].as.str_idx;
    return 1;
}

static void handle_vmsys(MetalRV64VM* vm, RV64Instruction inst) {
    int sub_op = inst.rs1;

    if (inst.funct3 == RV_F3_VM_OPS) {
        switch (sub_op) {
            case RV_VMO_HALT:
                vm->running = 0;
                vm->halted = 1;
                break;
             case RV_VMO_PRINT:
             case RV_VMO_PRINTM:
                 metal_rv64_print_value(vm, vm->x[10]);
                 if (vm->write_char) vm->write_char('\n');
                 break;
             case RV_VMO_CMP_BINARY:
                 if (inst.funct7 > RV_CMP_GE) {
                     (void)metal_rv64_fail(vm, "SGRV comparison operation is invalid");
                     return;
                 }
                 vm->x[10] = mv_bool(metal_rv64_compare(vm, vm->x[10], vm->x[11], inst.funct7));
                 break;
             case RV_VMO_NIL:
                 vm->x[inst.rd] = mv_nil();
                 break;
             case RV_VMO_TRUE:
                 vm->x[inst.rd] = mv_bool(1);
                 break;
             case RV_VMO_FALSE:
                 vm->x[inst.rd] = mv_bool(0);
                 break;
             case RV_VMO_NOT:
                 vm->x[inst.rd] = mv_bool(!metal_rv64_truthy(vm->x[10]));
                 break;
             case RV_VMO_TRUTHY:
                 vm->x[inst.rd] = mv_bool(metal_rv64_truthy(vm->x[10]));
                 break;
             case RV_VMO_NOP:
             case RV_VMO_IMPORT:
             case RV_VMO_EXEC_AST:
                 break;
            case RV_VMO_PUSH_ENV: {
                break;
            }
            case RV_VMO_POP_ENV:
                break;
            case RV_VMO_CALL: {
                MetalValue func_obj = vm->x[inst.rs2];
                int target_chunk = -1;
                 if (func_obj.type == MV_NUM) {
                     (void)metal_rv64_number_index(vm, func_obj, &target_chunk);
                 } else if (func_obj.type == MV_DICT &&
                            func_obj.as.dict_idx >= 0 &&
                            func_obj.as.dict_idx < vm->dict_count) {
                    // Check if class constructor call
                    MetalValue type_val = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_intern_checked(vm, "__type__", 8));
                    if (type_val.type == MV_STR && metal_rv64_string_compare(metal_rv64_string_get(vm, type_val.as.str_idx), "class") == 0) {
                         int inst_dict = metal_rv64_dict_new(vm);
                         if (inst_dict < 0) {
                             (void)metal_rv64_fail(vm, "SGRV dictionary pool overflow");
                             return;
                         }
                         metal_rv64_dict_set(vm, inst_dict, metal_rv64_intern_checked(vm, "__type__", 8), (MetalValue){MV_STR, {.str_idx = metal_rv64_intern_checked(vm, "instance", 8)}});
                        metal_rv64_dict_set(vm, inst_dict, metal_rv64_intern_checked(vm, "__class__", 9), func_obj);

                        MetalValue methods_val = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_intern_checked(vm, "__methods__", 11));
                        MetalValue init_func = mv_nil();
                        if (methods_val.type == MV_DICT) {
                            init_func = metal_rv64_dict_get(vm, methods_val.as.dict_idx, metal_rv64_intern_checked(vm, "init", 4));
                        }

                        if (init_func.type == MV_DICT) {
                            MetalValue chunk_idx_val = metal_rv64_dict_get(vm, init_func.as.dict_idx, metal_rv64_intern_checked(vm, "chunk_idx", 9));
                             if (chunk_idx_val.type == MV_NUM) {
                                 (void)metal_rv64_number_index(vm, chunk_idx_val, &target_chunk);
                             }

                             if (target_chunk >= 0 && target_chunk < vm->chunk_count) {
                                 if (vm->csp < 0 || vm->csp >= RV64_CALL_STACK_SIZE) {
                                     (void)metal_rv64_fail(vm, "Call stack overflow");
                                     return;
                                 }
                                 vm->call_stack[vm->csp].chunk_idx = vm->current_chunk_idx;
                                 vm->call_stack[vm->csp].return_pc = vm->pc + 4;
                                 vm->call_stack[vm->csp].saved_ra = vm->x[1];
                                 vm->call_stack[vm->csp].is_constructor = 1;
                                 vm->call_stack[vm->csp].constructor_instance = (MetalValue){MV_DICT, {.dict_idx = inst_dict}};
                                 vm->csp++;

                                 for (int r = 17; r > 10; r--) {
                                     vm->x[r] = vm->x[r - 1];
                                 }
                                 vm->x[10] = (MetalValue){MV_DICT, {.dict_idx = inst_dict}};

                                 vm->current_chunk_idx = target_chunk;
                                 vm->bytecode = vm->chunks[target_chunk];
                                 vm->bytecode_length = vm->chunk_lengths[target_chunk];
                                 vm->pc = 0;
                                 vm->x[1] = mv_num(0);
                                 return;
                             } else {
                                 vm->error = 1;
                                 vm->error_msg = "Invalid constructor chunk index";
                             }
                        } else {
                            // No init method, just return the instance directly
                            vm->x[10] = (MetalValue){MV_DICT, {.dict_idx = inst_dict}};
                            vm->pc += 4;
                        }
                        return;
                    }

                    // Check if __builtin__
                    MetalValue builtin = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_intern_checked(vm, "__builtin__", 11));
                    if (builtin.type == MV_STR) {
                        const char* b_name = metal_rv64_string_get(vm, builtin.as.str_idx);
                        if (metal_rv64_string_compare(b_name, "str") == 0) {
                            int str_idx = metal_rv64_intern_checked(vm, "", 0); // fallback
                            if (vm->x[10].type == MV_NUM) {
                                double d = vm->x[10].as.number;
                                if (d >= -1e15 && d <= 1e15 && d == (double)(long long)d) {
                                    long long integer = (long long)d;
                                    int len = 0;
                                    char rev[24];
                                    int is_neg = 0;
                                    if (integer < 0) { is_neg = 1; integer = -integer; }
                                    if (integer == 0) rev[len++] = '0';
                                    else {
                                        while (integer > 0) { rev[len++] = '0' + (int)(integer % 10); integer /= 10; }
                                    }
                                    char fin[32];
                                    int pos = 0;
                                    if (is_neg) fin[pos++] = '-';
                                    while (--len >= 0) fin[pos++] = rev[len];
                                    str_idx = metal_rv64_intern_checked(vm, fin, pos);
                                } else {
                                    str_idx = metal_rv64_intern_checked(vm, "<float>", 7);
                                }
                            } else if (vm->x[10].type == MV_BOOL) {
                                str_idx = metal_rv64_intern_checked(vm, vm->x[10].as.boolean ? "true" : "false", vm->x[10].as.boolean ? 4 : 5);
                            }
                            vm->x[10] = (MetalValue){MV_STR, {.str_idx = str_idx}};
                        } else if (metal_rv64_string_compare(b_name, "int") == 0) {
                            if (vm->x[10].type == MV_NUM) {
                                vm->x[10] = mv_num((double)(long long)vm->x[10].as.number);
                            }
                        }
                        vm->pc += 4;
                        return;
                    }
                    MetalValue chunk_idx_val = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_intern_checked(vm, "chunk_idx", 9));
                     if (chunk_idx_val.type == MV_NUM) {
                         (void)metal_rv64_number_index(vm, chunk_idx_val, &target_chunk);
                     }
                }

                 if (target_chunk >= 0 && target_chunk < vm->chunk_count) {
                     if (vm->csp < 0 || vm->csp >= RV64_CALL_STACK_SIZE) {
                         (void)metal_rv64_fail(vm, "Call stack overflow");
                         return;
                     }
                     vm->call_stack[vm->csp].chunk_idx = vm->current_chunk_idx;
                     vm->call_stack[vm->csp].return_pc = vm->pc + 4;
                     vm->call_stack[vm->csp].saved_ra = vm->x[1];
                     vm->call_stack[vm->csp].is_constructor = 0;
                     vm->call_stack[vm->csp].constructor_instance = mv_nil();
                     vm->csp++;

                     vm->current_chunk_idx = target_chunk;
                     vm->bytecode = vm->chunks[target_chunk];
                     vm->bytecode_length = vm->chunk_lengths[target_chunk];
                     vm->pc = 0;
                     vm->x[1] = mv_num(0);
                     return;
                 } else {
                    metal_rv64_print_str(vm, "VMO_CALL error: target_chunk=");
                    metal_rv64_print_int(vm, target_chunk);
                    metal_rv64_print_str(vm, " type=");
                    metal_rv64_print_int(vm, func_obj.type);
                     if (func_obj.type == MV_DICT && func_obj.as.dict_idx >= 0 &&
                         func_obj.as.dict_idx < vm->dict_count) {
                         metal_rv64_print_str(vm, " dict_idx=");
                         metal_rv64_print_int(vm, func_obj.as.dict_idx);
                         // Let's print keys in dict
                         MetalDict* d = &vm->dicts[func_obj.as.dict_idx];
                         if (d->count < 0 || d->count > METAL_DICT_MAX_ENTRIES) {
                             (void)metal_rv64_fail(vm, "SGRV dictionary state is invalid");
                             return;
                         }
                         metal_rv64_print_str(vm, " keys=[");
                         for (int k = 0; k < d->count; k++) {
                            if (k > 0) metal_rv64_print_str(vm, ", ");
                            metal_rv64_print_str(vm, metal_rv64_string_get(vm, d->key_str_idx[k]));
                            metal_rv64_print_str(vm, ":");
                            metal_rv64_print_int(vm, d->values[k].type);
                        }
                        metal_rv64_print_str(vm, "]");
                    }
                    if (vm->write_char) vm->write_char('\n');
                    vm->error = 1;
                    vm->error_msg = "Invalid function call target";
                }
                break;
            }
            case RV_VMO_ARRAY_LEN: {
                MetalValue obj = vm->x[inst.rs2];
                if (obj.type == MV_ARR) {
                    vm->x[inst.rd] = mv_num((double)metal_rv64_array_len(vm, obj.as.arr_idx));
                } else {
                    vm->x[inst.rd] = mv_num(0);
                }
                break;
            }
             case RV_VMO_SETUP_TRY: {
                 int catch_offset = inst.imm_i;
                 long catch_pc = (long)vm->pc + catch_offset;
                  if (catch_pc < 0 || catch_pc >= vm->bytecode_length ||
                      (catch_pc % 4) != 0 || vm->tsp >= RV64_TRY_STACK_SIZE) {
                     (void)metal_rv64_fail(vm, "SGRV exception handler target out of bounds");
                     return;
                 }
                 if (vm->tsp < RV64_TRY_STACK_SIZE) {
                      vm->try_stack[vm->tsp].catch_pc = (int)catch_pc;
                     vm->try_stack[vm->tsp].call_depth = vm->csp;
                     vm->try_stack[vm->tsp].chunk_idx = vm->current_chunk_idx;
                    vm->tsp++;
                }
                break;
            }
            case RV_VMO_END_TRY:
                if (vm->tsp > 0) vm->tsp--;
                break;
             case RV_VMO_RAISE: {
                 MetalValue exc_obj = vm->x[10];
                 if (vm->tsp <= 0 || vm->tsp > RV64_TRY_STACK_SIZE) {
                     (void)metal_rv64_fail(vm, "Unhandled exception raised");
                     return;
                 }
                 vm->tsp--;
                 int catch_pc = vm->try_stack[vm->tsp].catch_pc;
                 int target_depth = vm->try_stack[vm->tsp].call_depth;
                 int handler_chunk = vm->try_stack[vm->tsp].chunk_idx;
                 if (target_depth < 0 || target_depth > vm->csp ||
                     handler_chunk < 0 || handler_chunk >= vm->chunk_count ||
                     catch_pc < 0 || catch_pc > vm->chunk_lengths[handler_chunk] ||
                     (catch_pc % 4) != 0) {
                     (void)metal_rv64_fail(vm, "SGRV exception handler state is invalid");
                     return;
                 }
                 while (vm->csp > target_depth) vm->csp--;
                 vm->current_chunk_idx = handler_chunk;
                 vm->bytecode = vm->chunks[handler_chunk];
                 vm->bytecode_length = vm->chunk_lengths[handler_chunk];
                 vm->pc = catch_pc;
                 vm->x[10] = exc_obj;
                 return;
             }
            default:
                break;
        }
    } else if (inst.funct3 == RV_F3_OBJ_OPS) {
        switch (sub_op) {
             case RV_OBJ_GET_GLOBAL: {
                 int name_str_idx = -1;
                 if (!metal_rv64_name_index(vm, vm->x[10], &name_str_idx)) {
                     (void)metal_rv64_fail(vm, "SGRV global name index out of bounds");
                     return;
                 }
                 const char* name = metal_rv64_string_get(vm, name_str_idx);
                 if (metal_rv64_string_compare(name, "str") == 0) {
                     int d_idx = metal_rv64_dict_new(vm);
                     if (d_idx < 0) {
                         (void)metal_rv64_fail(vm, "SGRV dictionary pool overflow");
                         return;
                     }
                     metal_rv64_dict_set(vm, d_idx, metal_rv64_intern_checked(vm, "__builtin__", 11), (MetalValue){MV_STR, {.str_idx = metal_rv64_intern_checked(vm, "str", 3)}});
                     vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                 } else if (metal_rv64_string_compare(name, "int") == 0) {
                     int d_idx = metal_rv64_dict_new(vm);
                     if (d_idx < 0) {
                         (void)metal_rv64_fail(vm, "SGRV dictionary pool overflow");
                         return;
                     }
                     metal_rv64_dict_set(vm, d_idx, metal_rv64_intern_checked(vm, "__builtin__", 11), (MetalValue){MV_STR, {.str_idx = metal_rv64_intern_checked(vm, "int", 3)}});
                     vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                } else {
                    vm->x[inst.rd] = metal_rv64_dict_get(vm, vm->global_dict_idx, name_str_idx);
                }
                break;
            }
             case RV_OBJ_SET_GLOBAL: {
                 int name_str_idx = -1;
                 if (!metal_rv64_name_index(vm, vm->x[10], &name_str_idx)) {
                     (void)metal_rv64_fail(vm, "SGRV global name index out of bounds");
                     return;
                 }
                 MetalValue val = vm->x[11]; // a1
                metal_rv64_dict_set(vm, vm->global_dict_idx, name_str_idx, val);
                break;
            }
             case RV_OBJ_GET_PROP: {
                 MetalValue obj = vm->x[inst.rs2];
                 int name_str_idx = -1;
                 if (!metal_rv64_name_index(vm, vm->x[10], &name_str_idx)) {
                     (void)metal_rv64_fail(vm, "SGRV property name index out of bounds");
                     return;
                 }
                MetalValue val = mv_nil();
                if (obj.type == MV_DICT) {
                    val = metal_rv64_dict_get(vm, obj.as.dict_idx, name_str_idx);
                }
                if (val.type == MV_NIL) {
                    val = metal_rv64_dict_get(vm, vm->global_dict_idx, name_str_idx);
                }
                vm->x[inst.rd] = val;
                break;
            }
             case RV_OBJ_SET_PROP: {
                 MetalValue obj = vm->x[inst.rs2];
                 int name_str_idx = -1;
                 if (!metal_rv64_name_index(vm, vm->x[10], &name_str_idx)) {
                     (void)metal_rv64_fail(vm, "SGRV property name index out of bounds");
                     return;
                 }
                MetalValue val = vm->x[11];
                if (obj.type == MV_DICT) {
                    metal_rv64_dict_set(vm, obj.as.dict_idx, name_str_idx, val);
                }
                break;
            }
             case RV_OBJ_NEW_FUNC: {
                 int chunk_idx = -1;
                 if (!metal_rv64_number_index(vm, vm->x[10], &chunk_idx) ||
                     chunk_idx < 0 || chunk_idx >= vm->chunk_count) {
                     (void)metal_rv64_fail(vm, "SGRV function chunk index out of bounds");
                     return;
                 }
                 int d_idx = metal_rv64_dict_new(vm);
                 if (d_idx < 0) {
                     (void)metal_rv64_fail(vm, "SGRV dictionary pool overflow");
                     return;
                 }
                metal_rv64_dict_set(vm, d_idx, metal_rv64_intern_checked(vm, "type", 4), (MetalValue){MV_STR, {.str_idx = metal_rv64_intern_checked(vm, "function", 8)}});
                metal_rv64_dict_set(vm, d_idx, metal_rv64_intern_checked(vm, "chunk_idx", 9), mv_num((double)chunk_idx));
                vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                break;
            }
             case RV_OBJ_TUPLE_NEW:
             case RV_OBJ_ARRAY_NEW: {
                 int size = -1;
                 if (!metal_rv64_number_index(vm, vm->x[10], &size) ||
                     size < 0 || size > METAL_ARRAY_MAX_ELEMS) {
                     (void)metal_rv64_fail(vm, "SGRV array size out of bounds");
                     return;
                 }
                 MetalValue init_val = vm->x[11];
                 int arr = metal_rv64_array_new(vm);
                 if (arr < 0) {
                     (void)metal_rv64_fail(vm, "SGRV array pool overflow");
                     return;
                 }
                 for (int i = 0; i < size; i++) {
                    metal_rv64_array_push(vm, arr, init_val);
                }
                vm->x[inst.rd] = (MetalValue){MV_ARR, {.arr_idx = arr}};
                break;
            }
             case RV_OBJ_DICT_NEW: {
                 int d_idx = metal_rv64_dict_new(vm);
                 if (d_idx < 0) {
                     (void)metal_rv64_fail(vm, "SGRV dictionary pool overflow");
                     return;
                 }
                 vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                break;
            }
             case RV_OBJ_GET_INDEX: {
                 MetalValue obj = vm->x[inst.rs2];
                 int idx = 0;
                 if (!metal_rv64_number_index(vm, vm->x[10], &idx)) {
                     vm->x[inst.rd] = mv_nil();
                     break;
                 }
                 if (obj.type == MV_ARR) {
                    vm->x[inst.rd] = metal_rv64_array_get(vm, obj.as.arr_idx, idx);
                } else if (obj.type == MV_DICT && vm->x[10].type == MV_STR) {
                    vm->x[inst.rd] = metal_rv64_dict_get(vm, obj.as.dict_idx, vm->x[10].as.str_idx);
                } else {
                    vm->x[inst.rd] = mv_nil();
                }
                break;
            }
             case RV_OBJ_SET_INDEX: {
                 MetalValue obj = vm->x[inst.rs2];
                 int idx = 0;
                 if (!metal_rv64_number_index(vm, vm->x[10], &idx)) {
                     break;
                 }
                 MetalValue val = vm->x[11];
                if (obj.type == MV_ARR) {
                    int arr_idx = obj.as.arr_idx;
                     int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
                     if (arr_idx >= 0 && arr_idx < max &&
                         vm->arrays[arr_idx].count >= 0 &&
                         vm->arrays[arr_idx].count <= METAL_ARRAY_MAX_ELEMS &&
                         idx >= 0 && idx < vm->arrays[arr_idx].count) {
                        vm->arrays[arr_idx].elems[idx] = val;
                    }
                } else if (obj.type == MV_DICT && vm->x[10].type == MV_STR) {
                    metal_rv64_dict_set(vm, obj.as.dict_idx, vm->x[10].as.str_idx, val);
                }
                break;
            }
            default:
                break;
        }
    } else if (inst.funct3 == RV_F3_GPU_OPS) {
        // Stubs for GPU operations
        if (vm->trace) {
            metal_rv64_print_str(vm, "GPU Op: ");
            metal_rv64_print_int(vm, sub_op);
            if (vm->write_char) vm->write_char('\n');
        }
    }

    vm->pc += 4;
}

// ============================================================================
// Interpreter Step & Run
// ============================================================================

int metal_rv64_vm_step(MetalRV64VM* vm) {
    if (vm == NULL || vm->halted || vm->error) return 0;
    if (vm->chunk_count == 0) return 0;
    if (vm->pc < 0 || vm->bytecode_length < 0 || (vm->bytecode_length % 4) != 0 ||
        vm->current_chunk_idx < 0 || vm->current_chunk_idx >= vm->chunk_count ||
        vm->bytecode != vm->chunks[vm->current_chunk_idx] ||
        vm->bytecode_length != vm->chunk_lengths[vm->current_chunk_idx] ||
        vm->pc >= vm->bytecode_length || vm->pc > vm->bytecode_length - 4 ||
        vm->bytecode == NULL) {
        (void)metal_rv64_fail(vm, "SGRV execution state is invalid");
        return 0;
    }
    if (!vm->verified) {
        if (metal_rv64_vm_verify(vm) < 0) {
            (void)metal_rv64_fail(vm, "SGRV bytecode verification failed");
            return 0;
        }
        vm->verified = 1;
    }

    // Fetch 32-bit instruction (little-endian)
    unsigned int raw = (unsigned int)vm->bytecode[vm->pc] |
                       ((unsigned int)vm->bytecode[vm->pc + 1] << 8) |
                       ((unsigned int)vm->bytecode[vm->pc + 2] << 16) |
                       ((unsigned int)vm->bytecode[vm->pc + 3] << 24);

    RV64Instruction inst = rv64_decode(raw);

    if (vm->trace) {
        metal_rv64_print_str(vm, "PC: ");
        metal_rv64_print_int(vm, vm->pc);
        metal_rv64_print_str(vm, " Opcode: ");
        metal_rv64_print_int(vm, inst.opcode);
        metal_rv64_print_str(vm, " rd: ");
        metal_rv64_print_int(vm, inst.rd);
        metal_rv64_print_str(vm, " raw: ");
        for (int b = 0; b < 4; b++) {
            metal_rv64_print_int(vm, vm->bytecode[vm->pc + b]);
            metal_rv64_print_str(vm, " ");
        }
        if (vm->write_char) vm->write_char('\n');
    }

    switch (inst.opcode) {
        case RV_OP_LUI:
            vm->x[inst.rd] = mv_num((double)inst.imm_u);
            vm->pc += 4;
            break;
        case RV_OP_AUIPC:
            vm->x[inst.rd] = mv_num((double)(vm->pc + inst.imm_u));
            vm->pc += 4;
            break;
         case RV_OP_JAL: {
              long target = (long)vm->pc + inst.imm_j;
              if (target < 0 || target >= vm->bytecode_length || (target % 4) != 0) {
                 (void)metal_rv64_fail(vm, "RISC-V jump target out of bounds");
                 return 0;
             }
             vm->x[inst.rd] = mv_num((double)(vm->pc + 4));
             vm->pc = (int)target;
             break;
         }
         case RV_OP_JALR: {
             if (inst.rd == 0 && inst.rs1 == 1 && inst.imm_i == 0) {
                 if (vm->csp > 0) {
                     vm->csp--;
                     int caller_chunk = vm->call_stack[vm->csp].chunk_idx;
                     int return_pc = vm->call_stack[vm->csp].return_pc;
                     if (caller_chunk < 0 || caller_chunk >= vm->chunk_count ||
                         return_pc < 0 || return_pc >= vm->chunk_lengths[caller_chunk] ||
                         (return_pc % 4) != 0) {
                         (void)metal_rv64_fail(vm, "RISC-V return state is invalid");
                         return 0;
                     }
                     vm->current_chunk_idx = caller_chunk;
                     vm->bytecode = vm->chunks[vm->current_chunk_idx];
                     vm->bytecode_length = vm->chunk_lengths[vm->current_chunk_idx];
                     vm->pc = return_pc;
                     vm->x[1] = vm->call_stack[vm->csp].saved_ra;
                     if (vm->call_stack[vm->csp].is_constructor) {
                         vm->x[10] = vm->call_stack[vm->csp].constructor_instance;
                     }
                     return 1;
                 }
                 vm->running = 0;
                 vm->halted = 1;
                 return 0;
             }
             int target_base = 0;
             if (!metal_rv64_number_index(vm, vm->x[inst.rs1], &target_base)) {
                 (void)metal_rv64_fail(vm, "RISC-V jump target is invalid");
                 return 0;
             }
             long target_long = (long)target_base + inst.imm_i;
             long aligned_target = target_long & ~1L;
             if (aligned_target < 0 || aligned_target >= vm->bytecode_length ||
                 (aligned_target % 4) != 0) {
                 (void)metal_rv64_fail(vm, "RISC-V jump target out of bounds");
                 return 0;
             }
             vm->x[inst.rd] = mv_num((double)(vm->pc + 4));
             vm->pc = (int)aligned_target;
             break;
         }
        case RV_OP_BRANCH:
            handle_branch(vm, inst);
            break;
        case RV_OP_IMM:
            handle_imm(vm, inst);
            break;
        case RV_OP_REG:
            handle_reg(vm, inst);
            break;
        case RV_OP_LDC:
            handle_ldc(vm, inst);
            break;
        case RV_OP_LOAD:
            handle_load(vm, inst);
            break;
        case RV_OP_STORE:
            handle_store(vm, inst);
            break;
        case RV_OP_VMSYS:
            handle_vmsys(vm, inst);
            break;
        default:
            vm->error = 1;
            vm->error_msg = "Unknown RISC-V opcode";
            vm->running = 0;
            return 0;
    }

    // x0 is hardwired to zero
    vm->x[0] = mv_num(0.0);

    return 1;
}

int metal_rv64_vm_run(MetalRV64VM* vm) {
    if (vm == NULL) return -1;
    if (vm->chunk_count == 0) return 0;
    vm->running = 1;
    vm->halted = 0;
    while (vm->running && metal_rv64_vm_step(vm)) {
    }
    if (!vm->error && !vm->halted && vm->running) {
        (void)metal_rv64_fail(vm, "SGRV execution reached end of code");
        return -1;
    }
    return vm->error ? -1 : 0;
}
