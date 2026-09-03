# ============================================================================
# Interpreter Generators - Generator implementation
# ============================================================================
# True Generator Frames (from pipeline.md):
# generator() creates GeneratorFrame
# next() resumes frame, executes, yields, saves state
# Generators must suspend execution rather than eagerly collecting
# ============================================================================

import runtime.values as values
import runtime.frames as frames
import runtime.control as control
import runtime.errors as errors

# Generator frame structure
class GeneratorFrame {
    let frame: Frame              // The suspended frame
    let state: GeneratorState     // Current state
    let resume_value: Option<Value>  // Value to resume with
    let yield_value: Option<Value>   // Last yielded value
    let is_exhausted: Bool        // Whether generator is done
}

# Generator state
let GEN_STATE_CREATED = 0
let GEN_STATE_RUNNING = 1
let GEN_STATE_SUSPENDED = 2
let GEN_STATE_EXHAUSTED = 3
let GEN_STATE_ERROR = 4

# Create a generator from a function
proc create_generator(
    ctx: InterpreterContext,
    function: Value,
    args: Array<Value>
): Value =
    let fn = function.data.fn_val
    
    // Create initial frame for the generator
    let gen_frame = frames.new_frame(
        function_id: fn.function_id,
        function: fn,
        ip: 0,  // Start at beginning
        slot_count: fn.profile.slot_count,
        source_loc: fn.body.location
    )
    
    // Bind arguments
    let kw_map = calls.make_kw_param_map(fn.params, fn.defaults, fn.is_variadic)
    let bound_args = calls.bind_arguments(kw_map, args, fn.defaults)
    for i in 0..bound_args.len:
        frames.slot_store(gen_frame, i, bound_args[i])
    
    // Create generator frame
    let gf = GeneratorFrame(
        frame: gen_frame,
        state: GEN_STATE_CREATED,
        resume_value: None,
        yield_value: None,
        is_exhausted: false
    )
    
    return values.value_generator(gf, GeneratorResumeState())

# Generator resume state
class GeneratorResumeState {
    let ip: Int              // Instruction pointer to resume at
    let locals: Array<Value> // Local variables at suspend point
    let stack_depth: Int     // Stack depth at suspend point
}

# Next/resume a generator
proc generator_next(ctx: InterpreterContext, gen_val: Value, resume_val: Value): Value =
    let gen = gen_val.data.gen_val
    let gf = gen.frame
    
    if gf.state == GEN_STATE_EXHAUSTED:
        raise errors.error_runtime("Generator exhausted")
    if gf.state == GEN_STATE_ERROR:
        raise errors.error_runtime("Generator in error state")
    
    // Set resume value
    gf.resume_value = Some(resume_val)
    
    // Resume execution
    gf.state = GEN_STATE_RUNNING
    
    // Execute until yield or return
    let result = execute_generator_frame(ctx, gf)
    
    gf.state = if result.kind == control.CF_YIELD then GEN_STATE_SUSPENDED else GEN_STATE_EXHAUSTED
    gf.yield_value = if result.kind == control.CF_YIELD then Some(result.value) else None
    
    if result.kind == control.CF_YIELD:
        return result.value
    else if result.kind == control.CF_RETURN:
        gf.is_exhausted = true
        return values.nil
    else:
        gf.is_exhausted = true
        raise errors.error_runtime("Generator ended with unexpected control flow")

# Execute a generator frame until yield or return
proc execute_generator_frame(ctx: InterpreterContext, gf: GeneratorFrame): ControlResult =
    // This is the core generator execution loop
    // It runs the frame's function until a yield or return
    // The frame's instruction pointer is saved/restored
    
    let frame = gf.frame
    ctx.current_frame = frame
    
    // Restore state if resuming
    if gf.resume_value != None:
        // Handle resume value (e.g., for send())
        // ...
    
    // Execute statements until yield/return
    // This would integrate with the main interpreter loop
    // For now, return a placeholder
    return control.result_normal(values.nil)

# Send value to generator (like next() but with a value)
proc generator_send(ctx: InterpreterContext, gen_val: Value, value: Value): Value =
    return generator_next(ctx, gen_val, value)

# Throw exception into generator
proc generator_throw(ctx: InterpreterContext, gen_val: Value, exception: Value): Value =
    let gen = gen_val.data.gen_val
    let gf = gen.frame
    
    if gf.state == GEN_STATE_EXHAUSTED:
        raise errors.error_runtime("Generator exhausted")
    
    // Inject exception at current point
    gf.frame.exception_state = Some(ExceptionState(
        exception: Some(exception),
        handler_pc: None,
        unwinding: true,
        finalizer: None
    ))
    
    gf.state = GEN_STATE_RUNNING
    let result = execute_generator_frame(ctx, gf)
    
    gf.state = if result.kind == control.CF_YIELD then GEN_STATE_SUSPENDED else GEN_STATE_EXHAUSTED
    gf.yield_value = if result.kind == control.CF_YIELD then Some(result.value) else None
    
    return result.value

# Close generator (cleanup)
proc generator_close(ctx: InterpreterContext, gen_val: Value): Unit =
    let gen = gen_val.data.gen_val
    let gf = gen.frame
    
    if gf.state == GEN_STATE_EXHAUSTED or gf.state == GEN_STATE_ERROR:
        return
    
    // Run any pending finally/defer handlers
    // ...
    
    gf.state = GEN_STATE_EXHAUSTED
    gf.is_exhausted = true

# Check if generator is exhausted
proc generator_is_exhausted(gen_val: Value): Bool =
    let gen = gen_val.data.gen_val
    return gen.frame.is_exhausted
