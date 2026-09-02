gc_disable()
# ============================================================================
# interpreter.sage - Thin orchestration layer
# ============================================================================
# After modularization, interpreter.sage becomes a thin orchestration layer that:
# 1. Creates InterpreterContext
# 2. Selects a runtime profile
# 3. Invokes the frontend
# 4. Builds or loads Sage IR
# 5. Selects an execution tier
# 6. Runs the program
# 7. Normalizes diagnostics and results
# It should no longer contain the implementation of every runtime subsystem.
//
// This file replaces the old monolithic interpreter.sage and wires together
# all the modular components created in core/src/sage/runtime/, core/src/sage/interpreter/,
// core/src/sage/frontend/, and core/src/sage/ir/
//
// See pipeline.md Section 3: Modular Runtime Layout
// and Section 2: Ideal End-to-End Pipeline
// ============================================================================

import runtime.context as ctx_module
import runtime.values as values
import runtime.errors as errors
import runtime.modules as modules
import runtime.capabilities as capabilities
import frontend.sage as frontend
import interpreter.eval_expr as eval_expr
import interpreter.eval_stmt as eval_stmt
import interpreter.unwind as unwind
import interpreter.generators as generators
import ir.builder as ir_builder
import ir.sage as ir_sage
import ir.verifier as ir_verifier
import ir.optimizer as ir_optimizer
import vm.reference as reference_vm
import vm.bytecode as bytecode_vm

// ============================================================================
# CLI and Entry Point
// ============================================================================

// Main entry point for the SageLang runtime
// Usage: sage [options] [file.sage]
// or:    sage --repl
// or:    sage --profile general --runtime reference script.sage
proc main(args: Array<String>): Int =
    // Parse CLI options
    let opts = parse_args(args)
    
    // Validate profile and tier
    validate_profile_and_tier(opts)
    
    // Create InterpreterContext
    let ctx = ctx_module.context_new(opts.profile)
    
    // Apply CLI options
    ctx_module.set_runtime_tier(ctx, opts.tier)
    ctx_module.set_flag(ctx, "profiling", true)
    ctx_module.set_flag(ctx, "verification", opts.verify_parity)
    ctx_module.set_flag(ctx, "trace", opts.trace)
    if opts.max_steps > 0:
        ctx_module.resource_limits.max_steps = opts.max_steps
    
    // Print profile info
    print_profile_info(ctx, opts.profile)
    
    // Handle REPL
    if opts.repl:
        return run_repl(ctx)
    
    // Handle source file
    if opts.source_file == None:
        print "Error: No source file specified"
        return 1
    
    // Load source code
    let source = file_read(opts.source_file)
    let filename = opts.source_file
    
    // Set source in context for error reporting
    ctx_module.set_source(ctx, source, filename)
    
    // ====================================================================
    # 1. Invoke Frontend
    # ====================================================================
    print "=== Frontend: Lexing, Parsing, Semantic Analysis ==="
    
    let parse_result = frontend.parse(source, filename)
    
    // Check for errors
    if diagnostics.has_errors(parse_result.diagnostics):
        print "Frontend errors:"
        diagnostics.print_diagnostics(parse_result.diagnostics)
        return 1
    
    // Print warnings
    if diagnostics.has_warnings(parse_result.diagnostics):
        print "Frontend warnings:"
        diagnostics.print_diagnostics(parse_result.diagnostics)
    
    print "  ✓ Parsing and semantic analysis complete"
    
    // ====================================================================
    # 2. Build Sage IR
    # ====================================================================
    print "=== IR Generation ==="
    
    let resolved = parse_result.resolved
    let ir_module = ir_builder.build_ir(resolved, ctx)
    
    // Verify IR if requested
    if ctx_module.get_flag(ctx, "verification"):
        let verify_result = ir_verifier.verify(ir_module)
        if not verify_result.valid:
            print "IR Verification errors:"
            for err in verify_result.errors:
                print "  - " + err
            return 1
        print "  ✓ IR verification passed"
    
    // Print IR if requested
    if opts.dump_ir:
        print "=== Sage IR ==="
        print ir_module_to_string(ir_module)
    
    // Optimize IR if not reference tier
    let optimized_ir: ir_optimizer.OptimizedIR
    match opts.tier:
        "reference":
            // No optimization for reference
            optimized_ir = ir_optimizer.OptimizedIR(ir: ir_module, profile: ir_optimizer.CpcProfile())
        _:
            optimized_ir = ir_optimizer.optimize(ir_module, ctx_module.context_get_profiler(ctx))
    
    // Replace with optimized if we have it
    let execute_ir = optimized_ir.ir
    
    // ====================================================================
    # 3. Select and Run Execution Tier
    # ====================================================================
    print "=== Execution Tier: " + opts.tier + " ==="
    
    let result: Value
    match opts.tier:
        "reference":
            result = reference_vm.execute(ctx, execute_ir)
        "bytecode":
            let bytecode = bytecode_vm.compile_ir_to_bytecode(execute_ir)
            if opts.dump_bytecode:
                print "=== Bytecode ==="
                print bytecode_to_string(bytecode)
            result = bytecode_vm.execute_bytecode(ctx, bytecode)
        "cpc":
            // CPC optimization + reference execution
            // For now, execute the optimized IR through reference
            result = reference_vm.execute(ctx, execute_ir)
        "jit":
            // JIT compilation (fall back to reference for now)
            result = reference_vm.execute(ctx, execute_ir)
        "aot":
            // AOT compilation (fall back to reference for now)
            result = reference_vm.execute(ctx, execute_ir)
        _:
            print "Unknown runtime tier: " + opts.tier
            return 1
    
    // ====================================================================
    # 4. Normalize Diagnostics and Results
    # ====================================================================
    
    // Print result
    if result != values.nil:
        print "Result: " + values.value_to_string(result)
    
    // Print profiling info if enabled
    if ctx_module.get_flag(ctx, "profiling"):
        let profiles = ctx_module.context_get_function_profiles(ctx)
        if profiles.len > 0:
            print "=== Profile Summary ==="
            for func_id in profiles.keys:
                let profile = profiles[func_id]
                print "  " + func_id.source_name + ": " + profile.call_count.ToString() + " calls"
    
    // Resource usage summary
    let steps = ctx_module.context_get_resource_limits(ctx).max_steps
    let steps_used = // ... get from ctx
    if steps_used > 0:
        print "Steps: " + steps_used.ToString()
    
    // Parity verification if requested
    if opts.verify_parity and opts.tier != "reference":
        let ref_result = reference_vm.execute(ctx_module.context_new(opts.profile), execute_ir)
        if not values.value_eq(result, ref_result):
            print "PARITY MISMATCH between " + opts.tier + " and reference!"
            print "  " + opts.tier + ": " + values.value_to_string(result)
            print "  reference: " + values.value_to_string(ref_result)
            return 2
    
    // ====================================================================
    # Done
    # ====================================================================
    print "=== Execution Complete ==="
    return 0

// Parse CLI arguments
proc parse_args(args: Array<String>): CliOptions =
    let opts = CliOptions(
        source_file: None,
        source_code: None,
        profile: "general",
        tier: "reference",
        repl: false,
        verify_parity: false,
        trace: false,
        dump_ir: false,
        dump_bytecode: false,
        dump_frames: false,
        dump_profile: false,
        dump_shapes: false,
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
            "--tier":
                i = i + 1
                if i < len(args):
                    opts.tier = args[i]
            "--repl":
                opts.repl = true
            "--verify-parity":
                opts.verify_parity = true
            "--trace":
                opts.trace = true
            "--dump-ir":
                opts.dump_ir = true
            "--dump-bytecode":
                opts.dump_bytecode = true
            "--dump-frames":
                opts.dump_frames = true
            "--dump-profile":
                opts.dump_profile = true
            "--dump-shapes":
                opts.dump_shapes = true
            "--dump-capabilities":
                opts.dump_capabilities = true
            "--dump-deopt":
                opts.dump_deopt = true
            "--max-steps":
                i = i + 1
                if i < len(args):
                    opts.max_steps = args[i].toInt()
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

// Validate profile and tier
proc validate_profile_and_tier(opts: CliOptions): Unit =
    let valid_profiles = ["general", "embedded", "deterministic"]
    let valid_tiers = ["reference", "bytecode", "cpc", "jit", "aot"]
    
    if not valid_profiles.includes(opts.profile):
        print "Invalid profile: " + opts.profile
        print "Valid: " + valid_profiles.join(", ")
        exit 1
    
    if not valid_tiers.includes(opts.tier):
        print "Invalid tier: " + opts.tier
        print "Valid: " + valid_tiers.join(", ")
        exit 1

// Print profile info
proc print_profile_info(ctx: InterpreterContext, profile: String): Unit =
    let caps = capabilities.context_get_host_capabilities(ctx)
    print "Profile: " + profile
    print "Capabilities: " + caps.allowed.map { cap -> capabilities.CAP_NAMES[cap.level] }.join(", ")
    print "Resource limits: steps=" + ctx_module.context_get_resource_limits(ctx).max_steps.ToString()
    print "Runtime tier: " + ctx_module.context_get_runtime_tier(ctx)

// Print IR as string
proc ir_module_to_string(module: ir_sage.IR_Module): String =
    let output = "Module: " + module.name + "\n"
    output = output + "Functions: " + module.functions.len.ToString() + "\n"
    for func in module.functions:
        output = output + "  Function: " + func.name + " (" + func.local_count.ToString() + " slots)\n"
        for block in func.blocks:
            output = output + "    Block " + block.id.ToString() + ":"
            for instr in block.instructions:
                output = output + " " + opcode_to_string(instr.opcode)
            output = output + "\n"
    return output

// Opcode to string
proc opcode_to_string(opcode: Int): String =
    match opcode:
        0: return "NOP"
        1: return "LOAD_CONST"
        2: return "LOAD_LOCAL"
        3: return "STORE_LOCAL"
        4: return "LOAD_GLOBAL"
        5: return "STORE_GLOBAL"
        6: return "BINARY_OP"
        7: return "RETURN"
        8: return "JUMP"
        9: return "JUMP_IF_FALSE"
        10: return "GET_PROP"
        11: return "SET_PROP"
        12: return "GET_INDEX"
        13: return "SET_INDEX"
        14: return "BUILD_ARRAY"
        15: return "BUILD_DICT"
        _: return "UNKNOWN"

print "=== interpreter.sage orchestration layer loaded ==="
print "Modular SageLang runtime - all components from pipeline.md"