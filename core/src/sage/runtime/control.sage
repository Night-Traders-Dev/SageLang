# ============================================================================
# Runtime Control - Control flow management
# ============================================================================
# Represent control flow explicitly:
#   Normal, Return, Break, Continue, Yield, Throw
#
# Each frame tracks:
#   pending control flow, defer stack, exception state
#
# The runtime must define precedence for:
#   try, finally, return, break, continue, throw, defer
# ============================================================================

# Control flow result kinds
let CF_NORMAL = 0
let CF_RETURN = 1
let CF_BREAK = 2
let CF_CONTINUE = 3
let CF_YIELD = 4
let CF_THROW = 5

# Control flow result structure
class ControlResult {
    let kind: Int          // One of CF_* constants
    let value: Value       // Return/yield/throw value
    let target: Option[Int]  // Return target PC, if applicable
}

# Structured error types (from pipeline.md)
class RuntimeError  (msg: String) extends Exception(msg)
class TypeError     (msg: String) extends Exception(msg)
class NameError     (msg: String) extends Exception(msg)
class PropertyError  (msg: String) extends Exception(msg)
class IndexError     (msg: String) extends Exception(msg)
class ArgumentError  (msg: String) extends Exception(msg)
class CapabilityError(msg: String) extends Exception(msg)
class ResourceLimitError(msg: String) extends Exception(msg)
class HostError      (msg: String) extends Exception(msg)

# Control flow propagation through frames
proc propagate_control(current: CallFrame, result: ControlResult): Bool =
    match result.kind:
        CF_NORMAL:
            return false  // Continue normal execution
        CF_RETURN:
            set_return_target(current, result.value as Int)
            return true   // Indicate return occurred
        CF_BREAK:
            // Handle break - search for enclosing loop
            return true
        CF_CONTINUE:
            // Handle continue - search for enclosing loop
            return true
        CF_YIELD:
            // Handle yield - suspend execution
            return true
        CF_THROW:
            set_exception_state(current, ExceptionState(
                exception: Some(result.value),
                handler_pc: None,
                unwinding: true,
                finalizer: None
            ))
            return true   // Indicate exception propagation
    return false

# Defer/finally precedence rules (from pipeline.md line 707-715)
# The runtime must define precedence for:
#   try, finally, return, break, continue, throw, defer

# Precedence order (highest to lowest):
# 1. throw (if active)
# 2. defer (if pending)
# 3. finally (if in try block)
# 4. return
# 5. break
# 6. continue
# 7. normal

# Check if there's a pending defer in the current frame
proc has_pending_defer(frame: CallFrame): Bool =
    frame.defer_stack.len > 0

# Check if there's a pending exception
proc has_pending_exception(frame: CallFrame): Bool =
    frame.exception_state != None and frame.exception_state.unwinding

# Run defer handlers
proc run_defer_handlers(frame: CallFrame): Unit =
    while has_pending_defer(frame):
        let defer = pop_defer(frame)
        // Execute defer handler
        // Note: defer handlers run in LIFO order
        // Finally blocks run before return, after exception handling

# Finally block execution
proc run_finally(frame: CallFrame, finalizer_pc: Int): Unit =
    if has_pending_exception(frame):
        // If there's an active exception, run finally before handling
        // The exception will be re-thrown after finally completes
        run_defer_handlers(frame)
    // Execute finally block at finalizer_pc
    // Jump back to normal execution after finally

# Control flow precedence determination
# Returns the effective control flow kind, considering all factors
proc determine_control_flow(
    frame: CallFrame,
    proposed_kind: Int,
    proposed_value: Value
): Int =
    // Check for active exception (highest priority)
    if has_pending_exception(frame):
        return CF_THROW
    
    // Check for pending defer
    if has_pending_defer(frame) and proposed_kind != CF_THROW:
        // Defer takes precedence over normal flow
        // but not over throw
        return CF_NORMAL  // Defer will be run on exit
    
    // Check for return in finally context
    // ... complex logic here
    
    // Default: use proposed control flow
    return proposed_kind

# Yield/resume operations for generators
proc generator_yield(frame: CallFrame, value: Value): ControlResult =
    ControlResult(
        kind: CF_YIELD,
        value: value,
        target: None
    )

proc generator_resume(frame: CallFrame, resume_value: Value): ControlResult =
    ControlResult(
        kind: CF_NORMAL,
        value: resume_value,
        target: None
    )

# Entry point for control flow in execution tiers
# All tiers must respect the same control flow semantics
proc execute_statement(
    genv: InterpreterContext,
    stmt: Stmt
): ControlResult =
    // Dispatch to statement-specific handlers
    // All tiers must produce compatible results
    error "Not implemented: execute_statement"
