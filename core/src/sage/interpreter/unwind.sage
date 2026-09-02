// ============================================================================
# Interpreter Unwind - Exception unwinding and control flow
# ============================================================================
// Part of the Reference VM tier
// Handles exception propagation, finally blocks, defer execution
// ============================================================================

import runtime.frames as frames
import runtime.control as control
import runtime.errors as errors

// Unwind the stack looking for a handler
proc unwind_stack(
    ctx: InterpreterContext,
    exception: Value
): Option[ExceptionHandler] =
    // Walk frame stack from top to bottom
    let frame_stack = ctx.frame_stack
    let i = frame_stack.frames.len - 1
    while i >= 0:
        let frame = frame_stack.frames[i]
        
        // Check for exception handlers in this frame
        let handler = find_exception_handler(frame, exception)
        if handler != None:
            return Some(handler)
        
        // Run defer handlers in this frame
        run_defer_handlers(frame)
        
        // Check for finally blocks
        let finally_pc = find_finally_block(frame)
        if finally_pc != None:
            // Execute finally, then continue unwinding
            execute_finally(ctx, frame, finally_pc)
        
        i = i - 1
    
    return None  // Unhandled exception

// Find exception handler in a frame
proc find_exception_handler(frame: Frame, exception: Value): Option[ExceptionHandler] =
    // Look for catch blocks in the frame's code
    // This would be determined at compile time
    return None  // Simplified

// Exception handler structure
class ExceptionHandler {
    let catch_var: String       // Variable name for caught exception
    let catch_block: Stmt       // Catch block AST
    let finally_block: Option[Stmt]  // Finally block, if any
    let handler_pc: Int         // Program counter of handler
}

// Run defer handlers in a frame
proc run_defer_handlers(frame: Frame): Unit =
    while frames.has_pending_defer(frame):
        let defer = frames.pop_defer(frame)
        // Execute the defer handler
        // In the reference VM, this means running the deferred statements
        execute_defer_statement(defer.handler, frame.captured_locals)

// Find finally block in a frame
proc find_finally_block(frame: Frame): Option[Int] =
    // Check if there's a finally block associated with this frame
    // This would be stored in the frame's exception state
    if frame.exception_state != None:
        return frame.exception_state.finalizer
    return None

// Execute finally block
proc execute_finally(ctx: InterpreterContext, frame: Frame, finally_pc: Int): Unit =
    // Save current state
    let saved_ip = frame.ip
    let saved_locals = frame.locals.copy()
    
    // Jump to finally block
    frame.ip = finally_pc
    
    // Execute finally statements
    // ...
    
    // Restore state
    frame.ip = saved_ip
    frame.locals = saved_locals

// Execute a defer statement
proc execute_defer_statement(handler: String, captured_locals: Array<Value>): Unit =
    // Execute the deferred code with captured locals
    // ...

// Unwind result types
let UNWIND_HANDLED = 0
let UNWIND_UNHANDLED = 1
let UNWIND_FINALLY = 2

// Handle control flow result
proc handle_control_flow(
    ctx: InterpreterContext,
    frame: Frame,
    result: ControlResult
): Int =
    match result.kind:
        control.CF_NORMAL:
            return UNWIND_HANDLED
        control.CF_RETURN:
            // Set return value and unwind
            frame.return_target = Some(result.value)
            return unwind_for_return(ctx, frame)
        control.CF_BREAK:
            // Find enclosing loop
            return unwind_for_break(ctx, frame)
        control.CF_CONTINUE:
            // Find enclosing loop
            return unwind_for_continue(ctx, frame)
        control.CF_YIELD:
            // Suspend generator
            return UNWIND_HANDLED  // Generator handles this
        control.CF_THROW:
            // Exception - unwind stack
            let handler = unwind_stack(ctx, result.value)
            if handler != None:
                // Found handler, transfer control
                return UNWIND_HANDLED
            else:
                // Unhandled exception
                return UNWIND_UNHANDLED
    return UNWIND_HANDLED

// Unwind for return
proc unwind_for_return(ctx: InterpreterContext, frame: Frame): Int =
    // Run defer handlers
    run_defer_handlers(frame)
    
    // Run finally blocks
    let finally_pc = find_finally_block(frame)
    if finally_pc != None:
        execute_finally(ctx, frame, finally_pc)
    
    // Pop frame and continue unwinding
    frames.pop_frame()
    return UNWIND_HANDLED

// Unwind for break
proc unwind_for_break(ctx: InterpreterContext, frame: Frame): Int =
    // Run defer handlers in frames being exited
    // Find enclosing loop
    // ...

// Unwind for continue
proc unwind_for_continue(ctx: InterpreterContext, frame: Frame): Int =
    // Similar to break but jumps to loop continuation
    // ...

// Unhandled exception handler
proc handle_unhandled_exception(ctx: InterpreterContext, exception: Value): Unit =
    // Print error and exit
    let msg = errors.format_error(exception)
    print "Unhandled exception: " + msg
    // In REPL, continue; in script, exit
