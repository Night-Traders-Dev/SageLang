#include "program.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include "gc.h"
#include "lexer.h"
#include "parser.h"
#include "pass.h"

static void set_program_error(char* error, size_t error_size, const char* message);

#define VM_ARTIFACT_MAX_FUNCTIONS 65535
#define VM_ARTIFACT_MAX_CHUNKS 65535
#define VM_ARTIFACT_MAX_CONSTANTS 65536
#define VM_ARTIFACT_MAX_PARAMS 65535
#define VM_ARTIFACT_MAX_CODE_BYTES (16 * 1024 * 1024)
#define VM_ARTIFACT_MAX_LOCALS 256
#define VM_ARTIFACT_STACK_MAX 65536

typedef struct {
    int pops;
    int pushes;
    int terminal;
    int branch_kind;
    int target;
} VMInstructionFlow;

static int vm_opcode_width(int op) {
    switch ((BytecodeOp)op) {
        case BC_OP_CONSTANT:
        case BC_OP_GET_GLOBAL:
        case BC_OP_DEFINE_GLOBAL:
        case BC_OP_SET_GLOBAL:
        case BC_OP_GET_PROPERTY:
        case BC_OP_SET_PROPERTY:
        case BC_OP_LOAD_FUNCTION:
        case BC_OP_JUMP:
        case BC_OP_JUMP_IF_FALSE:
        case BC_OP_ARRAY:
        case BC_OP_TUPLE:
        case BC_OP_DICT:
        case BC_OP_EXEC_AST_STMT:
        case BC_OP_LOOP_BACK:
        case BC_OP_IMPORT:
        case BC_OP_CLASS:
        case BC_OP_METHOD:
        case BC_OP_SETUP_TRY:
        case BC_OP_GET_LOCAL:
        case BC_OP_SET_LOCAL:
            return 2;
        case BC_OP_DEFINE_FUNCTION:
        case BC_OP_CREATE_GENERATOR:
            return 4;
        case BC_OP_CALL_METHOD:
            return 3;
        case BC_OP_CALL:
        case BC_OP_DUP:
            return 1;
        case BC_OP_NIL:
        case BC_OP_TRUE:
        case BC_OP_FALSE:
        case BC_OP_POP:
        case BC_OP_GET_INDEX:
        case BC_OP_SET_INDEX:
        case BC_OP_SLICE:
        case BC_OP_ADD:
        case BC_OP_SUB:
        case BC_OP_MUL:
        case BC_OP_DIV:
        case BC_OP_MOD:
        case BC_OP_NEGATE:
        case BC_OP_EQUAL:
        case BC_OP_NOT_EQUAL:
        case BC_OP_GREATER:
        case BC_OP_GREATER_EQUAL:
        case BC_OP_LESS:
        case BC_OP_LESS_EQUAL:
        case BC_OP_BIT_AND:
        case BC_OP_BIT_OR:
        case BC_OP_BIT_XOR:
        case BC_OP_BIT_NOT:
        case BC_OP_SHIFT_LEFT:
        case BC_OP_SHIFT_RIGHT:
        case BC_OP_NOT:
        case BC_OP_TRUTHY:
        case BC_OP_PRINT:
        case BC_OP_RETURN:
        case BC_OP_PUSH_ENV:
        case BC_OP_POP_ENV:
        case BC_OP_ARRAY_LEN:
        case BC_OP_BREAK:
        case BC_OP_CONTINUE:
        case BC_OP_INHERIT:
        case BC_OP_END_TRY:
        case BC_OP_RAISE:
        case BC_OP_YIELD:
        case BC_OP_GENERATOR_NEXT:
        case BC_OP_GPU_POLL_EVENTS:
        case BC_OP_GPU_WINDOW_SHOULD_CLOSE:
        case BC_OP_GPU_GET_TIME:
        case BC_OP_GPU_KEY_PRESSED:
        case BC_OP_GPU_KEY_DOWN:
        case BC_OP_GPU_MOUSE_POS:
        case BC_OP_GPU_MOUSE_DELTA:
        case BC_OP_GPU_UPDATE_INPUT:
        case BC_OP_GPU_BEGIN_COMMANDS:
        case BC_OP_GPU_END_COMMANDS:
        case BC_OP_GPU_CMD_BEGIN_RP:
        case BC_OP_GPU_CMD_END_RP:
        case BC_OP_GPU_CMD_DRAW:
        case BC_OP_GPU_CMD_BIND_GP:
        case BC_OP_GPU_CMD_BIND_DS:
        case BC_OP_GPU_CMD_SET_VP:
        case BC_OP_GPU_CMD_SET_SC:
        case BC_OP_GPU_CMD_BIND_VB:
        case BC_OP_GPU_CMD_BIND_IB:
        case BC_OP_GPU_CMD_DRAW_IDX:
        case BC_OP_GPU_SUBMIT_SYNC:
        case BC_OP_GPU_ACQUIRE_IMG:
        case BC_OP_GPU_PRESENT:
        case BC_OP_GPU_WAIT_FENCE:
        case BC_OP_GPU_RESET_FENCE:
        case BC_OP_GPU_UPDATE_UNIFORM:
        case BC_OP_GPU_CMD_PUSH_CONST:
        case BC_OP_GPU_CMD_DISPATCH:
            return 0;
        default:
            return -1;
    }
}

static int vm_validate_name_operand(const BytecodeChunk* chunk, int operand_pos,
                                    const unsigned char* code, int code_count,
                                    char* error, size_t error_size) {
    if (operand_pos < 0 || operand_pos + 2 > code_count) {
        set_program_error(error, error_size, "Truncated VM bytecode operand.");
        return 0;
    }
    int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
    if (index < 0 || index >= chunk->constant_count || chunk->constants == NULL ||
        !IS_STRING(chunk->constants[index])) {
        set_program_error(error, error_size, "VM bytecode references an invalid name constant.");
        return 0;
    }
    return 1;
}

static int vm_validate_operands(const BytecodeChunk* chunk, int code_count,
                                const unsigned char* code, int instruction_offset,
                                const unsigned char* instruction_starts,
                                const BytecodeProgram* program,
                                char* error, size_t error_size) {
    int op = code[instruction_offset];
    int width = vm_opcode_width(op);
    int operand_pos = instruction_offset + 1;
    if (width < 0 || width > code_count - operand_pos) {
        set_program_error(error, error_size, "VM bytecode contains an invalid or truncated opcode.");
        return 0;
    }

    switch ((BytecodeOp)op) {
        case BC_OP_CONSTANT: {
            int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            if (index < 0 || index >= chunk->constant_count || chunk->constants == NULL) {
                set_program_error(error, error_size, "VM bytecode references an invalid constant.");
                return 0;
            }
            return 1;
        }
        case BC_OP_LOAD_FUNCTION: {
            int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            if (program == NULL || index < 0 || index >= program->function_count) {
                set_program_error(error, error_size, "VM bytecode references an invalid function.");
                return 0;
            }
            return 1;
        }
        case BC_OP_GET_GLOBAL:
        case BC_OP_DEFINE_GLOBAL:
        case BC_OP_SET_GLOBAL:
        case BC_OP_GET_PROPERTY:
        case BC_OP_SET_PROPERTY:
        case BC_OP_IMPORT:
        case BC_OP_CLASS:
        case BC_OP_METHOD:
        case BC_OP_CALL_METHOD:
            return vm_validate_name_operand(chunk, operand_pos, code, code_count,
                                            error, error_size);
        case BC_OP_CREATE_GENERATOR:
        case BC_OP_DEFINE_FUNCTION:
            if (!vm_validate_name_operand(chunk, operand_pos, code, code_count,
                                          error, error_size) ||
                operand_pos + 4 > code_count) {
                if (operand_pos + 4 > code_count) {
                    set_program_error(error, error_size, "Truncated VM function reference.");
                }
                return 0;
            } else {
                int function_index = ((int)code[operand_pos + 2] << 8) | code[operand_pos + 3];
                if (program == NULL || function_index < 0 || function_index >= program->function_count) {
                    set_program_error(error, error_size, "VM bytecode references an invalid function.");
                    return 0;
                }
                return 1;
            }
        case BC_OP_EXEC_AST_STMT: {
            int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            if (index < 0 || index >= chunk->ast_stmt_count || chunk->ast_stmts == NULL) {
                set_program_error(error, error_size, "VM bytecode references an invalid AST statement.");
                return 0;
            }
            return 1;
        }
        case BC_OP_GET_LOCAL:
        case BC_OP_SET_LOCAL: {
            int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            if (index < 0 || index >= VM_ARTIFACT_MAX_LOCALS) {
                set_program_error(error, error_size, "VM bytecode local index is out of bounds.");
                return 0;
            }
            return 1;
        }
        case BC_OP_JUMP:
        case BC_OP_JUMP_IF_FALSE:
        case BC_OP_SETUP_TRY: {
            int target = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            if (target < 0 || target >= code_count ||
                (target < code_count && instruction_starts != NULL && !instruction_starts[target])) {
                set_program_error(error, error_size, "VM bytecode branch target is out of bounds.");
                return 0;
            }
            return 1;
        }
        case BC_OP_LOOP_BACK: {
            int offset = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            long target = (long)operand_pos + 2L - offset;
            if (target < 0 || target >= code_count ||
                (target < code_count && instruction_starts != NULL && !instruction_starts[(size_t)target])) {
                set_program_error(error, error_size, "VM bytecode loop target is out of bounds.");
                return 0;
            }
            return 1;
        }
        case BC_OP_CALL:
        case BC_OP_DUP:
        case BC_OP_ARRAY:
        case BC_OP_TUPLE:
        case BC_OP_DICT:
            return 1;
        case BC_OP_BREAK:
        case BC_OP_CONTINUE:
            set_program_error(error, error_size, "VM bytecode contains an unresolved loop opcode.");
            return 0;
        default:
            return 1;
    }
}

static int vm_merge_stack_state(int* minimum, int* maximum, int target,
                                int target_minimum, int target_maximum,
                                int code_count, int preserve_maximum) {
    if (target < 0 || target > code_count) return 0;
    if (target == code_count) {
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

static int vm_instruction_flow(const BytecodeChunk* chunk, int code_count,
                               const unsigned char* code, int instruction_offset,
                               const BytecodeProgram* program, VMInstructionFlow* flow,
                               char* error, size_t error_size) {
    int op = code[instruction_offset];
    int operand_pos = instruction_offset + 1;
    memset(flow, 0, sizeof(*flow));

    switch ((BytecodeOp)op) {
        case BC_OP_CONSTANT:
        case BC_OP_NIL:
        case BC_OP_TRUE:
        case BC_OP_FALSE:
        case BC_OP_GET_GLOBAL:
        case BC_OP_GET_LOCAL:
        case BC_OP_LOAD_FUNCTION:
        case BC_OP_DUP:
         case BC_OP_IMPORT:
         case BC_OP_CLASS:
         case BC_OP_CREATE_GENERATOR:
        case BC_OP_GPU_WINDOW_SHOULD_CLOSE:
        case BC_OP_GPU_GET_TIME:
        case BC_OP_GPU_MOUSE_POS:
        case BC_OP_GPU_MOUSE_DELTA:
        case BC_OP_GPU_ACQUIRE_IMG:
            flow->pushes = 1;
            if (op == BC_OP_DUP) {
                int distance = code[operand_pos];
                if (distance < 0) {
                    set_program_error(error, error_size, "VM bytecode duplicate distance is invalid.");
                    return 0;
                }
            }
            break;
        case BC_OP_POP:
        case BC_OP_PRINT:
        case BC_OP_DEFINE_GLOBAL:
        case BC_OP_RAISE:
            flow->pops = 1;
            if (op == BC_OP_RAISE) flow->terminal = 1;
            break;
         case BC_OP_SET_GLOBAL:
             flow->pops = 1;
             flow->pushes = 1;
             break;
        case BC_OP_GET_PROPERTY:
            flow->pops = 1;
            flow->pushes = 1;
            break;
        case BC_OP_SET_PROPERTY:
            flow->pops = 2;
            flow->pushes = 1;
            break;
         case BC_OP_SET_INDEX:
         case BC_OP_SLICE:
             flow->pops = 3;
             flow->pushes = 1;
             break;
        case BC_OP_INHERIT:
            flow->pops = 2;
            flow->pushes = 1;
            break;
        case BC_OP_METHOD:
            flow->pops = 1;
            break;
        case BC_OP_SET_LOCAL:
            flow->pops = 1;
            flow->pushes = 1;
            break;
        case BC_OP_GET_INDEX:
        case BC_OP_EXEC_AST_STMT:
        case BC_OP_GENERATOR_NEXT:
        case BC_OP_ARRAY_LEN:
        case BC_OP_GPU_POLL_EVENTS:
        case BC_OP_GPU_UPDATE_INPUT:
        case BC_OP_GPU_KEY_PRESSED:
        case BC_OP_GPU_KEY_DOWN:
        case BC_OP_GPU_BEGIN_COMMANDS:
        case BC_OP_GPU_END_COMMANDS:
              if (op == BC_OP_GET_INDEX) {
                 flow->pops = 2;
                 flow->pushes = 1;
             } else if (op == BC_OP_GENERATOR_NEXT || op == BC_OP_ARRAY_LEN) {
                 flow->pops = 1;
                 flow->pushes = 1;

            } else if (op == BC_OP_EXEC_AST_STMT) {
                flow->pushes = 1;
            }
            break;
        case BC_OP_ADD:
        case BC_OP_SUB:
        case BC_OP_MUL:
        case BC_OP_DIV:
        case BC_OP_MOD:
        case BC_OP_EQUAL:
        case BC_OP_NOT_EQUAL:
        case BC_OP_GREATER:
        case BC_OP_GREATER_EQUAL:
        case BC_OP_LESS:
        case BC_OP_LESS_EQUAL:
        case BC_OP_BIT_AND:
        case BC_OP_BIT_OR:
        case BC_OP_BIT_XOR:
        case BC_OP_SHIFT_LEFT:
        case BC_OP_SHIFT_RIGHT:
            flow->pops = 2;
            flow->pushes = 1;
            break;
        case BC_OP_NEGATE:
        case BC_OP_BIT_NOT:
        case BC_OP_NOT:
        case BC_OP_TRUTHY:
        case BC_OP_YIELD:
            flow->pops = 1;
            flow->pushes = 1;
            break;
        case BC_OP_JUMP:
            flow->branch_kind = 1;
            flow->target = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            break;
        case BC_OP_LOOP_BACK: {
            int offset = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            flow->branch_kind = 1;
            flow->target = (int)((long)operand_pos + 2L - offset);
            break;
        }
        case BC_OP_JUMP_IF_FALSE:
            flow->branch_kind = 2;
            flow->target = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            break;
        case BC_OP_SETUP_TRY:
            flow->branch_kind = 3;
            flow->target = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            break;
        case BC_OP_CALL:
        case BC_OP_CALL_METHOD: {
            int argument_count = op == BC_OP_CALL ? code[operand_pos] : code[operand_pos + 2];
            flow->pops = argument_count + 1;
            flow->pushes = 1;
            break;
        }
        case BC_OP_ARRAY:
        case BC_OP_TUPLE: {
            int count = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            flow->pops = count;
            flow->pushes = 1;
            break;
        }
        case BC_OP_DICT: {
            int count = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
            flow->pops = count * 2;
            flow->pushes = 1;
            break;
        }
         case BC_OP_END_TRY:
         case BC_OP_PUSH_ENV:
         case BC_OP_POP_ENV:
         case BC_OP_DEFINE_FUNCTION:
         case BC_OP_RETURN:
        case BC_OP_BREAK:
        case BC_OP_CONTINUE:
            if (op == BC_OP_RETURN) flow->terminal = 1;
            break;
        case BC_OP_GPU_CMD_BEGIN_RP:
            flow->pops = 6;
            break;
        case BC_OP_GPU_CMD_END_RP:
        case BC_OP_GPU_RESET_FENCE:
            flow->pops = 1;
            break;
        case BC_OP_GPU_PRESENT:
        case BC_OP_GPU_WAIT_FENCE:
        case BC_OP_GPU_UPDATE_UNIFORM:
            flow->pops = 2;
            break;
        case BC_OP_GPU_CMD_PUSH_CONST:
        case BC_OP_GPU_CMD_DISPATCH:
            flow->pops = 4;
            break;
        case BC_OP_GPU_CMD_DRAW:
            flow->pops = 5;
            break;
        case BC_OP_GPU_CMD_BIND_GP:
        case BC_OP_GPU_CMD_BIND_VB:
        case BC_OP_GPU_CMD_BIND_IB:
            flow->pops = 2;
            break;
        case BC_OP_GPU_CMD_BIND_DS:
            flow->pops = 4;
            break;
        case BC_OP_GPU_CMD_SET_VP:
            flow->pops = 7;
            break;
        case BC_OP_GPU_CMD_SET_SC:
            flow->pops = 5;
            break;
        case BC_OP_GPU_CMD_DRAW_IDX:
            flow->pops = 6;
            break;
        case BC_OP_GPU_SUBMIT_SYNC:
            flow->pops = 4;
            flow->pushes = 1;
            break;
        default: {
            char message[64];
            snprintf(message, sizeof(message), "VM bytecode contains unknown opcode %d.", op);
            set_program_error(error, error_size, message);
            return 0;
        }
    }

    (void)chunk;
    (void)code_count;
    (void)program;
    return 1;
}

static int vm_validate_stack_dataflow(const BytecodeChunk* chunk, int initial_stack,
                                      const unsigned char* code, int code_count,
                                      const unsigned char* instruction_starts,
                                      const BytecodeProgram* program,
                                      char* error, size_t error_size) {
    if (initial_stack < 0 || initial_stack > VM_ARTIFACT_STACK_MAX) {
        set_program_error(error, error_size, "VM initial stack depth is out of bounds.");
        return 0;
    }
    if (code_count == 0) return 1;

    int* minimum = malloc(sizeof(int) * (size_t)(code_count + 1));
    int* maximum = malloc(sizeof(int) * (size_t)(code_count + 1));
    if (minimum == NULL || maximum == NULL) {
        free(minimum);
        free(maximum);
        set_program_error(error, error_size, "Unable to allocate VM validation state.");
        return 0;
    }
    for (int i = 0; i <= code_count; i++) {
        minimum[i] = -1;
        maximum[i] = -1;
    }
    minimum[0] = initial_stack;
    maximum[0] = initial_stack;

    int changed = 1;
    size_t iterations = 0;
    size_t max_iterations = (size_t)code_count * 4u + 1024u;
    while (changed) {
        if (++iterations > max_iterations) {
            free(minimum);
            free(maximum);
            set_program_error(error, error_size, "VM bytecode dataflow did not converge.");
            return 0;
        }
        changed = 0;
        for (int offset = 0; offset < code_count; offset++) {
            if (!instruction_starts[offset] || minimum[offset] < 0) continue;

            VMInstructionFlow flow;
            if (!vm_instruction_flow(chunk, code_count, code, offset, program, &flow,
                                    error, error_size)) {
                free(minimum);
                free(maximum);
                return 0;
            }
            if (minimum[offset] < flow.pops) {
                free(minimum);
                free(maximum);
                set_program_error(error, error_size, "VM bytecode stack underflow.");
                return 0;
            }
            int raw_op = code[offset];
            int operand_pos = offset + 1;
            if (raw_op == BC_OP_DUP) {
                int distance = code[operand_pos];
                if (minimum[offset] < distance + 1) {
                    free(minimum);
                    free(maximum);
                    set_program_error(error, error_size, "VM bytecode stack underflow.");
                    return 0;
                }
            } else if (raw_op == BC_OP_GET_LOCAL) {
                int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
                if (index >= minimum[offset]) {
                    free(minimum);
                    free(maximum);
                    set_program_error(error, error_size, "VM bytecode local index is out of bounds.");
                    return 0;
                }
            } else if (raw_op == BC_OP_SET_LOCAL) {
                int index = ((int)code[operand_pos] << 8) | code[operand_pos + 1];
                if (minimum[offset] < 1 || index >= minimum[offset]) {
                    free(minimum);
                    free(maximum);
                    set_program_error(error, error_size, "VM bytecode local index is out of bounds.");
                    return 0;
                }
            }
            long next_minimum = (long)minimum[offset] - flow.pops + flow.pushes;
            long next_maximum = (long)maximum[offset] - flow.pops + flow.pushes;
            if (next_minimum < 0 || next_maximum > VM_ARTIFACT_STACK_MAX) {
                char message[128];
                snprintf(message, sizeof(message),
                         "VM bytecode stack depth is out of bounds at offset %d (op %d, min %d, max %d).",
                         offset, code[offset], minimum[offset], maximum[offset]);
                free(minimum);
                free(maximum);
                set_program_error(error, error_size, message);
                return 0;
            }

            int next = offset + 1 + vm_opcode_width(code[offset]);
            if (!flow.terminal && flow.branch_kind != 1 && next <= code_count) {
                changed |= vm_merge_stack_state(minimum, maximum, next,
                                                 (int)next_minimum, (int)next_maximum,
                                                 code_count, next < offset);
            }
            if (flow.branch_kind != 0) {
                int branch_minimum = (int)next_minimum;
                int branch_maximum = (int)next_maximum;
                if (flow.branch_kind == 3) {
                    if (branch_maximum >= VM_ARTIFACT_STACK_MAX) {
                        free(minimum);
                        free(maximum);
                        set_program_error(error, error_size, "VM exception handler stack depth is out of bounds.");
                        return 0;
                    }
                    branch_minimum++;
                    branch_maximum++;
                }
                if (flow.target < 0 || flow.target >= code_count ||
                    (flow.target < code_count && !instruction_starts[flow.target])) {
                    free(minimum);
                    free(maximum);
                    set_program_error(error, error_size, "VM bytecode branch target is invalid.");
                    return 0;
                }
                changed |= vm_merge_stack_state(minimum, maximum, flow.target,
                                                 branch_minimum, branch_maximum,
                                                 code_count, flow.target < offset);
            }
        }
    }

    free(minimum);
    free(maximum);
    return 1;
}

int bytecode_chunk_validate(const BytecodeChunk* chunk, int initial_stack,
                            const BytecodeProgram* program, char* error, size_t error_size) {
    if (chunk == NULL) {
        set_program_error(error, error_size, "VM bytecode chunk is null.");
        return 0;
    }
    if (initial_stack < 0 || initial_stack > VM_ARTIFACT_STACK_MAX ||
        chunk->code_count < 0 || chunk->constant_count < 0 || chunk->ast_stmt_count < 0 ||
        chunk->code_capacity < chunk->code_count ||
        chunk->constant_capacity < chunk->constant_count ||
        chunk->ast_stmt_capacity < chunk->ast_stmt_count) {
        set_program_error(error, error_size, "VM bytecode chunk has invalid counts.");
        return 0;
    }
    if (chunk->code_count > VM_ARTIFACT_MAX_CODE_BYTES ||
        (chunk->code_count > 0 && chunk->code == NULL) ||
        (chunk->constant_count > 0 && chunk->constants == NULL) ||
        (chunk->ast_stmt_count > 0 && chunk->ast_stmts == NULL)) {
        set_program_error(error, error_size, "VM bytecode chunk has invalid storage.");
        return 0;
    }
    for (int i = 0; i < chunk->constant_count; i++) {
        Value constant = chunk->constants[i];
        if (constant.type != VAL_NUMBER &&
            (constant.type != VAL_STRING || constant.as.string == NULL)) {
            set_program_error(error, error_size, "VM constant pool contains an invalid value.");
            return 0;
        }
    }
    for (int i = 0; i < chunk->ast_stmt_count; i++) {
        if (chunk->ast_stmts[i] == NULL) {
            set_program_error(error, error_size, "VM AST statement table contains a null entry.");
            return 0;
        }
    }
    if (chunk->code_count == 0) return 1;

    unsigned char* instruction_starts = calloc((size_t)chunk->code_count + 1, sizeof(unsigned char));
    if (instruction_starts == NULL) {
        set_program_error(error, error_size, "Unable to allocate VM bytecode validation state.");
        return 0;
    }

    int offset = 0;
    while (offset < chunk->code_count) {
        instruction_starts[offset] = 1;
        int width = vm_opcode_width(chunk->code[offset]);
        if (width < 0 || width > chunk->code_count - offset - 1) {
            free(instruction_starts);
            set_program_error(error, error_size, "VM bytecode contains an invalid or truncated opcode.");
            return 0;
        }
        offset += 1 + width;
    }
    instruction_starts[chunk->code_count] = 1;

    offset = 0;
    while (offset < chunk->code_count) {
        if (!vm_validate_operands(chunk, chunk->code_count, chunk->code, offset,
                                  instruction_starts, program, error, error_size)) {
            free(instruction_starts);
            return 0;
        }
        offset += 1 + vm_opcode_width(chunk->code[offset]);
    }

    int valid = vm_validate_stack_dataflow(chunk, initial_stack, chunk->code,
                                           chunk->code_count, instruction_starts,
                                           program, error, error_size);
    free(instruction_starts);
    return valid;
}

int bytecode_program_validate(const BytecodeProgram* program, char* error, size_t error_size) {
    if (program == NULL) {
        set_program_error(error, error_size, "VM program is null.");
        return 0;
    }
    if (program->function_count < 0 || program->chunk_count < 0 ||
        program->function_capacity < 0 || program->chunk_capacity < 0 ||
        program->function_count > program->function_capacity ||
        program->chunk_count > program->chunk_capacity ||
        program->function_count > VM_ARTIFACT_MAX_FUNCTIONS ||
        program->chunk_count > VM_ARTIFACT_MAX_CHUNKS ||
        (program->function_count > 0 && program->functions == NULL) ||
        (program->chunk_count > 0 && program->chunks == NULL)) {
        set_program_error(error, error_size, "VM program has invalid table counts.");
        return 0;
    }

    for (int i = 0; i < program->function_count; i++) {
        const BytecodeFunction* function = &program->functions[i];
        if (function->param_count < 0 || function->param_count > VM_ARTIFACT_MAX_PARAMS ||
            function->param_count > VM_ARTIFACT_MAX_LOCALS ||
            (function->param_count > 0 && function->params == NULL)) {
            set_program_error(error, error_size, "VM function has invalid parameter metadata.");
            return 0;
        }
        for (int j = 0; j < function->param_count; j++) {
            if (function->params[j] == NULL) {
                set_program_error(error, error_size, "VM function parameter is null.");
                return 0;
            }
        }
        if (!bytecode_chunk_validate(&function->chunk, function->param_count, program,
                                     error, error_size)) {
            return 0;
        }
    }

    for (int i = 0; i < program->chunk_count; i++) {
        if (!bytecode_chunk_validate(&program->chunks[i], 0, program, error, error_size)) {
            return 0;
        }
    }
    return 1;
}

static void set_program_error(char* error, size_t error_size, const char* message) {
    if (error != NULL && error_size > 0) {
        snprintf(error, error_size, "%s", message);
    }
}

static char* dup_text(const char* text, size_t length) {
    if (text == NULL || length == SIZE_MAX) return NULL;
    char* copy = SAGE_ALLOC(length + 1);
    memcpy(copy, text, length);
    copy[length] = '\0';
    return copy;
}

static int ensure_chunk_capacity(BytecodeProgram* program) {
    if (program == NULL || program->chunk_count < 0 || program->chunk_capacity < 0 ||
        program->chunk_count >= VM_ARTIFACT_MAX_CHUNKS) {
        return 0;
    }
    if (program->chunk_count < program->chunk_capacity) {
        return 1;
    }

    int new_capacity = program->chunk_capacity == 0 ? 8 : program->chunk_capacity;
    if (new_capacity < VM_ARTIFACT_MAX_CHUNKS) {
        if (new_capacity > VM_ARTIFACT_MAX_CHUNKS / 2) {
            new_capacity = VM_ARTIFACT_MAX_CHUNKS;
        } else {
            new_capacity *= 2;
        }
    }
    if (new_capacity <= program->chunk_capacity ||
        (size_t)new_capacity > SIZE_MAX / sizeof(BytecodeChunk)) {
        return 0;
    }
    program->chunks = SAGE_REALLOC(program->chunks, sizeof(BytecodeChunk) * (size_t)new_capacity);
    program->chunk_capacity = new_capacity;
    return 1;
}

static int ensure_function_capacity(BytecodeProgram* program) {
    if (program == NULL || program->function_count < 0 || program->function_capacity < 0 ||
        program->function_count >= VM_ARTIFACT_MAX_FUNCTIONS) {
        return 0;
    }
    if (program->function_count < program->function_capacity) {
        return 1;
    }

    int new_capacity = program->function_capacity == 0 ? 8 : program->function_capacity;
    if (new_capacity < VM_ARTIFACT_MAX_FUNCTIONS) {
        if (new_capacity > VM_ARTIFACT_MAX_FUNCTIONS / 2) {
            new_capacity = VM_ARTIFACT_MAX_FUNCTIONS;
        } else {
            new_capacity *= 2;
        }
    }
    if (new_capacity <= program->function_capacity ||
        (size_t)new_capacity > SIZE_MAX / sizeof(BytecodeFunction)) {
        return 0;
    }
    program->functions = SAGE_REALLOC(program->functions, sizeof(BytecodeFunction) * (size_t)new_capacity);
    program->function_capacity = new_capacity;
    return 1;
}

static int ensure_constant_capacity(BytecodeChunk* chunk, int needed) {
    if (chunk == NULL || chunk->constant_count < 0 || chunk->constant_capacity < 0 ||
        needed <= 0 || chunk->constant_count > VM_ARTIFACT_MAX_CONSTANTS - needed) {
        return 0;
    }
    int required = chunk->constant_count + needed;
    if (required <= chunk->constant_capacity) {
        return 1;
    }

    int new_capacity = chunk->constant_capacity == 0 ? 16 : chunk->constant_capacity;
    while (new_capacity < required) {
        if (new_capacity > VM_ARTIFACT_MAX_CONSTANTS / 2) {
            new_capacity = VM_ARTIFACT_MAX_CONSTANTS;
            break;
        }
        new_capacity *= 2;
    }
    if (new_capacity < required ||
        (size_t)new_capacity > SIZE_MAX / sizeof(Value)) {
        return 0;
    }

    chunk->constants = SAGE_REALLOC(chunk->constants, sizeof(Value) * (size_t)new_capacity);
    chunk->constant_capacity = new_capacity;
    return 1;
}

static int ensure_code_capacity(BytecodeChunk* chunk, int needed) {
    if (chunk == NULL || chunk->code_count < 0 || needed < 0 ||
        chunk->code_capacity < 0 ||
        chunk->code_count > VM_ARTIFACT_MAX_CODE_BYTES - needed) {
        return 0;
    }
    int required = chunk->code_count + needed;
    if (required <= chunk->code_capacity) {
        return 1;
    }

    int new_capacity = chunk->code_capacity == 0 ? 64 : chunk->code_capacity;
    while (new_capacity < required) {
        if (new_capacity > VM_ARTIFACT_MAX_CODE_BYTES / 2) {
            new_capacity = VM_ARTIFACT_MAX_CODE_BYTES;
            break;
        }
        new_capacity *= 2;
    }
    if (new_capacity < required ||
        (size_t)new_capacity > SIZE_MAX / sizeof(int)) {
        return 0;
    }

    uint8_t* new_code = SAGE_ALLOC((size_t)new_capacity);
    int* new_lines = SAGE_ALLOC(sizeof(int) * (size_t)new_capacity);
    int* new_columns = SAGE_ALLOC(sizeof(int) * (size_t)new_capacity);
    if (new_code == NULL || new_lines == NULL || new_columns == NULL) {
        free(new_code);
        free(new_lines);
        free(new_columns);
        return 0;
    }

    if (chunk->code_count > 0 &&
        (chunk->code == NULL || chunk->lines == NULL || chunk->columns == NULL)) {
        free(new_code);
        free(new_lines);
        free(new_columns);
        return 0;
    }
    if (chunk->code_count > 0) {
        memcpy(new_code, chunk->code, (size_t)chunk->code_count);
        memcpy(new_lines, chunk->lines, sizeof(int) * (size_t)chunk->code_count);
        memcpy(new_columns, chunk->columns, sizeof(int) * (size_t)chunk->code_count);
    }

    free(chunk->code);
    free(chunk->lines);
    free(chunk->columns);

    chunk->code = new_code;
    chunk->lines = new_lines;
    chunk->columns = new_columns;
    chunk->code_capacity = new_capacity;
    return 1;
}

static int append_constant(BytecodeChunk* chunk, Value value) {
    if (chunk == NULL || !ensure_constant_capacity(chunk, 1)) {
        return 0;
    }
    chunk->constants[chunk->constant_count++] = value;
    return 1;
}

static int append_chunk(BytecodeProgram* program, BytecodeChunk* chunk, char* error, size_t error_size) {
    if (!ensure_chunk_capacity(program)) {
        set_program_error(error, error_size, "Out of memory while storing compiled VM chunks.");
        return 0;
    }

    chunk->program = program;
    program->chunks[program->chunk_count++] = *chunk;
    memset(chunk, 0, sizeof(*chunk));
    return 1;
}

static int compile_program_function(void* data, ProcStmt* proc, char* error, size_t error_size,
                                    int* function_index_out);

static int append_function(BytecodeProgram* program, BytecodeFunction* function, char* error,
                           size_t error_size, int* function_index_out) {
    if (!ensure_function_capacity(program)) {
        set_program_error(error, error_size, "Out of memory while storing compiled VM functions.");
        return 0;
    }

    function->chunk.program = program;
    program->functions[program->function_count] = *function;
    if (function_index_out != NULL) {
        *function_index_out = program->function_count;
    }
    program->function_count++;
    memset(function, 0, sizeof(*function));
    return 1;
}

static int compile_program_function(void* data, ProcStmt* proc, char* error, size_t error_size,
                                    int* function_index_out) {
    BytecodeProgram* program = data;
    BytecodeFunction function;

    memset(&function, 0, sizeof(function));
    bytecode_chunk_init(&function.chunk);

    function.param_count = proc->param_count;
    if (function.param_count < 0 || function.param_count > VM_ARTIFACT_MAX_PARAMS ||
        function.param_count > VM_ARTIFACT_MAX_LOCALS ||
        (size_t)function.param_count > SIZE_MAX / sizeof(char*)) {
        set_program_error(error, error_size, "Function has too many parameters.");
        bytecode_chunk_free(&function.chunk);
        return 0;
    }
    if (function.param_count > 0) {
        function.params = SAGE_ALLOC((size_t)function.param_count * sizeof(char*));
        memset(function.params, 0, (size_t)function.param_count * sizeof(char*));

        for (int i = 0; i < function.param_count; i++) {
            function.params[i] = dup_text(proc->params[i].start, (size_t)proc->params[i].length);
            if (function.params[i] == NULL) {
                for (int j = 0; j < i; j++) {
                    free(function.params[j]);
                }
                free(function.params);
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Out of memory while copying function parameter name.");
                return 0;
            }
        }
    }

    if (!bytecode_compile_function_body(&function.chunk, proc->body,
                                        function.params, function.param_count,
                                        compile_program_function, program,
                                        error, error_size)) {
        for (int i = 0; i < function.param_count; i++) {
            free(function.params[i]);
        }
        free(function.params);
        bytecode_chunk_free(&function.chunk);
        return 0;
    }

    return append_function(program, &function, error, error_size, function_index_out);
}

static Stmt* parse_program(const char* source, const char* input_path) {
    init_lexer(source, input_path);
    parser_init();

    Stmt* head = NULL;
    Stmt* tail = NULL;
    while (1) {
        Stmt* stmt = parse();
        if (stmt == NULL) {
            break;
        }

        if (head == NULL) {
            head = stmt;
        } else {
            tail->next = stmt;
        }
        tail = stmt;
    }

    return head;
}

static char hex_digit(int value) {
    return (char)(value < 10 ? ('0' + value) : ('a' + (value - 10)));
}

static int write_hex_line(FILE* out, const uint8_t* bytes, size_t byte_count) {
    for (size_t i = 0; i < byte_count; i++) {
        unsigned int value = bytes[i];
        if (fputc(hex_digit((int)((value >> 4) & 0xf)), out) == EOF ||
            fputc(hex_digit((int)(value & 0xf)), out) == EOF) {
            return 0;
        }
    }
    return fputc('\n', out) != EOF;
}

static int parse_nonnegative_int(const char* text, int* out) {
    if (text == NULL || out == NULL) return 0;
    char* end = NULL;
    errno = 0;
    long value = strtol(text, &end, 10);
    if (end == text || *end != '\0' || errno == ERANGE ||
        value < 0 || value > 0x7fffffffL) {
        return 0;
    }
    *out = (int)value;
    return 1;
}

static int parse_double_value(const char* text, double* out) {
    char* end = NULL;
    double value = strtod(text, &end);
    if (end == text || *end != '\0') {
        return 0;
    }
    *out = value;
    return 1;
}

static int hex_value(int ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
    if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
    return -1;
}

static int decode_hex_line(const char* hex, size_t byte_count, uint8_t* out) {
    if (hex == NULL || (byte_count > 0 && out == NULL) || byte_count > SIZE_MAX / 2) {
        return 0;
    }
    size_t expected_length = byte_count * 2;
    if (strlen(hex) != expected_length) {
        return 0;
    }

    for (size_t i = 0; i < byte_count; i++) {
        int high = hex_value((unsigned char)hex[i * 2]);
        int low = hex_value((unsigned char)hex[i * 2 + 1]);
        if (high < 0 || low < 0) {
            return 0;
        }
        out[i] = (uint8_t)((high << 4) | low);
    }

    return 1;
}

static int read_trimmed_line(FILE* file, char** line, size_t* capacity) {
    if (file == NULL || line == NULL || capacity == NULL) return 0;
    errno = 0;
    ssize_t line_len = getline(line, capacity, file);
    if (line_len < 0) return 0;
    if ((uintmax_t)line_len > (uintmax_t)SAGE_MAX_READ_SIZE * 2u + 4096u) {
        errno = EOVERFLOW;
        return 0;
    }
    if (strlen(*line) != (size_t)line_len) {
        errno = EOVERFLOW;
        return 0;
    }

    while (line_len > 0 && ((*line)[line_len - 1] == '\n' || (*line)[line_len - 1] == '\r')) {
        (*line)[--line_len] = '\0';
    }
    return 1;
}

static int write_chunk_constants(FILE* out, const BytecodeChunk* chunk, char* error, size_t error_size) {
    if (fprintf(out, "constants %d\n", chunk->constant_count) < 0) {
        return 0;
    }

    for (int i = 0; i < chunk->constant_count; i++) {
        Value constant = chunk->constants[i];
        if (IS_NUMBER(constant)) {
            if (fprintf(out, "number %.17g\n", AS_NUMBER(constant)) < 0) {
                return 0;
            }
        } else if (IS_STRING(constant)) {
            size_t string_len = strlen(AS_STRING(constant));
            if (fprintf(out, "string %zu\n", string_len) < 0 ||
                !write_hex_line(out, (const uint8_t*)AS_STRING(constant), string_len)) {
                return 0;
            }
        } else {
            set_program_error(error, error_size,
                              "Compiled VM artifacts only support number/string constants.");
            return 0;
        }
    }

    return 1;
}

static int write_chunk_payload(FILE* out, const BytecodeChunk* chunk, const char* end_marker,
                               char* error, size_t error_size) {
    if (!write_chunk_constants(out, chunk, error, error_size)) {
        return 0;
    }

    return fprintf(out, "code %d\n", chunk->code_count) >= 0 &&
           write_hex_line(out, chunk->code, (size_t)chunk->code_count) &&
           fprintf(out, "%s\n", end_marker) >= 0;
}

static int read_chunk_constants(FILE* file, BytecodeChunk* chunk, char** line, size_t* line_capacity,
                                char* error, size_t error_size) {
    if (!read_trimmed_line(file, line, line_capacity) || strncmp(*line, "constants ", 10) != 0) {
        set_program_error(error, error_size, "Missing constant table in VM artifact.");
        return 0;
    }

    int constant_count = 0;
    if (!parse_nonnegative_int(*line + 10, &constant_count) ||
        constant_count > VM_ARTIFACT_MAX_CONSTANTS) {
        set_program_error(error, error_size, "Invalid constant count in VM artifact.");
        return 0;
    }

    for (int i = 0; i < constant_count; i++) {
        if (!read_trimmed_line(file, line, line_capacity)) {
            set_program_error(error, error_size, "Unexpected EOF while reading constants.");
            return 0;
        }

        if (strncmp(*line, "number ", 7) == 0) {
            double value = 0.0;
            if (!parse_double_value(*line + 7, &value) ||
                !append_constant(chunk, val_number(value))) {
                set_program_error(error, error_size, "Invalid number constant in VM artifact.");
                return 0;
            }
            continue;
        }

        if (strncmp(*line, "string ", 7) == 0) {
            int string_len = 0;
            if (!parse_nonnegative_int(*line + 7, &string_len) ||
                string_len > SAGE_MAX_READ_SIZE || (size_t)string_len == SIZE_MAX) {
                set_program_error(error, error_size, "Invalid string length in VM artifact.");
                return 0;
            }

            if (!read_trimmed_line(file, line, line_capacity)) {
                set_program_error(error, error_size, "Unexpected EOF while reading string constant.");
                return 0;
            }

            char* decoded = SAGE_ALLOC((size_t)string_len + 1);
            if (decoded == NULL) {
                set_program_error(error, error_size, "Out of memory while reading string constant.");
                return 0;
            }

            if (!decode_hex_line(*line, (size_t)string_len, (uint8_t*)decoded)) {
                free(decoded);
                set_program_error(error, error_size, "Invalid string constant payload in VM artifact.");
                return 0;
            }
            decoded[string_len] = '\0';

            if (!append_constant(chunk, val_string_take(decoded))) {
                set_program_error(error, error_size, "Out of memory while storing string constant.");
                return 0;
            }
            continue;
        }

        set_program_error(error, error_size, "Unknown constant entry in VM artifact.");
        return 0;
    }

    return 1;
}

static int read_code_payload(FILE* file, BytecodeChunk* chunk, char** line, size_t* line_capacity,
                             const char* end_marker, char* error, size_t error_size) {
    if (!read_trimmed_line(file, line, line_capacity) || strncmp(*line, "code ", 5) != 0) {
        set_program_error(error, error_size, "Missing bytecode payload in VM artifact.");
        return 0;
    }

    int code_count = 0;
    if (!parse_nonnegative_int(*line + 5, &code_count) ||
        code_count > VM_ARTIFACT_MAX_CODE_BYTES ||
        !ensure_code_capacity(chunk, code_count)) {
        set_program_error(error, error_size, "Invalid code size in VM artifact.");
        return 0;
    }

    if (!read_trimmed_line(file, line, line_capacity)) {
        set_program_error(error, error_size, "Unexpected EOF while reading bytecode payload.");
        return 0;
    }

    if (!decode_hex_line(*line, (size_t)code_count, chunk->code)) {
        set_program_error(error, error_size, "Invalid bytecode payload in VM artifact.");
        return 0;
    }

    chunk->code_count = code_count;
    for (int i = 0; i < code_count; i++) {
        chunk->lines[i] = 0;
        chunk->columns[i] = 0;
    }

    if (!read_trimmed_line(file, line, line_capacity) || strcmp(*line, end_marker) != 0) {
        set_program_error(error, error_size, "Missing VM artifact end marker.");
        return 0;
    }

    return 1;
}

void bytecode_program_init(BytecodeProgram* program) {
    if (program != NULL) memset(program, 0, sizeof(*program));
}

void bytecode_program_free(BytecodeProgram* program) {
    if (program == NULL) return;
    if (program->chunk_count < 0 || program->function_count < 0 ||
        program->chunk_count > program->chunk_capacity ||
        program->function_count > program->function_capacity ||
        (program->chunk_count > 0 && program->chunks == NULL) ||
        (program->function_count > 0 && program->functions == NULL)) {
        memset(program, 0, sizeof(*program));
        return;
    }
    for (int i = 0; i < program->chunk_count; i++) {
        bytecode_chunk_free(&program->chunks[i]);
    }
    free(program->chunks);

    for (int i = 0; i < program->function_count; i++) {
        BytecodeFunction* function = &program->functions[i];
        if (function->param_count > 0 && function->params != NULL) {
            for (int j = 0; j < function->param_count; j++) free(function->params[j]);
        }
        free(function->params);
        bytecode_chunk_free(&function->chunk);
    }
    free(program->functions);

    memset(program, 0, sizeof(*program));
}

int bytecode_compile_program(BytecodeProgram* program, Stmt* statements, BytecodeCompileMode mode,
                             char* error, size_t error_size) {
    gc_pin();
    if (error != NULL && error_size > 0) {
        error[0] = '\0';
    }

    for (Stmt* stmt = statements; stmt != NULL; stmt = stmt->next) {
        BytecodeChunk chunk;
        bytecode_chunk_init(&chunk);

        if (!bytecode_compile_statement_with_functions(&chunk, stmt, mode,
                                                      mode == BYTECODE_COMPILE_STRICT ? compile_program_function : NULL,
                                                      program,
                                                      error, error_size)) {
            bytecode_chunk_free(&chunk);
            gc_unpin();
            return 0;
        }

        if (!append_chunk(program, &chunk, error, error_size)) {
            bytecode_chunk_free(&chunk);
            gc_unpin();
            return 0;
        }
    }

    gc_unpin();
    return 1;
}

int bytecode_program_write_file(const BytecodeProgram* program, const char* output_path,
                                char* error, size_t error_size) {
    if (program == NULL || output_path == NULL ||
        !bytecode_program_validate(program, error, error_size)) {
        if (error != NULL && error_size > 0 && error[0] == '\0') {
            set_program_error(error, error_size, "Invalid VM program.");
        }
        return 0;
    }
    FILE* out = fopen(output_path, "wb");
    if (out == NULL) {
        if (error != NULL && error_size > 0) {
            snprintf(error, error_size, "Could not open \"%s\": %s", output_path, strerror(errno));
        }
        return 0;
    }

    int ok = fprintf(out, "SAGEBC1\nfunctions %d\n", program->function_count) >= 0;
    for (int i = 0; ok && i < program->function_count; i++) {
        const BytecodeFunction* function = &program->functions[i];
        ok = fprintf(out, "function\nparams %d\n", function->param_count) >= 0;
        for (int j = 0; ok && j < function->param_count; j++) {
            size_t param_len = strlen(function->params[j]);
            ok = fprintf(out, "param %zu\n", param_len) >= 0 &&
                 write_hex_line(out, (const uint8_t*)function->params[j], param_len);
        }
        if (ok) {
            ok = write_chunk_payload(out, &function->chunk, "endfunction", error, error_size);
        }
    }

    if (ok) {
        ok = fprintf(out, "chunks %d\n", program->chunk_count) >= 0;
    }
    for (int i = 0; ok && i < program->chunk_count; i++) {
        ok = fprintf(out, "chunk\n") >= 0 &&
             write_chunk_payload(out, &program->chunks[i], "endchunk", error, error_size);
    }

    if (fclose(out) != 0) {
        ok = 0;
    }

    if (!ok && error != NULL && error_size > 0 && error[0] == '\0') {
        snprintf(error, error_size, "Could not write compiled VM artifact \"%s\".", output_path);
    }

    return ok;
}

int bytecode_program_read_file(BytecodeProgram* program, const char* input_path,
                               char* error, size_t error_size) {
    if (program == NULL || input_path == NULL) {
        set_program_error(error, error_size, "Invalid VM artifact arguments.");
        return 0;
    }
    if (error != NULL && error_size > 0) error[0] = '\0';
    gc_pin();
    FILE* file = fopen(input_path, "rb");
    char* line = NULL;
    size_t line_capacity = 0;
    int ok = 0;

    if (file == NULL) {
        if (error != NULL && error_size > 0) {
            snprintf(error, error_size, "Could not open \"%s\": %s", input_path, strerror(errno));
        }
        gc_unpin();
        return 0;
    }

    if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "SAGEBC1") != 0) {
        set_program_error(error, error_size, "Invalid VM artifact header.");
        goto cleanup;
    }

    if (!read_trimmed_line(file, &line, &line_capacity)) {
        set_program_error(error, error_size, "Unexpected EOF while reading VM artifact.");
        goto cleanup;
    }

    if (strncmp(line, "functions ", 10) == 0) {
        int function_count = 0;
        if (!parse_nonnegative_int(line + 10, &function_count) ||
            function_count > VM_ARTIFACT_MAX_FUNCTIONS) {
            set_program_error(error, error_size, "Invalid function count in VM artifact.");
            goto cleanup;
        }

        for (int i = 0; i < function_count; i++) {
            BytecodeFunction function;
            memset(&function, 0, sizeof(function));
            bytecode_chunk_init(&function.chunk);

            if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "function") != 0) {
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Invalid function marker in VM artifact.");
                goto cleanup;
            }

            if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "params ", 7) != 0) {
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Missing function parameter table in VM artifact.");
                goto cleanup;
            }

            if (!parse_nonnegative_int(line + 7, &function.param_count) ||
                function.param_count > VM_ARTIFACT_MAX_PARAMS ||
                function.param_count > VM_ARTIFACT_MAX_LOCALS ||
                (size_t)function.param_count > SIZE_MAX / sizeof(char*)) {
                bytecode_chunk_free(&function.chunk);
                set_program_error(error, error_size, "Invalid function parameter count in VM artifact.");
                goto cleanup;
            }

            if (function.param_count > 0) {
                function.params = SAGE_ALLOC((size_t)function.param_count * sizeof(char*));
                if (function.params == NULL) {
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Out of memory while reading function parameters.");
                    goto cleanup;
                }
                memset(function.params, 0, (size_t)function.param_count * sizeof(char*));
            }

            for (int j = 0; j < function.param_count; j++) {
                int param_len = 0;
                if (!read_trimmed_line(file, &line, &line_capacity) || strncmp(line, "param ", 6) != 0 ||
                    !parse_nonnegative_int(line + 6, &param_len) ||
                    param_len > SAGE_MAX_READ_SIZE || (size_t)param_len == SIZE_MAX) {
                    for (int k = 0; k < j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Invalid function parameter entry in VM artifact.");
                    goto cleanup;
                }

                if (!read_trimmed_line(file, &line, &line_capacity)) {
                    for (int k = 0; k < j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Unexpected EOF while reading function parameter.");
                    goto cleanup;
                }

                function.params[j] = SAGE_ALLOC((size_t)param_len + 1);
                if (function.params[j] == NULL) {
                    for (int k = 0; k < j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Out of memory while reading function parameter.");
                    goto cleanup;
                }

                if (!decode_hex_line(line, (size_t)param_len, (uint8_t*)function.params[j])) {
                    for (int k = 0; k <= j; k++) free(function.params[k]);
                    free(function.params);
                    bytecode_chunk_free(&function.chunk);
                    set_program_error(error, error_size, "Invalid function parameter payload in VM artifact.");
                    goto cleanup;
                }
                function.params[j][param_len] = '\0';
            }

            if (!read_chunk_constants(file, &function.chunk, &line, &line_capacity, error, error_size) ||
                !read_code_payload(file, &function.chunk, &line, &line_capacity, "endfunction",
                                   error, error_size) ||
                !append_function(program, &function, error, error_size, NULL)) {
                for (int j = 0; j < function.param_count; j++) free(function.params[j]);
                free(function.params);
                bytecode_chunk_free(&function.chunk);
                goto cleanup;
            }
        }

        if (!read_trimmed_line(file, &line, &line_capacity)) {
            set_program_error(error, error_size, "Unexpected EOF while reading chunk table.");
            goto cleanup;
        }
    }

    if (strncmp(line, "chunks ", 7) != 0) {
        set_program_error(error, error_size, "Missing chunk table in VM artifact.");
        goto cleanup;
    }

    int chunk_count = 0;
    if (!parse_nonnegative_int(line + 7, &chunk_count) ||
        chunk_count > VM_ARTIFACT_MAX_CHUNKS) {
        set_program_error(error, error_size, "Invalid chunk count in VM artifact.");
        goto cleanup;
    }

    for (int i = 0; i < chunk_count; i++) {
        BytecodeChunk chunk;
        bytecode_chunk_init(&chunk);

        if (!read_trimmed_line(file, &line, &line_capacity) || strcmp(line, "chunk") != 0) {
            bytecode_chunk_free(&chunk);
            set_program_error(error, error_size, "Invalid chunk marker in VM artifact.");
            goto cleanup;
        }

        if (!read_chunk_constants(file, &chunk, &line, &line_capacity, error, error_size) ||
            !read_code_payload(file, &chunk, &line, &line_capacity, "endchunk", error, error_size) ||
            !append_chunk(program, &chunk, error, error_size)) {
            bytecode_chunk_free(&chunk);
            goto cleanup;
        }
    }

    errno = 0;
    if (read_trimmed_line(file, &line, &line_capacity)) {
        set_program_error(error, error_size, "Unexpected trailing data in VM artifact.");
        goto cleanup;
    }
    if (ferror(file) || errno != 0) {
        set_program_error(error, error_size, "Error reading VM artifact.");
        goto cleanup;
    }
    if (!bytecode_program_validate(program, error, error_size)) goto cleanup;

    ok = 1;

 cleanup:
    free(line);
    fclose(file);
    if (!ok) {
        bytecode_program_free(program);
    }
    gc_unpin();
    return ok;
}

int compile_source_to_vm_artifact(const char* source, const char* input_path, const char* output_path,
                                  int opt_level, int debug_info) {
    BytecodeProgram program;
    char error[256];
    Stmt* ast = parse_program(source, input_path);
    bytecode_program_init(&program);

    if (opt_level > 0) {
        PassContext pass_ctx;
        pass_ctx.opt_level = opt_level;
        pass_ctx.debug_info = debug_info;
        pass_ctx.verbose = 0;
        pass_ctx.input_path = input_path;
        ast = run_passes(ast, &pass_ctx);
    }

    if (!bytecode_compile_program(&program, ast, BYTECODE_COMPILE_STRICT, error, sizeof(error))) {
        fprintf(stderr, "VM compile error: %s\n", error[0] ? error : "unknown error");
        bytecode_program_free(&program);
        free_stmt(ast);
        return 0;
    }

    if (!bytecode_program_write_file(&program, output_path, error, sizeof(error))) {
        fprintf(stderr, "VM artifact error: %s\n", error[0] ? error : "unknown error");
        bytecode_program_free(&program);
        free_stmt(ast);
        return 0;
    }

    bytecode_program_free(&program);
    free_stmt(ast);
    return 1;
}
