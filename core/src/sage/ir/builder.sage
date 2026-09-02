// ============================================================================
# Sage IR - Intermediate Representation
// ============================================================================
// Shared production representation for bytecode, CPC, JIT, AOT
// Represents: lexical slots, calls, property/index ops, branches, loops,
// returns, break/continue, yield, throws, defer/finally, imports, source mappings
// ============================================================================

import ast
import runtime.values as values
import runtime.slots as slots

// IR Instruction types
let IR_NOP = 0
let IR_LOAD_CONST = 1
let IR_LOAD_LOCAL = 2
let IR_STORE_LOCAL = 3
let IR_LOAD_GLOBAL = 4
let IR_STORE_GLOBAL = 5
let IR_LOAD_CLOSURE = 6
let IR_STORE_CLOSURE = 7
let IR_BINARY_OP = 8
let IR_UNARY_OP = 9
let IR_CALL = 10
let IR_CALL_METHOD = 11
let IR_RETURN = 12
let IR_JUMP = 13
let IR_JUMP_IF_TRUE = 14
let IR_JUMP_IF_FALSE = 15
let IR_GET_PROP = 16
let IR_SET_PROP = 17
let IR_GET_INDEX = 18
let IR_SET_INDEX = 19
let IR_SLICE = 20
let IR_BUILD_ARRAY = 21
let IR_BUILD_DICT = 22
let IR_BUILD_TUPLE = 23
let IR_BUILD_CLOSURE = 24
let IR_GET_ITER = 25
let IR_NEXT = 26
let IR_YIELD = 27
let IR_YIELD_FROM = 28
let IR_THROW = 29
let IR_PUSH_DEFER = 30
let IR_POP_DEFER = 31
let IR_PUSH_TRY = 32
let IR_POP_TRY = 33
let IR_PUSH_FINALLY = 34
let IR_END_FINALLY = 35
let IR_BREAK = 36
let IR_CONTINUE = 37
let IR_IMPORT = 38
let IR_DEBUG_LINE = 39

// IR Instruction
class IR_Instr {
    let opcode: Int
    let dest: Int              // Destination slot
    let operands: Array<Value> // Operands (slot indices, constants, etc.)
    let op: String             // Operator name (for binary/unary)
    let source_loc: SourceLocation  // Source location for debugging
}

// IR Block (basic block)
class IR_Block {
    let id: Int
    let instructions: List<IR_Instr>
    let predecessors: List<Int>
    let successors: List<Int>
    let start_pc: Int
    let end_pc: Int
    let is_loop_header: Bool
    let is_exception_handler: Bool
}

// IR Function
class IR_Function {
    let function_id: FunctionId
    let name: String
    let params: Array<String>
    let param_slots: Array<Int>    // Slot indices for parameters
    let local_count: Int           // Total local slots needed
    let blocks: List<IR_Block>
    let entry_block: Int
    let exception_handlers: List<ExceptionHandler>
    let defers: List<DeferInfo>
}

// Exception handler in IR
class ExceptionHandler {
    let try_start: Int
    let try_end: Int
    let catch_var: String
    let catch_block: Int
    let finally_block: Option<Int>
}

// Defer info in IR
class DeferInfo {
    let handler_block: Int
    let scope_depth: Int
}

// IR Module
class IR_Module {
    let name: String
    let functions: List<IR_Function>
    let globals: Dict<String, Int>    // Global name -> slot
    let entry_function: Int           // Index of module entry function
    let imports: List<ImportInfo>
    let source_map: Dict<Int, SourceLocation>  // PC -> source location
}

// Import info
class ImportInfo {
    let module_name: String
    let items: List<(String, Option<String>)>  // (name, alias)
    let is_wildcard: Bool
}

// Slot info for IR
class IR_SlotInfo {
    let index: Int
    let name: String
    let scope: Int          // SCOPE_LOCAL, SCOPE_CLOSURE, SCOPE_GLOBAL, SCOPE_MODULE
    let captured: Bool
    let mutable: Bool
    let type_hint: Option<String>
}

// ============================================================================
# IR Builder - Builds IR from resolved AST
// ============================================================================

// Builder state
class IR_Builder {
    let resolved: ResolvedModule
    let functions: List<IR_Function>
    let current_function: Option<IR_Function>
    let current_block: Option<IR_Block>
    let next_block_id: Int
    let next_instr_id: Int
    let slot_allocator: SlotAllocator
    let errors: List<String>
}

// Slot allocator for IR
class SlotAllocator {
    let next_slot: Int
    let slot_info: Dict<Int, IR_SlotInfo>
    
    proc init(): SlotAllocator = SlotAllocator(
        next_slot: 0,
        slot_info: {} as Dict<Int, IR_SlotInfo>
    )
    
    proc alloc(name: String, scope: Int, captured: Bool, mutable: Bool): Int =
        let idx = next_slot
        next_slot = next_slot + 1
        slot_info[idx] = IR_SlotInfo(
            index: idx,
            name: name,
            scope: scope,
            captured: captured,
            mutable: mutable,
            type_hint: None
        )
        return idx
    
    proc alloc_param(name: String): Int =
        return alloc(name, slots.SCOPE_LOCAL, false, true)
    
    proc alloc_local(name: String, captured: Bool): Int =
        return alloc(name, slots.SCOPE_LOCAL, captured, true)
    
    proc alloc_closure(name: String): Int =
        return alloc(name, slots.SCOPE_CLOSURE, true, true)
    
    proc alloc_global(name: String): Int =
        return alloc(name, slots.SCOPE_GLOBAL, false, true)
    
    proc get_slot_info(idx: Int): Option<IR_SlotInfo> =
        if dict_has(slot_info, idx):
            return Some(slot_info[idx])
        return None
}

// Create a new IR builder
proc builder_new(resolved: ResolvedModule): IR_Builder = IR_Builder(
    resolved: resolved,
    functions: [],
    current_function: None,
    current_block: None,
    next_block_id: 0,
    next_instr_id: 0,
    slot_allocator: SlotAllocator(),
    errors: []
)

// Build IR from resolved module
proc build_ir(resolved: ResolvedModule, ctx: InterpreterContext): IR_Module =
    let builder = builder_new(resolved)
    
    // Build module-level function
    let module_func = builder_build_module_function(builder, resolved)
    builder.functions = builder.functions.push(module_func)
    
    // Build other functions
    for func_name in resolved.function_map.keys:
        let func_id = resolved.function_map[func_name]
        // Build function IR
        // ...
    
    return IR_Module(
        name: resolved.ast.name or "main",
        functions: builder.functions,
        globals: builder_collect_globals(builder),
        entry_function: 0,
        imports: builder_collect_imports(builder),
        source_map: builder_collect_source_map(builder)
    )

// Build module-level function
proc builder_build_module_function(builder: IR_Builder, resolved: ResolvedModule): IR_Function =
    let slot_alloc = builder.slot_allocator
    let blocks = []
    let entry_block = builder_new_block(builder)
    
    // Allocate slots for module-level bindings
    // ...
    
    // Build statements
    builder.current_function = Some(IR_Function(...))
    builder.current_block = Some(entry_block)
    
    for stmt in resolved.ast.statements:
        builder_build_statement(builder, stmt)
    
    // Create module function
    return IR_Function(
        function_id: make_module_function_id(resolved.ast.name or "main"),
        name: resolved.ast.name or "main",
        params: [],
        param_slots: [],
        local_count: slot_alloc.next_slot,
        blocks: blocks,
        entry_block: 0,
        exception_handlers: [],
        defers: []
    )

// Build a statement
proc builder_build_statement(builder: IR_Builder, stmt: AST_Stmt): Unit =
    match stmt.kind:
        ast.STMT_EXPRESSION:
            builder_build_expression(builder, stmt.expr)
            // Pop result if not used
            builder_emit(builder, IR_NOP, 0, [])
        ast.STMT_LET:
            builder_build_let(builder, stmt)
        ast.STMT_IF:
            builder_build_if(builder, stmt)
        ast.STMT_WHILE:
            builder_build_while(builder, stmt)
        ast.STMT_FOR:
            builder_build_for(builder, stmt)
        ast.STMT_BLOCK:
            builder_build_block(builder, stmt)
        ast.STMT_RETURN:
            builder_build_return(builder, stmt)
        ast.STMT_BREAK:
            builder_emit(builder, IR_BREAK, 0, [])
        ast.STMT_CONTINUE:
            builder_emit(builder, IR_CONTINUE, 0, [])
        ast.STMT_TRY:
            builder_build_try(builder, stmt)
        ast.STMT_RAISE:
            builder_build_raise(builder, stmt)
        ast.STMT_YIELD:
            builder_build_yield(builder, stmt)
        ast.STMT_IMPORT:
            builder_build_import(builder, stmt)
        ast.STMT_DEFER:
            builder_build_defer(builder, stmt)
        ast.STMT_PROC:
            builder_build_proc(builder, stmt)
        ast.STMT_CLASS:
            builder_build_class(builder, stmt)
        _:
            builder.errors = builder.errors.push("Unknown statement type")

// Build let statement
proc builder_build_let(builder: IR_Builder, stmt: AST_Stmt): Unit =
    let value_slot = builder_build_expression(builder, stmt.init_expr)
    if stmt.resolved_binding != None:
        let binding = stmt.resolved_binding
        if binding.kind == resolver.BINDING_LOCAL:
            builder_emit(builder, IR_STORE_LOCAL, binding.slot_index, [value_slot])
        else if binding.kind == resolver.BINDING_CLOSURE:
            builder_emit(builder, IR_STORE_CLOSURE, binding.slot_index, [value_slot])
        else if binding.kind == resolver.BINDING_GLOBAL:
            builder_emit(builder, IR_STORE_GLOBAL, binding.slot_index, [value_slot])
    else:
        // Fallback to environment
        let name_slot = builder.slot_allocator.alloc_global(stmt.name)
        builder_emit(builder, IR_STORE_GLOBAL, name_slot, [value_slot])

// Build expression and return result slot
proc builder_build_expression(builder: IR_Builder, expr: AST_Expr): Int =
    let dest = builder.slot_allocator.alloc_local("tmp_" + builder.next_instr_id.ToString(), false)
    
    match expr.kind:
        ast.EXPR_NUMBER:
            builder_emit(builder, IR_LOAD_CONST, dest, [values.value_number(expr.value)])
        ast.EXPR_STRING:
            builder_emit(builder, IR_LOAD_CONST, dest, [values.value_string(expr.value)])
        ast.EXPR_BOOL:
            builder_emit(builder, IR_LOAD_CONST, dest, [if expr.value then values.true_val else values.false_val])
        ast.EXPR_NIL:
            builder_emit(builder, IR_LOAD_CONST, dest, [values.nil])
        ast.EXPR_VARIABLE:
            if expr.resolved_binding != None:
                let binding = expr.resolved_binding
                if binding.kind == resolver.BINDING_LOCAL:
                    builder_emit(builder, IR_LOAD_LOCAL, dest, [binding.slot_index])
                else if binding.kind == resolver.BINDING_CLOSURE:
                    builder_emit(builder, IR_LOAD_CLOSURE, dest, [binding.slot_index])
                else if binding.kind == resolver.BINDING_GLOBAL:
                    builder_emit(builder, IR_LOAD_GLOBAL, dest, [binding.slot_index])
            else:
                // Fallback
                let name_slot = builder.slot_allocator.alloc_global(expr.name)
                builder_emit(builder, IR_LOAD_GLOBAL, dest, [name_slot])
        ast.EXPR_BINARY:
            let lhs_slot = builder_build_expression(builder, expr.lhs)
            let rhs_slot = builder_build_expression(builder, expr.rhs)
            builder_emit(builder, IR_BINARY_OP, dest, [lhs_slot, rhs_slot, expr.op.kind])
        ast.EXPR_CALL:
            let callee_slot = builder_build_expression(builder, expr.callee)
            let arg_slots = []
            for arg in expr.args:
                arg_slots.push(builder_build_expression(builder, arg))
            builder_emit(builder, IR_CALL, dest, [callee_slot, len(arg_slots)] + arg_slots)
        ast.EXPR_GET:
            let obj_slot = builder_build_expression(builder, expr.object)
            builder_emit(builder, IR_GET_PROP, dest, [obj_slot, expr.property_name])
        ast.EXPR_INDEX:
            let obj_slot = builder_build_expression(builder, expr.object)
            let idx_slot = builder_build_expression(builder, expr.index)
            builder_emit(builder, IR_GET_INDEX, dest, [obj_slot, idx_slot])
        ast.EXPR_ARRAY:
            let elem_slots = []
            for elem in expr.elements:
                elem_slots.push(builder_build_expression(builder, elem))
            builder_emit(builder, IR_BUILD_ARRAY, dest, [len(elem_slots)] + elem_slots)
        ast.EXPR_DICT:
            let entry_slots = []
            for pair in expr.entries:
                let k = builder_build_expression(builder, pair.key)
                let v = builder_build_expression(builder, pair.value)
                entry_slots.push(k)
                entry_slots.push(v)
            builder_emit(builder, IR_BUILD_DICT, dest, [len(expr.entries)] + entry_slots)
        _:
            builder.errors = builder.errors.push("Unknown expression type")
    
    return dest

// Emit an instruction
proc builder_emit(builder: IR_Builder, opcode: Int, dest: Int, operands: Array<Value>): Int =
    let instr = IR_Instr(
        opcode: opcode,
        dest: dest,
        operands: operands,
        op: "",
        source_loc: SourceLocation("<unknown>", 0, 0, 0)
    )
    if builder.current_block != None:
        builder.current_block.instructions = builder.current_block.instructions.push(instr)
    builder.next_instr_id = builder.next_instr_id + 1
    return dest

// Create new basic block
proc builder_new_block(builder: IR_Builder): IR_Block =
    let block = IR_Block(
        id: builder.next_block_id,
        instructions: [],
        predecessors: [],
        successors: [],
        start_pc: 0,
        end_pc: 0,
        is_loop_header: false,
        is_exception_handler: false
    )
    builder.next_block_id = builder.next_block_id + 1
    if builder.current_function != None:
        builder.current_function.blocks = builder.current_function.blocks.push(block)
    return block

// Collect globals
proc builder_collect_globals(builder: IR_Builder): Dict<String, Int> =
    return {} as Dict<String, Int>

// Collect imports
proc builder_collect_imports(builder: IR_Builder): List<ImportInfo> =
    return []

// Collect source map
proc builder_collect_source_map(builder: IR_Builder): Dict<Int, SourceLocation> =
    return {} as Dict<Int, SourceLocation>

// Make module function ID
proc make_module_function_id(name: String): FunctionId =
    FunctionId(
        hash: name.hash(),
        source_name: name,
        owner_class: None,
        param_hash: 0,
        default_hash: 0
    )