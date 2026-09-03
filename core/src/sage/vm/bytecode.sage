# ============================================================================
# Bytecode VM - Compact production execution
# ============================================================================
# Tier 1: Bytecode VM
# Purpose: general-purpose production execution, lower memory usage,
# faster dispatch, compact deployment, embedded baseline
# ============================================================================

import runtime.context as context
import runtime.values as values
import runtime.frames as frames
import runtime.control as control
import runtime.errors as errors
import ir.builder as ir_builder
import ir.slots as ir_slots
import interpreter.unwind as unwind
import interpreter.generators as generators

# Bytecode instruction types (compact encoding)
let BC_NOP = 0
let BC_LOAD_CONST = 1
let BC_LOAD_LOCAL = 2
let BC_STORE_LOCAL = 3
let BC_LOAD_GLOBAL = 4
let BC_STORE_GLOBAL = 5
let BC_BINARY_OP = 6
let BC_RETURN = 7
let BC_JUMP = 8
let BC_JUMP_IF_FALSE = 9
let BC_GET_PROP = 10
let BC_SET_PROP = 11
let BC_GET_INDEX = 12
let BC_SET_INDEX = 13
let BC_BUILD_ARRAY = 14
let BC_BUILD_DICT = 15
let BC_THROW = 16
let BC_CALL = 17
let BC_YIELD = 18
let BC_PUSH_DEFER = 19
let BC_POP_DEFER = 20
let BC_PUSH_TRY = 21
let BC_POP_TRY = 22

# Bytecode instruction
class Bytecode_Instr {
    let opcode: Int
    let dest: Int
    let operands: Array<Int>  // Mostly slot indices, compact encoding
    let constants: Array<Value>  // Embedded constants (for immediates)
    let source_loc: SourceLocation  // Source location
}

# Bytecode module
class Bytecode_Artifact {
    let name: String
    let instructions: Array<Bytecode_Instr>
    let constants: Array<Value>
    let num_slots: Int          // Number of local slots needed
    let source_map: Dict<Int, String>  // PC offset -> source location
    let function_ids: Dict<Int, String>  // Block/function IDs
}

# Compile IR module to bytecode
proc compile_ir_to_bytecode(module: IR_Module): Bytecode_Artifact =
    // Compact bytecode compilation from IR
    let instructions = []
    let constants = []
    let num_slots = 0
    let source_map = {} as Dict<Int, String>
    
    // Walk functions and compile
    for func in module.functions:
        let func_bytecode = compile_function(func)
        instructions = instructions.concat(func_bytecode.instructions)
        constants = constants.concat(func_bytecode.constants)
        num_slots = max(num_slots, func_bytecode.num_slots)
        // ... source map
    
    return Bytecode_Artifact(
        name: module.name,
        instructions: instructions,
        constants: constants,
        num_slots: num_slots,
        source_map: source_map,
        function_ids: {} as Dict<Int, String>
    )

# Compile IR function to bytecode
proc compile_function(func: IR_Function): Bytecode_Artifact_Inner =
    let instructions = []
    let constants = []
    let num_slots = func.local_count
    
    // Walk blocks and compile
    for block in func.blocks:
        let block_result = compile_block(func, block)
        instructions = instructions.concat(block_result.instructions)
        constants = constants.concat(block_result.constants)
    
    return Bytecode_Artifact_Inner(
        instructions: instructions,
        constants: constants,
        num_slots: num_slots
    )

# Compile block
proc compile_block(func: IR_Function, block: IR_Block): Bytecode_Block =
    let instructions = []
    let pc_offset = 0
    
    for instr in block.instructions:
        let bc_result = compile_instruction(func, instr)
        instructions = instructions.push(bc_result.instruction)
        if bc_result.new_constants != None:
            constants = constants.concat(bc_result.new_constants)
        // Update source map
        source_map[pc_offset] = instr.source_loc.to_string()
        pc_offset = pc_offset + 1
    
    return Bytecode_Block(
        instructions: instructions,
        num_slots: num_slots
    )

# Compile IR instruction to bytecode
proc compile_instruction(func: IR_Function, instr: IR_Instr): Bytecode_Compile_Result =
    match instr.opcode:
        IR_LOAD_CONST:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_LOAD_CONST,
                    dest: instr.dest,
                    operands: [],
                    constants: [instr.operands[0]],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_LOAD_LOCAL:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_LOAD_LOCAL,
                    dest: instr.dest,
                    operands: [instr.operands[0]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_STORE_LOCAL:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_STORE_LOCAL,
                    dest: instr.dest,
                    operands: [instr.operands[0]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_BINARY_OP:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_BINARY_OP,
                    dest: instr.dest,
                    operands: [instr.operands[0], instr.operands[1]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_CALL:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_CALL,
                    dest: instr.dest,
                    operands: [instr.operands[0], instr.operands[1]],
                    constants: slice(instr.operands, 2),
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_RETURN:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_RETURN,
                    dest: instr.dest,
                    operands: [instr.operands[0]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_JUMP:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_JUMP,
                    dest: 0,
                    operands: [instr.operands[0]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_JUMP_IF_FALSE:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_JUMP_IF_FALSE,
                    dest: 0,
                    operands: [instr.operands[0], instr.operands[1]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_GET_PROP:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_GET_PROP,
                    dest: instr.dest,
                    operands: [instr.operands[0], instr.operands[1]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_THROW:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_THROW,
                    dest: instr.dest,
                    operands: [instr.operands[0]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        IR_YIELD:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(
                    opcode: BC_YIELD,
                    dest: instr.dest,
                    operands: [instr.operands[0]],
                    constants: [],
                    source_loc: instr.source_loc
                ),
                new_constants: None
            )
        _:
            return Bytecode_Compile_Result(
                instruction: Bytecode_Instr(opcode: BC_NOP, dest: 0, operands: [], constants: [], source_loc: instr.source_loc),
                new_constants: None
            )

# ============================================================================
# Bytecode VM Structures
# ============================================================================

# Bytecode result from operation
class Bytecode_Compile_Result {
    let instruction: Bytecode_Instr
    let new_constants: Option<Array<Value>>
}

# Bytecode block result
class Bytecode_Block {
    let instructions: Array<Bytecode_Instr>
    let num_slots: Int
}

# Execute bytecode
proc execute_bytecode(ctx: InterpreterContext, bytecode: Bytecode_Artifact): Value =
    context.set_runtime_tier(ctx, "bytecode")
    
    // Initialize frame
    let module_func = make_module_function(bytecode.name)
    let frame = frames.new_frame(
        function_id: module_func.function_id,
        function: module_func,
        ip: 0,
        slot_count: bytecode.num_slots,
        source_loc: SourceLocation(bytecode.name, 1, 1)
    )
    
    context.push_frame(ctx, frame)
    
    // Execute bytecode
    let result = execute_bytecode_block(ctx, frame, bytecode)
    
    context.pop_frame(ctx)
    
    return result

# Execute bytecode block
proc execute_bytecode_block(ctx: InterpreterContext, frame: CallFrame, bytecode: Bytecode_Artifact): Value =
    let instructions = bytecode.instructions
    let pc = 0
    
    while pc < len(instructions):
        // Check step limit
        if not context.increment_steps(ctx):
            raise errors.ResourceLimitError("Step limit exceeded")
        
        let instr = instructions[pc]
        pc = pc + 1
        
        let result = execute_bytecode_instr(ctx, frame, instr)
        
        if result.kind != control.CF_NORMAL:
            return handle_control_flow(ctx, frame, result)
    
    return values.nil

# Execute single bytecode instruction
proc execute_bytecode_instr(ctx: InterpreterContext, frame: CallFrame, instr: Bytecode_Instr): ControlResult =
    match instr.opcode:
        BC_NOP:
            return control.result_normal(values.nil)
        BC_LOAD_CONST:
            frames.slot_store(frame, instr.dest, instr.constants[0])
            return control.result_normal(values.nil)
        BC_LOAD_LOCAL:
            let val = frames.slot_load(frame, instr.operands[0])
            frames.slot_store(frame, instr.dest, val)
            return control.result_normal(values.nil)
        BC_STORE_LOCAL:
            let val = frames.slot_load(frame, instr.operands[0])
            frames.slot_store(frame, instr.dest, val)
            return control.result_normal(values.nil)
        BC_BINARY_OP:
            let lhs = frames.slot_load(frame, instr.operands[0])
            let rhs = frames.slot_load(frame, instr.operands[1])
            let op = get_binary_op_name(instr.opcode)
            let result = context.runtime_binary(ctx, op, lhs, rhs)
            frames.slot_store(frame, instr.dest, result)
            return control.result_normal(values.nil)
        BC_RETURN:
            let val = frames.slot_load(frame, instr.operands[0])
            return ControlResult(kind: control.CF_RETURN, value: val, target: None)
        BC_JUMP:
            return control.result_normal(values.nil)  // IP updated by caller
        BC_JUMP_IF_FALSE:
            let cond = frames.slot_load(frame, instr.operands[0])
            let target = instr.operands[1]
            if not context.runtime_truthy(ctx, cond):
                // Jump handled externally
                pass
            return control.result_normal(values.nil)
        BC_GET_PROP:
            let obj = frames.slot_load(frame, instr.operands[0])
            let prop_name = values.value_to_string(frames.slot_load(frame, instr.operands[1]))
            let result = context.runtime_get_property(ctx, obj, prop_name)
            frames.slot_store(frame, instr.dest, result)
            return control.result_normal(values.nil)
        BC_SET_PROP:
            let obj = frames.slot_load(frame, instr.operands[0])
            let val = frames.slot_load(frame, instr.operands[1])
            let prop_name = values.value_to_string(frames.slot_load(frame, instr.operands[2]))
            context.runtime_set_property(ctx, obj, prop_name, val)
            return control.result_normal(values.nil)
        BC_THROW:
            let exception = frames.slot_load(frame, instr.operands[0])
            return ControlResult(kind: control.CF_THROW, value: exception, target: None)
        BC_CALL:
            let callee = frames.slot_load(frame, instr.operands[0])
            let arg_count = instr.operands[1]
            let args = []
            let i = 0
            while i < arg_count:
                args.push(frames.slot_load(frame, instr.operands[2 + i]))
                i = i + 1
            let result = context.runtime_call(ctx, callee, args, None)
            frames.slot_store(frame, instr.dest, result)
            return control.result_normal(values.nil)
        BC_YIELD:
            let val = frames.slot_load(frame, instr.operands[0])
            return generators.generator_yield(frame, val)
        BC_PUSH_DEFER:
            frames.push_defer(frame, instr.operands[0], frame.locals)
            return control.result_normal(values.nil)
        BC_POP_DEFER:
            frames.pop_defer(frame)
            return control.result_normal(values.nil)
        _:
            return control.result_normal(values.nil)

# Get binary op name from opcode
proc get_binary_op_name(opcode: Int): String =
    match opcode:
        BC_BINARY_OP: return "add"  // Default, actual op from slot or metadata
    return "add"

# Make module function for bytecode
proc make_module_function(name: String): Function =
    return Function(
        function_id: make_function_id(name),
        source_name: name,
        owner_class: None,
        params: [],
        defaults: [],
        body: nil as IR_Instr,
        closure: None,
        profile: FunctionProfile(
            function_id: make_function_id(name),
            call_count: 0,
            monomorphic: true,
            observed_types: {} as Dict<String, Int>,
            inline_cache: None,
            deopt_reason: None
        )
    )

# Make function ID
proc make_function_id(name: String): FunctionId =
    FunctionId(
        hash: name.hash(),
        source_name: name,
        owner_class: None,
        param_hash: 0,
        default_hash: 0
    )