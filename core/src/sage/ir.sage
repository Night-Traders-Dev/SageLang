# ============================================================================
# IR Facade - Unified IR interface
# ============================================================================

import ir.builder as builder
import ir.verifier as verifier
import ir.optimizer as optimizer

# Build IR from resolved module
proc build_ir(resolved: ResolvedModule, ctx: InterpreterContext): IR_Module =
    return builder.build_ir(resolved, ctx)

# Verify IR module
proc verify(module: IR_Module): VerifyResult =
    return verifier.verify(module)

# Optimize IR module
proc optimize(module: IR_Module, profiles: Dict<FunctionId, FunctionProfile>): OptimizedIR =
    let opt = optimizer.optimizer_new(module, profiles)
    return optimizer.optimizer_run(opt)