# ============================================================================
# SageLang Runtime Orchestration Layer
# ============================================================================
# Thin orchestration layer that:
#   1. Creates InterpreterContext
#   2. Selects runtime profile
#   3. Invokes frontend
#   4. Builds or loads Sage IR
#   5. Selects execution tier
#   6. Runs the program
#   7. Normalizes diagnostics and results
# ============================================================================

import runtime.context as context
import runtime.values as values
import runtime.errors as errors
import frontend.lexer as lexer
import frontend.parser as parser
import frontend.resolver as resolver
import frontend.diagnostics as diagnostics
import interpreter.eval_expr as eval_expr
import interpreter.eval_stmt as eval_stmt
import interpreter.unwind as unwind
import interpreter.generators as generators
import ir.builder as ir_builder
import ir.verifier as ir_verifier
import vm.reference as reference_vm
import vm.bytecode as bytecode_vm

# CLI options structure
class CliOptions {
    let source_file: Option<String>
    let source_code: Option<String>
    let profile: String              // general, embedded, deterministic
    let tier: String                 // reference, bytecode, cpc, jit, aot
    let verify_parity: Bool
    let trace_runtime: Bool
    let dump_ir: Bool
    let dump_slots: Bool
    let dump_profile: Bool
    let dump_shapes: Bool
    let dump_frames: Bool
    let dump_capabilities: Bool
    let dump_deopt: Bool
    let max_steps: Int
    let output_file: Option<String>
}

# Parse command line arguments
proc parse_cli_args(args: Array<String>): CliOptions =
    let opts = CliOptions(
        source_file: None,
        source_code: None,
        profile: "general",
        tier: "reference",
        verify_parity: false,
        trace_runtime: false,
        dump_ir: false,
        dump_slots: false,
        dump_profile: false,
        dump_shapes: false,
        dump_frames: false,
        dump_capabilities: false,
        dump_deopt: false,
        max_steps: -1,
        output_file: None
    )
    
    let i = 0
    while i < len(args):
        let arg = args[i]
        match arg:
            "--profile":
                i = i + 1
                if i < len(args):
                    opts.profile = args[i]
            "--runtime":
                i = i + 1
                if i < len(args):
                    opts.tier = args[i]
            "--verify-parity":
                opts.verify_parity = true
            "--trace-runtime":
                opts.trace_runtime = true
            "--dump-ir":
                opts.dump_ir = true
            "--dump-slots":
                opts.dump_slots = true
            "--dump-profile":
                opts.dump_profile = true
            "--dump-shapes":
                opts.dump_shapes = true
            "--dump-frames":
                opts.dump_frames = true
            "--dump-capabilities":
                opts.dump_capabilities = true
            "--dump-deopt":
                opts.dump_deopt = true
            "--max-steps":
                i = i + 1
                if i < len(args):
                    opts.max_steps = args[i].toInt()
            "--output":
            "-o":
                i = i + 1
                if i < len(args):
                    opts.output_file = Some(args[i])
            "-c":
                i = i + 1
                if i < len(args):
                    opts.source_code = Some(args[i])
            "-e":
                i = i + 1
                if i < len(args):
                    opts.source_code = Some(args[i])
            _:
                if not arg.starts_with("-"):
                    opts.source_file = Some(arg)
        i = i + 1
    
    return opts

# Main entry point
proc run(opts: CliOptions): Int =
    // 1. Create InterpreterContext with selected profile
    let ctx = context.context_new(opts.profile)
    
    // Apply CLI options to context
    context.set_runtime_tier(ctx, opts.tier)
    context.set_flag(ctx, "trace", opts.trace_runtime)
    context.set_flag(ctx, "dump_ir", opts.dump_ir)
    context.set_flag(ctx, "dump_frames", opts.dump_frames)
    context.set_flag(ctx, "profiling", true)
    
    if opts.max_steps > 0:
        ctx.resource_limits.max_steps = opts.max_steps
    
    // 2. Load source
    let source: String
    let filename: String
    if opts.source_code != None:
        source = opts.source_code
        filename = "<cmdline>"
    else if opts.source_file != None:
        filename = opts.source_file
        source = file_read(filename)
    else:
        // REPL mode
        return run_repl(ctx)
    
    // 3. Set source in context for error reporting
    context.set_source(ctx, source, filename)
    
    // 4. Invoke frontend - Lexer
    let lexer_state = lexer.lexer_new(source)
    let tokens = lexer.lexer_run(lexer_state)
    let lex_diagnostics = lexer.lexer_get_diagnostics(lexer_state)
    
    // 5. Invoke frontend - Parser
    let parse_result = parser.parse(tokens, filename)
    let ast = parse_result.ast
    let parse_diagnostics = parse_result.diagnostics
    
    // 6. Invoke frontend - Semantic Analysis (Resolver)
    let resolver_state = resolver.resolver_new(ast)
    let resolved = resolver.resolver_run(resolver_state)
    let resolve_diagnostics = resolved.diagnostics
    
    // 7. Collect all diagnostics
    let all_diagnostics = []
    all_diagnostics = all_diagnostics.concat(lex_diagnostics)
    all_diagnostics = all_diagnostics.concat(parse_diagnostics)
    all_diagnostics = all_diagnostics.concat(resolve_diagnostics)
    
    // Check for errors
    if diagnostics.has_errors(all_diagnostics):
        diagnostics.print_diagnostics(all_diagnostics)
        return 1
    
    // Print warnings
    if diagnostics.has_warnings(all_diagnostics):
        diagnostics.print_diagnostics(all_diagnostics)
    
    // 8. Build or load Sage IR
    let ir_module: IR_Module
    if opts.tier == "reference":
        // Reference VM can work directly with AST
        ir_module = ir_builder.build_ir(resolved.ast, ctx)
    else:
        // Other tiers need IR
        ir_module = ir_builder.build_ir(resolved.ast, ctx)
        
        // Verify IR
        if context.get_flag(ctx, "verification"):
            let verify_result = ir_verifier.verify(ir_module)
            if not verify_result.valid:
                for err in verify_result.errors:
                    print "IR Verification Error: " + err
                return 1
    
    // 9. Dump IR if requested
    if opts.dump_ir:
        print "=== Sage IR ==="
        print ir_module.to_string()
    
    // 10. Select and run execution tier
    let result: Value
    match opts.tier:
        "reference":
            result = reference_vm.execute(ctx, ir_module)
        "bytecode":
            let bytecode = bytecode_vm.compile(ir_module)
            if opts.dump_bytecode:
                print "=== Bytecode ==="
                print bytecode.to_string()
            result = bytecode_vm.execute(ctx, bytecode)
        "cpc":
            // CPC optimizer
            let optimized = cpc_optimize(ctx, ir_module)
            if opts.dump_profile:
                print "=== CPC Profile ==="
                print optimized.profile.to_string()
            result = reference_vm.execute(ctx, optimized.ir)
        "jit":
            // JIT compilation
            result = jit_execute(ctx, ir_module)
        "aot":
            // AOT compilation
            result = aot_execute(ctx, ir_module)
        _:
            print "Unknown runtime tier: " + opts.tier
            return 1
    
    // 11. Handle result
    if result != values.nil:
        print values.value_to_string(result)
    
    // 12. Dump profiling info if requested
    if opts.dump_profile:
        print "=== Profile Data ==="
        print ctx.profiler.call_counts.to_string()
    
    if opts.dump_shapes:
        print "=== Shape Data ==="
        print ctx.profiler.shape_feedback.to_string()
    
    if opts.dump_capabilities:
        print "=== Capabilities ==="
        print ctx.host_capabilities.allowed.to_string()
    
    if opts.dump_deopt:
        print "=== Deoptimizations ==="
        // Print deopt reasons from profiles
        for func_id in ctx.function_profiles.keys:
            let profile = ctx.function_profiles[func_id]
            if profile.deopt_reason != None:
                print "  " + func_id.source_name + ": " + profile.deopt_reason
    
    // 13. Verify parity if requested
    if opts.verify_parity and opts.tier != "reference":
        let ref_ctx = context.context_new(opts.profile)
        context.set_runtime_tier(ref_ctx, "reference")
        let ref_result = reference_vm.execute(ref_ctx, ir_module)
        
        if not verify_parity(result, ref_result):
            print "PARITY MISMATCH!"
            print "  " + opts.tier + ": " + values.value_to_string(result)
            print "  reference: " + values.value_to_string(ref_result)
            return 2
    
    return 0

# REPL mode
proc run_repl(ctx: InterpreterContext, sandbox_mode: String = ""): Int =
    // Enable sandbox if sandbox_mode is set
    if sandbox_mode == "sandbox":
        let sandbox_config = sandbox.SandboxModeConfig(
            mode: sandbox.SANDBOX_MODE_STANDARD,
            enable_modules: true,
            enable_resources: true,
            enable_functions: true,
            enable_timeline: true,
            enable_errors: true,
            sample_rate: 1
        )
        ctx_module.interpreter_context_enable_sandbox(ctx, sandbox_config)
    
    print "Sage REPL (modular runtime)"
    print "Type :quit to exit, :help for commands"
    
    while true:
        print "sage> "
        let line = input()
        if line == ":quit" or line == "exit":
            break
        if line == ":help":
            print_repl_help()
            continue
        if line == "":
            continue
        
        // Execute line
        let opts = CliOptions(
            source_code: Some(line),
            profile: ctx.runtime_profile,
            tier: ctx.runtime_tier,
            verify_parity: false,
            trace_runtime: false,
            dump_ir: false,
            dump_slots: false,
            dump_profile: false,
            dump_shapes: false,
            dump_frames: false,
            dump_capabilities: false,
            dump_deopt: false,
            max_steps: -1,
            output_file: None,
            source_file: None
        )
        let result = run(opts)
        if result != 0:
            print "Error (code: " + result.ToString() + ")"
    
    print "Goodbye!"
    return 0

proc print_repl_help(): Unit =
    print "Commands:"
    print "  :quit, exit  - Exit REPL"
    print "  :help        - Show this help"
    print "  :ir          - Dump IR for last expression"
    print "  :ast         - Dump AST for last expression"
    print "  :tokens      - Dump tokens for last expression"

# Parity verification
proc verify_parity(result1: Value, result2: Value): Bool =
    // Compare values for parity
    return values.value_eq(result1, result2)

# CPC optimization (stub)
proc cpc_optimize(ctx: InterpreterContext, ir: IR_Module): OptimizedIR =
    // Profile-guided optimization
    // ...
    return OptimizedIR(ir: ir, profile: CpcProfile())

# JIT execution (stub)
proc jit_execute(ctx: InterpreterContext, ir: IR_Module): Value =
    // JIT compilation and execution
    // For now, fall back to reference
    return reference_vm.execute(ctx, ir)

# AOT execution (stub)
proc aot_execute(ctx: InterpreterContext, ir: IR_Module): Value =
    // AOT compilation and execution
    // For now, fall back to reference
    return reference_vm.execute(ctx, ir)

# ============================================================================
# Interpreter Loop (Reference VM)
# ============================================================================
# The reference VM executes IR directly using the common runtime operations
# ============================================================================

# Execute IR module
proc execute(ctx: InterpreterContext, module: IR_Module): Value =
    // Set up initial frame for module-level code
    let frame = frames.new_frame(
        function_id: make_module_function_id(module.name),
        function: make_module_function(module),
        ip: 0,
        slot_count: module.slot_count,
        source_loc: SourceLocation(module.name, 1, 1)
    )
    
    context.push_frame(ctx, frame)
    
    // Execute module body
    let result = execute_ir_block(ctx, module.body)
    
    context.pop_frame(ctx)
    
    return result

# Execute IR block
proc execute_ir_block(ctx: InterpreterContext, block: IR_Block): Value =
    let frame = context.get_current_frame(ctx).unwrap()
    frame.ip = block.start_pc
    
    while frame.ip < block.end_pc:
        let instr = module.instructions[frame.ip]
        frame.ip = frame.ip + 1
        
        let result = execute_instruction(ctx, frame, instr)
        
        // Handle control flow
        if result.kind != control.CF_NORMAL:
            return handle_control_flow(ctx, frame, result)
    
    return values.nil

# Execute single IR instruction
proc execute_instruction(ctx: InterpreterContext, frame: CallFrame, instr: IR_Instr): ControlResult =
    match instr.opcode:
        IR_LOAD_CONST:
            let val = instr.operands[0]
            frames.slot_store(frame, instr.dest, val)
            return control.result_normal(values.nil)
        IR_LOAD_LOCAL:
            let val = frames.slot_load(frame, instr.operands[0])
            frames.slot_store(frame, instr.dest, val)
            return control.result_normal(values.nil)
        IR_STORE_LOCAL:
            let val = frames.slot_load(frame, instr.operands[0])
            frames.slot_store(frame, instr.dest, val)
            return control.result_normal(values.nil)
        IR_BINARY_OP:
            let lhs = frames.slot_load(frame, instr.operands[0])
            let rhs = frames.slot_load(frame, instr.operands[1])
            let result = context.runtime_binary(ctx, instr.op, lhs, rhs)
            frames.slot_store(frame, instr.dest, result)
            return control.result_normal(values.nil)
        IR_CALL:
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
        IR_RETURN:
            let val = frames.slot_load(frame, instr.operands[0])
            return ControlResult(kind: control.CF_RETURN, value: val, target: None)
        IR_JUMP:
            frame.ip = instr.operands[0]
            return control.result_normal(values.nil)
        IR_JUMP_IF_FALSE:
            let cond = frames.slot_load(frame, instr.operands[0])
            if not context.runtime_truthy(ctx, cond):
                frame.ip = instr.operands[1]
            return control.result_normal(values.nil)
        IR_GET_PROP:
            let obj = frames.slot_load(frame, instr.operands[0])
            let result = context.runtime_get_property(ctx, obj, instr.operands[1])
            frames.slot_store(frame, instr.dest, result)
            return control.result_normal(values.nil)
        IR_SET_PROP:
            let obj = frames.slot_load(frame, instr.operands[0])
            let val = frames.slot_load(frame, instr.operands[1])
            context.runtime_set_property(ctx, obj, instr.operands[2], val)
            return control.result_normal(values.nil)
        IR_INDEX:
            let obj = frames.slot_load(frame, instr.operands[0])
            let idx = frames.slot_load(frame, instr.operands[1])
            let result = context.runtime_index(ctx, obj, idx)
            frames.slot_store(frame, instr.dest, result)
            return control.result_normal(values.nil)
        _:
            // Unknown instruction
            return control.result_normal(values.nil)

# Handle control flow results
proc handle_control_flow(ctx: InterpreterContext, frame: CallFrame, result: ControlResult): Value =
    match result.kind:
        control.CF_RETURN:
            return result.value
        control.CF_BREAK:
            // Find enclosing loop
            return unwind.unwind_for_break(ctx, frame)
        control.CF_CONTINUE:
            return unwind.unwind_for_continue(ctx, frame)
        control.CF_YIELD:
            // Generator yield
            return generators.generator_yield(frame, result.value)
        control.CF_THROW:
            return unwind.unwind_stack(ctx, result.value)
        _:
            return values.nil

# ============================================================================
# IR Types (minimal for orchestration)
# ============================================================================

class IR_Module {
    let name: String
    let instructions: Array<IR_Instr>
    let slot_count: Int
    let body: IR_Block
}

class IR_Block {
    let start_pc: Int
    let end_pc: Int
}

class IR_Instr {
    let opcode: Int
    let dest: Int
    let operands: Array<Value>
    let op: String
}

class OptimizedIR {
    let ir: IR_Module
    let profile: CpcProfile
}

class CpcProfile {
    // CPC profile data
}

# IR opcodes
let IR_LOAD_CONST = 0
let IR_LOAD_LOCAL = 1
let IR_STORE_LOCAL = 2
let IR_BINARY_OP = 3
let IR_CALL = 4
let IR_RETURN = 5
let IR_JUMP = 6
let IR_JUMP_IF_FALSE = 7
let IR_GET_PROP = 8
let IR_SET_PROP = 9
let IR_INDEX = 10

# Helper functions
proc make_module_function_id(name: String): FunctionId =
    FunctionId(
        hash: name.hash(),
        source_name: name,
        owner_class: None,
        param_hash: 0,
        default_hash: 0
    )

proc make_module_function(module: IR_Module): Function =
    Function(
        function_id: make_module_function_id(module.name),
        source_name: module.name,
        owner_class: None,
        params: [],
        defaults: [],
        body: module.body,
        closure: None,
        profile: FunctionProfile(
            function_id: make_module_function_id(module.name),
            call_count: 0,
            monomorphic: true,
            observed_types: {} as Dict<String, Int>,
            inline_cache: None,
            deopt_reason: None
        )
    )