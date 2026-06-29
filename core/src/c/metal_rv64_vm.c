#include "metal_rv64_vm.h"

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

// ============================================================================
// Helpers / Internals
// ============================================================================

static void metal_rv64_print_str(MetalRV64VM* vm, const char* s) {
    if (!vm->write_char) return;
    while (*s) vm->write_char(*s++);
}

static void metal_rv64_print_int(MetalRV64VM* vm, long long n) {
    if (n < 0) { if (vm->write_char) vm->write_char('-'); n = -n; }
    char buf[24];
    int i = 0;
    if (n == 0) { buf[i++] = '0'; }
    else { while (n > 0) { buf[i++] = '0' + (int)(n % 10); n /= 10; } }
    while (--i >= 0) if (vm->write_char) vm->write_char(buf[i]);
}

static void metal_rv64_print_double(MetalRV64VM* vm, double d) {
    if (d == (double)(long long)d && d >= -1e15 && d <= 1e15) {
        metal_rv64_print_int(vm, (long long)d);
    } else {
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

static int metal_rv64_string_intern(MetalRV64VM* vm, const char* s, int len) {
    int search = 0;
    while (search < vm->string_used) {
        const char* existing = &vm->strings[search];
        int existing_len = (int)strlen(existing);
        if (existing_len == len) {
            int match = 1;
            for (int i = 0; i < len; i++) {
                if (existing[i] != s[i]) { match = 0; break; }
            }
            if (match) return search;
        }
        search += existing_len + 1;
    }

    if (vm->string_used + len + 1 > METAL_STRING_POOL) return -1;
    int idx = vm->string_used;
    memcpy(&vm->strings[idx], s, (unsigned long)len);
    vm->strings[idx + len] = '\0';
    vm->string_used += len + 1;
    return idx;
}

static const char* metal_rv64_string_get(MetalRV64VM* vm, int idx) {
    if (idx < 0 || idx >= vm->string_used) return "";
    return &vm->strings[idx];
}

static int metal_rv64_array_new(MetalRV64VM* vm) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (vm->array_count >= max) return -1;
    int idx = vm->array_count++;
    vm->arrays[idx].count = 0;
    vm->arrays[idx].in_use = 1;
    return idx;
}

static void metal_rv64_array_push(MetalRV64VM* vm, int arr_idx, MetalValue val) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return;
    MetalArray* a = &vm->arrays[arr_idx];
    if (a->count >= METAL_ARRAY_MAX_ELEMS) return;
    a->elems[a->count++] = val;
}

static MetalValue metal_rv64_array_get(MetalRV64VM* vm, int arr_idx, int index) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return mv_nil();
    MetalArray* a = &vm->arrays[arr_idx];
    if (index < 0 || index >= a->count) return mv_nil();
    return a->elems[index];
}

static int metal_rv64_array_len(MetalRV64VM* vm, int arr_idx) {
    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
    if (arr_idx < 0 || arr_idx >= max) return 0;
    return vm->arrays[arr_idx].count;
}

static int metal_rv64_dict_new(MetalRV64VM* vm) {
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (vm->dict_count >= max) return -1;
    int idx = vm->dict_count++;
    vm->dicts[idx].count = 0;
    vm->dicts[idx].in_use = 1;
    return idx;
}

static void metal_rv64_dict_set(MetalRV64VM* vm, int dict_idx, int key_str_idx, MetalValue val) {
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (dict_idx < 0 || dict_idx >= max) return;
    MetalDict* d = &vm->dicts[dict_idx];
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
    int max = (int)(sizeof(vm->dicts) / sizeof(vm->dicts[0]));
    if (dict_idx < 0 || dict_idx >= max) return mv_nil();
    MetalDict* d = &vm->dicts[dict_idx];
    for (int i = 0; i < d->count; i++) {
        if (d->key_str_idx[i] == key_str_idx) return d->values[i];
    }
    return mv_nil();
}

static void metal_rv64_print_value(MetalRV64VM* vm, MetalValue value) {
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
    memset(vm, 0, sizeof(MetalRV64VM));
    vm->global_dict_idx = metal_rv64_dict_new(vm);
}

int metal_rv64_vm_load_binary(MetalRV64VM* vm, const unsigned char* data, int size) {
    if (size < 8) return -1;
    int pos = 0;

    // Magic: SGRV
    if (data[pos++] != 'S' || data[pos++] != 'G' || data[pos++] != 'R' || data[pos++] != 'V')
        return -2;

    // Version: 2 bytes (expecting 0x00 0x01)
    if (data[pos++] != 0x00 || data[pos++] != 0x01)
        return -3;

    // Constant Count: 2 bytes
    int const_count = (data[pos] << 8) | data[pos + 1];
    pos += 2;

    for (int i = 0; i < const_count; i++) {
        unsigned char type = data[pos++];
        if (type == 1) { // MV_NUM
            union { double d; unsigned char b[8]; } u;
            for (int j = 0; j < 8; j++) u.b[j] = data[pos + 7 - j];
            if (vm->const_count < METAL_CONST_POOL) {
                vm->constants[vm->const_count++] = mv_num(u.d);
            }
            pos += 8;
        } else if (type == 3) { // MV_STR
            int len = (data[pos] << 8) | data[pos + 1];
            pos += 2;
            int str_idx = metal_rv64_string_intern(vm, (const char*)&data[pos], len);
            if (vm->const_count < METAL_CONST_POOL) {
                vm->constants[vm->const_count++] = (MetalValue){MV_STR, {.str_idx = str_idx}};
            }
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
        if (vm->chunk_count < RV64_MAX_CHUNKS) {
            vm->chunks[vm->chunk_count] = &data[pos];
            vm->chunk_lengths[vm->chunk_count] = code_len;
            vm->chunk_count++;
        }
        pos += code_len;
    }

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
            case RV_F3_BLTU: take = ((unsigned long long)a < (unsigned long long)b); break;
            case RV_F3_BGEU: take = ((unsigned long long)a >= (unsigned long long)b); break;
        }
    } else if (rs1_val.type == MV_STR && rs2_val.type == MV_STR) {
        const char* a = metal_rv64_string_get(vm, rs1_val.as.str_idx);
        const char* b = metal_rv64_string_get(vm, rs2_val.as.str_idx);
        int cmp = strcmp(a, b);
        switch (inst.funct3) {
            case RV_F3_BEQ: take = (cmp == 0); break;
            case RV_F3_BNE: take = (cmp != 0); break;
            case RV_F3_BLT: take = (cmp < 0); break;
            case RV_F3_BGE: take = (cmp >= 0); break;
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
        vm->pc += inst.imm_b;
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
                    int len1 = (int)strlen(s1);
                    int len2 = (int)strlen(s2);
                    char concat_buf[1024];
                    if (len1 + len2 < 1024) {
                        memcpy(concat_buf, s1, len1);
                        memcpy(concat_buf + len1, s2, len2);
                        int new_idx = metal_rv64_string_intern(vm, concat_buf, len1 + len2);
                        vm->x[inst.rd] = (MetalValue){MV_STR, {.str_idx = new_idx}};
                    } else {
                        vm->error = 1;
                        vm->error_msg = "String concatenation buffer overflow";
                        vm->x[inst.rd] = mv_nil();
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
                vm->x[inst.rd] = mv_bool(strcmp(a, b) < 0);
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
    int idx = (inst.imm_u >> 12) & 0xFFFFF;
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
    int addr = 0;
    if (vm->x[inst.rs1].type == MV_NUM) {
        addr = (int)vm->x[inst.rs1].as.number;
    }
    addr += inst.imm_i;

    if (addr >= 0 && addr < RV64_STACK_SIZE) {
        vm->x[inst.rd] = vm->stack[addr];
    } else {
        vm->error = 1;
        vm->error_msg = "Load access violation";
        vm->x[inst.rd] = mv_nil();
    }
    vm->pc += 4;
}

static void handle_store(MetalRV64VM* vm, RV64Instruction inst) {
    int addr = 0;
    if (vm->x[inst.rs1].type == MV_NUM) {
        addr = (int)vm->x[inst.rs1].as.number;
    }
    addr += inst.imm_s;

    MetalValue val = vm->x[inst.rs2];
    if (addr >= 0 && addr < RV64_STACK_SIZE) {
        vm->stack[addr] = val;
    } else {
        vm->error = 1;
        vm->error_msg = "Store access violation";
    }
    vm->pc += 4;
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
                metal_rv64_print_value(vm, vm->x[10]); // x10 is a0
                if (vm->write_char) vm->write_char('\n');
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
                    target_chunk = (int)func_obj.as.number;
                } else if (func_obj.type == MV_DICT) {
                    // Check if class constructor call
                    MetalValue type_val = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_string_intern(vm, "__type__", 8));
                    if (type_val.type == MV_STR && strcmp(metal_rv64_string_get(vm, type_val.as.str_idx), "class") == 0) {
                        int inst_dict = metal_rv64_dict_new(vm);
                        metal_rv64_dict_set(vm, inst_dict, metal_rv64_string_intern(vm, "__type__", 8), (MetalValue){MV_STR, {.str_idx = metal_rv64_string_intern(vm, "instance", 8)}});
                        metal_rv64_dict_set(vm, inst_dict, metal_rv64_string_intern(vm, "__class__", 9), func_obj);

                        MetalValue methods_val = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_string_intern(vm, "__methods__", 11));
                        MetalValue init_func = mv_nil();
                        if (methods_val.type == MV_DICT) {
                            init_func = metal_rv64_dict_get(vm, methods_val.as.dict_idx, metal_rv64_string_intern(vm, "init", 4));
                        }

                        if (init_func.type == MV_DICT) {
                            MetalValue chunk_idx_val = metal_rv64_dict_get(vm, init_func.as.dict_idx, metal_rv64_string_intern(vm, "chunk_idx", 9));
                            if (chunk_idx_val.type == MV_NUM) {
                                target_chunk = (int)chunk_idx_val.as.number;
                            }

                            if (target_chunk >= 0 && target_chunk < vm->chunk_count) {
                                if (vm->csp < RV64_CALL_STACK_SIZE) {
                                    vm->call_stack[vm->csp].chunk_idx = vm->current_chunk_idx;
                                    vm->call_stack[vm->csp].return_pc = vm->pc + 4;
                                    vm->call_stack[vm->csp].saved_ra = vm->x[1];
                                    vm->call_stack[vm->csp].is_constructor = 1;
                                    vm->call_stack[vm->csp].constructor_instance = (MetalValue){MV_DICT, {.dict_idx = inst_dict}};
                                    vm->csp++;

                                    // Shift arguments: self is in x10, original args in x11..
                                    for (int r = 17; r > 10; r--) {
                                        vm->x[r] = vm->x[r - 1];
                                    }
                                    vm->x[10] = (MetalValue){MV_DICT, {.dict_idx = inst_dict}};

                                    vm->current_chunk_idx = target_chunk;
                                    vm->bytecode = vm->chunks[target_chunk];
                                    vm->bytecode_length = vm->chunk_lengths[target_chunk];
                                    vm->pc = 0;
                                    vm->x[1] = mv_num(0);
                                    return; // Skip standard PC increment
                                } else {
                                    vm->error = 1;
                                    vm->error_msg = "Call stack overflow";
                                }
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
                    MetalValue builtin = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_string_intern(vm, "__builtin__", 11));
                    if (builtin.type == MV_STR) {
                        const char* b_name = metal_rv64_string_get(vm, builtin.as.str_idx);
                        if (strcmp(b_name, "str") == 0) {
                            int str_idx = metal_rv64_string_intern(vm, "", 0); // fallback
                            if (vm->x[10].type == MV_NUM) {
                                double d = vm->x[10].as.number;
                                if (d == (double)(long long)d && d >= -1e15 && d <= 1e15) {
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
                                    str_idx = metal_rv64_string_intern(vm, fin, pos);
                                } else {
                                    str_idx = metal_rv64_string_intern(vm, "<float>", 7);
                                }
                            } else if (vm->x[10].type == MV_BOOL) {
                                str_idx = metal_rv64_string_intern(vm, vm->x[10].as.boolean ? "true" : "false", vm->x[10].as.boolean ? 4 : 5);
                            }
                            vm->x[10] = (MetalValue){MV_STR, {.str_idx = str_idx}};
                        } else if (strcmp(b_name, "int") == 0) {
                            if (vm->x[10].type == MV_NUM) {
                                vm->x[10] = mv_num((double)(long long)vm->x[10].as.number);
                            }
                        }
                        vm->pc += 4;
                        return;
                    }
                    MetalValue chunk_idx_val = metal_rv64_dict_get(vm, func_obj.as.dict_idx, metal_rv64_string_intern(vm, "chunk_idx", 9));
                    if (chunk_idx_val.type == MV_NUM) {
                        target_chunk = (int)chunk_idx_val.as.number;
                    }
                }

                if (target_chunk >= 0 && target_chunk < vm->chunk_count) {
                    if (vm->csp < RV64_CALL_STACK_SIZE) {
                        vm->call_stack[vm->csp].chunk_idx = vm->current_chunk_idx;
                        vm->call_stack[vm->csp].return_pc = vm->pc + 4;
                        vm->call_stack[vm->csp].saved_ra = vm->x[1]; // Save x1 (ra)
                        vm->call_stack[vm->csp].is_constructor = 0;
                        vm->call_stack[vm->csp].constructor_instance = mv_nil();
                        vm->csp++;

                        vm->current_chunk_idx = target_chunk;
                        vm->bytecode = vm->chunks[target_chunk];
                        vm->bytecode_length = vm->chunk_lengths[target_chunk];
                        vm->pc = 0;
                        vm->x[1] = mv_num(0); // ra = 0
                        return; // Skip standard PC increment
                    } else {
                        vm->error = 1;
                        vm->error_msg = "Call stack overflow";
                    }
                } else {
                    metal_rv64_print_str(vm, "VMO_CALL error: target_chunk=");
                    metal_rv64_print_int(vm, target_chunk);
                    metal_rv64_print_str(vm, " type=");
                    metal_rv64_print_int(vm, func_obj.type);
                    if (func_obj.type == MV_DICT) {
                        metal_rv64_print_str(vm, " dict_idx=");
                        metal_rv64_print_int(vm, func_obj.as.dict_idx);
                        
                        // Let's print keys in dict
                        MetalDict* d = &vm->dicts[func_obj.as.dict_idx];
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
                if (vm->tsp < RV64_TRY_STACK_SIZE) {
                    vm->try_stack[vm->tsp].catch_pc = vm->pc + catch_offset;
                    vm->try_stack[vm->tsp].call_depth = vm->csp;
                    vm->tsp++;
                }
                break;
            }
            case RV_VMO_END_TRY:
                if (vm->tsp > 0) vm->tsp--;
                break;
            case RV_VMO_RAISE: {
                MetalValue exc_obj = vm->x[10]; // a0
                if (vm->tsp > 0) {
                    vm->tsp--;
                    int catch_pc = vm->try_stack[vm->tsp].catch_pc;
                    int target_depth = vm->try_stack[vm->tsp].call_depth;
                    while (vm->csp > target_depth) {
                        vm->csp--;
                    }
                    vm->current_chunk_idx = vm->call_stack[vm->csp].chunk_idx; // or restore current
                    vm->bytecode = vm->chunks[vm->current_chunk_idx];
                    vm->bytecode_length = vm->chunk_lengths[vm->current_chunk_idx];
                    vm->pc = catch_pc;
                    vm->x[10] = exc_obj;
                    return; // Skip standard PC increment
                } else {
                    vm->error = 1;
                    vm->error_msg = "Unhandled exception raised";
                    vm->running = 0;
                    return;
                }
            }
            default:
                break;
        }
    } else if (inst.funct3 == RV_F3_OBJ_OPS) {
        switch (sub_op) {
            case RV_OBJ_GET_GLOBAL: {
                int idx = 0;
                if (vm->x[10].type == MV_NUM) idx = (int)vm->x[10].as.number;
                int name_str_idx = vm->constants[idx].as.str_idx;
                const char* name = metal_rv64_string_get(vm, name_str_idx);
                if (strcmp(name, "str") == 0) {
                    int d_idx = metal_rv64_dict_new(vm);
                    metal_rv64_dict_set(vm, d_idx, metal_rv64_string_intern(vm, "__builtin__", 11), (MetalValue){MV_STR, {.str_idx = metal_rv64_string_intern(vm, "str", 3)}});
                    vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                } else if (strcmp(name, "int") == 0) {
                    int d_idx = metal_rv64_dict_new(vm);
                    metal_rv64_dict_set(vm, d_idx, metal_rv64_string_intern(vm, "__builtin__", 11), (MetalValue){MV_STR, {.str_idx = metal_rv64_string_intern(vm, "int", 3)}});
                    vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                } else {
                    vm->x[inst.rd] = metal_rv64_dict_get(vm, vm->global_dict_idx, name_str_idx);
                }
                break;
            }
            case RV_OBJ_SET_GLOBAL: {
                int idx = 0;
                if (vm->x[10].type == MV_NUM) idx = (int)vm->x[10].as.number;
                int name_str_idx = vm->constants[idx].as.str_idx;
                MetalValue val = vm->x[11]; // a1
                metal_rv64_dict_set(vm, vm->global_dict_idx, name_str_idx, val);
                break;
            }
            case RV_OBJ_GET_PROP: {
                MetalValue obj = vm->x[inst.rs2];
                int name_idx = 0;
                if (vm->x[10].type == MV_NUM) name_idx = (int)vm->x[10].as.number;
                int name_str_idx = vm->constants[name_idx].as.str_idx;
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
                int name_idx = 0;
                if (vm->x[10].type == MV_NUM) name_idx = (int)vm->x[10].as.number;
                int name_str_idx = vm->constants[name_idx].as.str_idx;
                MetalValue val = vm->x[11];
                if (obj.type == MV_DICT) {
                    metal_rv64_dict_set(vm, obj.as.dict_idx, name_str_idx, val);
                }
                break;
            }
            case RV_OBJ_NEW_FUNC: {
                int chunk_idx = 0;
                if (vm->x[10].type == MV_NUM) chunk_idx = (int)vm->x[10].as.number;
                int d_idx = metal_rv64_dict_new(vm);
                metal_rv64_dict_set(vm, d_idx, metal_rv64_string_intern(vm, "type", 4), (MetalValue){MV_STR, {.str_idx = metal_rv64_string_intern(vm, "function", 8)}});
                metal_rv64_dict_set(vm, d_idx, metal_rv64_string_intern(vm, "chunk_idx", 9), mv_num((double)chunk_idx));
                vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                break;
            }
            case RV_OBJ_TUPLE_NEW:
            case RV_OBJ_ARRAY_NEW: {
                int size = 0;
                if (vm->x[10].type == MV_NUM) size = (int)vm->x[10].as.number;
                MetalValue init_val = vm->x[11];
                int arr = metal_rv64_array_new(vm);
                for (int i = 0; i < size; i++) {
                    metal_rv64_array_push(vm, arr, init_val);
                }
                vm->x[inst.rd] = (MetalValue){MV_ARR, {.arr_idx = arr}};
                break;
            }
            case RV_OBJ_DICT_NEW: {
                int d_idx = metal_rv64_dict_new(vm);
                vm->x[inst.rd] = (MetalValue){MV_DICT, {.dict_idx = d_idx}};
                break;
            }
            case RV_OBJ_GET_INDEX: {
                MetalValue obj = vm->x[inst.rs2];
                int idx = 0;
                if (vm->x[10].type == MV_NUM) idx = (int)vm->x[10].as.number;
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
                if (vm->x[10].type == MV_NUM) idx = (int)vm->x[10].as.number;
                MetalValue val = vm->x[11];
                if (obj.type == MV_ARR) {
                    int arr_idx = obj.as.arr_idx;
                    int max = (int)(sizeof(vm->arrays) / sizeof(vm->arrays[0]));
                    if (arr_idx >= 0 && arr_idx < max && idx >= 0 && idx < vm->arrays[arr_idx].count) {
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
    if (vm->halted || vm->error || vm->pc >= vm->bytecode_length) return 0;

    // Fetch 32-bit instruction (little-endian)
    unsigned int raw = vm->bytecode[vm->pc] |
                      (vm->bytecode[vm->pc + 1] << 8) |
                      (vm->bytecode[vm->pc + 2] << 16) |
                      (vm->bytecode[vm->pc + 3] << 24);

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
        case RV_OP_JAL:
            vm->x[inst.rd] = mv_num((double)(vm->pc + 4));
            vm->pc += inst.imm_j;
            break;
        case RV_OP_JALR: {
            double target_base = 0.0;
            if (vm->x[inst.rs1].type == MV_NUM) {
                target_base = vm->x[inst.rs1].as.number;
            }
            int target = ((int)target_base + inst.imm_i) & ~1;
            MetalValue rd_val = mv_num((double)(vm->pc + 4));

            // Special case for return: JALR x0, 0(x1)
            if (inst.rd == 0 && inst.rs1 == 1 && inst.imm_i == 0) {
                if (vm->csp > 0) {
                    vm->csp--;
                    vm->current_chunk_idx = vm->call_stack[vm->csp].chunk_idx;
                    vm->bytecode = vm->chunks[vm->current_chunk_idx];
                    vm->bytecode_length = vm->chunk_lengths[vm->current_chunk_idx];
                    vm->pc = vm->call_stack[vm->csp].return_pc;
                    vm->x[1] = vm->call_stack[vm->csp].saved_ra;
                    if (vm->call_stack[vm->csp].is_constructor) {
                        vm->x[10] = vm->call_stack[vm->csp].constructor_instance;
                    }
                    return 1; // Skip standard PC increment
                } else {
                    vm->running = 0;
                    vm->halted = 1;
                    return 0;
                }
            }

            vm->x[inst.rd] = rd_val;
            vm->pc = target;
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
    vm->running = 1;
    vm->halted = 0;
    while (vm->running && metal_rv64_vm_step(vm)) {
        // Execution loop
    }
    return vm->error ? -1 : 0;
}
