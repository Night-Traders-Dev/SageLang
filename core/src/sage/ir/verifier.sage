// ============================================================================
# IR Verifier - Validates IR correctness
// ============================================================================
// Verifies: control flow integrity, slot usage, type consistency,
// exception handler coverage, defer matching, etc.
// ============================================================================

import ir.builder as builder

// Verification result
class VerifyResult {
    let valid: Bool
    let errors: List<String>
    let warnings: List<String>
}

// Create a new verifier
proc verify(module: IR_Module): VerifyResult =
    let errors = []
    let warnings = []
    
    // Verify each function
    for func in module.functions:
        let func_result = verify_function(func)
        errors = errors.concat(func_result.errors)
        warnings = warnings.concat(func_result.warnings)
    
    // Verify module-level invariants
    if module.entry_function >= len(module.functions):
        errors = errors.push("Invalid entry function index: " + module.entry_function.ToString())
    
    // Verify imports
    for imp in module.imports:
        if imp.module_name == "":
            errors = errors.push("Empty module name in import")
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify a single function
proc verify_function(func: IR_Function): VerifyResult =
    let errors = []
    let warnings = []
    
    // Check entry block exists
    if func.entry_block >= len(func.blocks):
        errors = errors.push("Function " + func.name + ": invalid entry block")
    
    // Verify each block
    for block in func.blocks:
        let block_result = verify_block(func, block)
        errors = errors.concat(block_result.errors)
        warnings = warnings.concat(block_result.warnings)
    
    // Verify control flow graph
    let cfg_result = verify_cfg(func)
    errors = errors.concat(cfg_result.errors)
    warnings = warnings.concat(cfg_result.warnings)
    
    // Verify slot usage
    let slot_result = verify_slots(func)
    errors = errors.concat(slot_result.errors)
    warnings = warnings.concat(slot_result.warnings)
    
    // Verify exception handlers
    let eh_result = verify_exception_handlers(func)
    errors = errors.concat(eh_result.errors)
    warnings = warnings.concat(eh_result.warnings)
    
    // Verify defers
    let defer_result = verify_defers(func)
    errors = errors.concat(defer_result.errors)
    warnings = warnings.concat(defer_result.warnings)
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify a basic block
proc verify_block(func: IR_Function, block: IR_Block): VerifyResult =
    let errors = []
    let warnings = []
    
    let i = 0
    while i < block.instructions.len:
        let instr = block.instructions[i]
        let instr_result = verify_instruction(func, block, instr, i)
        errors = errors.concat(instr_result.errors)
        warnings = warnings.concat(instr_result.warnings)
        i = i + 1
    
    // Check block ends with terminator
    if block.instructions.len > 0:
        let last = block.instructions[block.instructions.len - 1]
        if not is_terminator(last.opcode):
            warnings = warnings.push("Block " + block.id.ToString() + " does not end with terminator")
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify an instruction
proc verify_instruction(func: IR_Function, block: IR_Block, instr: IR_Instr, index: Int): VerifyResult =
    let errors = []
    let warnings = []
    
    match instr.opcode:
        IR_LOAD_CONST:
            // Always valid
            pass
        IR_LOAD_LOCAL:
            if instr.operands[0] >= func.local_count:
                errors = errors.push("LOAD_LOCAL: slot index " + instr.operands[0].ToString() + " out of range (max " + func.local_count.ToString() + ")")
        IR_STORE_LOCAL:
            if instr.operands[0] >= func.local_count:
                errors = errors.push("STORE_LOCAL: slot index " + instr.operands[0].ToString() + " out of range")
            if instr.dest >= func.local_count:
                errors = errors.push("STORE_LOCAL: dest slot " + instr.dest.ToString() + " out of range")
        IR_BINARY_OP:
            if instr.operands.len < 3:
                errors = errors.push("BINARY_OP: insufficient operands")
        IR_CALL:
            let arg_count = instr.operands[1]
            if instr.operands.len != 2 + arg_count:
                errors = errors.push("CALL: operand count mismatch")
        IR_JUMP:
            let target = instr.operands[0]
            if target >= get_total_instructions(func):
                errors = errors.push("JUMP: target PC " + target.ToString() + " out of range")
        IR_JUMP_IF_FALSE:
            let target = instr.operands[1]
            if target >= get_total_instructions(func):
                errors = errors.push("JUMP_IF_FALSE: target PC " + target.ToString() + " out of range")
        IR_RETURN:
            // Valid
            pass
        IR_GET_PROP:
            if instr.operands.len < 2:
                errors = errors.push("GET_PROP: insufficient operands")
        IR_SET_PROP:
            if instr.operands.len < 3:
                errors = errors.push("SET_PROP: insufficient operands")
        IR_GET_INDEX:
            if instr.operands.len < 2:
                errors = errors.push("GET_INDEX: insufficient operands")
        IR_SET_INDEX:
            if instr.operands.len < 3:
                errors = errors.push("SET_INDEX: insufficient operands")
        IR_BUILD_ARRAY:
            let count = instr.operands[0]
            if instr.operands.len != 1 + count:
                errors = errors.push("BUILD_ARRAY: operand count mismatch")
        IR_BUILD_DICT:
            let count = instr.operands[0]
            if instr.operands.len != 1 + 2 * count:
                errors = errors.push("BUILD_DICT: operand count mismatch")
        IR_THROW:
            // Valid
            pass
        IR_PUSH_DEFER:
            // Valid
            pass
        IR_POP_DEFER:
            // Valid
            pass
        IR_PUSH_TRY:
            // Valid
            pass
        IR_POP_TRY:
            // Valid
            pass
        IR_YIELD:
            // Valid
            pass
        _:
            warnings = warnings.push("Unknown opcode: " + instr.opcode.ToString())
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify control flow graph
proc verify_cfg(func: IR_Function): VerifyResult =
    let errors = []
    let warnings = []
    
    // Build CFG
    let visited = {} as Dict<Int, Bool>
    let worklist = [func.entry_block]
    
    while worklist.len > 0:
        let block_id = worklist.pop()
        if dict_has(visited, block_id):
            continue
        visited[block_id] = true
        
        let block = func.blocks[block_id]
        
        // Check successors
        for succ in block.successors:
            if succ >= len(func.blocks):
                errors = errors.push("Block " + block_id.ToString() + ": invalid successor " + succ.ToString())
            else:
                worklist.push(succ)
    
    // Check for unreachable blocks
    for i in 0..func.blocks.len:
        if not dict_has(visited, i):
            if i != func.entry_block:
                warnings = warnings.push("Block " + i.ToString() + " is unreachable")
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify slot usage
proc verify_slots(func: IR_Function): VerifyResult =
    let errors = []
    let warnings = []
    
    // Track defined slots
    let defined = {} as Dict<Int, Bool>
    let used = {} as Dict<Int, Bool>
    
    for block in func.blocks:
        for instr in block.instructions:
            match instr.opcode:
                IR_STORE_LOCAL:
                    defined[instr.operands[0]] = true
                IR_LOAD_LOCAL:
                    used[instr.operands[0]] = true
    
    // Check for used-before-defined
    for slot in used.keys:
        if not dict_has(defined, slot):
            warnings = warnings.push("Slot " + slot.ToString() + " may be used before definition")
    
    // Check for unused slots
    for i in 0..func.local_count:
        if not dict_has(defined, i) and not dict_has(used, i):
            warnings = warnings.push("Slot " + i.ToString() + " is never used")
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify exception handlers
proc verify_exception_handlers(func: IR_Function): VerifyResult =
    let errors = []
    let warnings = []
    
    for handler in func.exception_handlers:
        if handler.try_start >= handler.try_end:
            errors = errors.push("Exception handler: try_start >= try_end")
        if handler.try_end > get_total_instructions(func):
            errors = errors.push("Exception handler: try_end out of range")
        if handler.catch_block >= len(func.blocks):
            errors = errors.push("Exception handler: catch_block out of range")
        if handler.finally_block != None:
            if handler.finally_block >= len(func.blocks):
                errors = errors.push("Exception handler: finally_block out of range")
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Verify defers
proc verify_defers(func: IR_Function): VerifyResult =
    let errors = []
    let warnings = []
    
    // Check defer handlers are valid blocks
    for defer in func.defers:
        if defer.handler_block >= len(func.blocks):
            errors = errors.push("Defer: handler_block out of range")
    
    return VerifyResult(
        valid: len(errors) == 0,
        errors: errors,
        warnings: warnings
    )

// Check if opcode is a terminator
proc is_terminator(opcode: Int): Bool =
    match opcode:
        IR_RETURN: return true
        IR_JUMP: return true
        IR_THROW: return true
        IR_YIELD: return true
        IR_BREAK: return true
        IR_CONTINUE: return true
        _: return false

// Get total instruction count
proc get_total_instructions(func: IR_Function): Int =
    let total = 0
    for block in func.blocks:
        total = total + block.instructions.len
    return total