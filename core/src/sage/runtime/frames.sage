# ============================================================================
# Runtime Frames - CallFrame management
# ============================================================================
# The same conceptual frame model supports:
#   reference execution, bytecode execution, generators
#   exception unwinding, JIT deoptimization, debugging
# ============================================================================

# CallFrame structure - matches pipeline.md definition:
# CallFrame
#   ├── function_id
#   ├── function
#   ├── instruction/AST position
#   ├── locals or slots
#   ├── closure
#   ├── return target
#   ├── defer stack
#   ├── exception state
#   └── source location

class CallFrame {
    let function_id: FunctionId      // Unique function identifier
    let function: Function           // Function object
    let ip: Int                      // Instruction pointer / program counter
    let locals: Array<Value>         // Local variables/slots
    let closure: Option<Frame>       // Capturing closure, if any
    let return_target: Option[Int]   // Where to return to
    let defer_stack: List<DeferInfo> // Defer/try-stack for this frame
    let exception_state: Option[ExceptionState]  // Current exception
    let source_location: SourceLocation  // Source code position
}

# Defer information for defer/finally semantics
class DeferInfo {
    let handler: String       // Handler name/ID
    let pc: Int               // Program counter at defer point
    let captured_locals: Array<Value>  // Locals captured at defer point
}

# Exception state tracking
class ExceptionState {
    let exception: Option[Value]  // The exception value, if any
    let handler_pc: Option[Int]   // Next handler to jump to
    let unwinding: Bool           // Whether we're currently unwinding
    let finalizer: Option[Int]    // Finally block PC, if any
}

# Frame stack for call management
class FrameStack {
    let frames: List<CallFrame>
    let max_depth: Int
    
    proc init(max_depth: Int): FrameStack = FrameStack(frames: [], max_depth: max_depth)
    
    proc push(frame: CallFrame): Bool =
        if frames.len >= max_depth:
            return false  // Stack overflow
        frames = frames.push(frame)
        return true
    
    proc pop(): Option<CallFrame> =
        if frames.is_empty():
            return None
        let frame = frames.last
        frames = frames.pop()
        return Some(frame)
    
    proc peek(): Option<CallFrame> =
        if frames.is_empty():
            return None
        return Some(frames.last)
    
    // Current active frame
    proc current(): Option<CallFrame> = peek()
    
    // Set current frame
    proc set_current(frame: CallFrame): Bool =
        if frames.is_empty():
            return false
        frames.last = frame  // Mutate the last frame
        return true
}

# Frame creation helpers
proc new_frame(
    function_id: FunctionId,
    function: Function,
    ip: Int,
    slot_count: Int,
    source_loc: SourceLocation
): CallFrame = CallFrame(
    function_id: function_id,
    function: function,
    ip: ip,
    locals: Array<Value>(slot_count),  // Initialize with nils
    closure: None,
    return_target: None,
    defer_stack: [],
    exception_state: None,
    source_location: source_loc
)

# Frame stack singleton for the current interpreter
let g_frame_stack: FrameStack = FrameStack(max_depth: 12000)

# Accessor functions (matching pipeline.md canonical operations)
proc get_current_frame(): Option[CallFrame] = g_frame_stack.current()
proc set_current_frame(frame: CallFrame): Bool = g_frame_stack.set_current(frame)
proc push_frame(frame: CallFrame): Bool = g_frame_stack.push(frame)
proc pop_frame(): Option[CallFrame] = g_frame_stack.pop()
proc get_function_id(frame: CallFrame): FunctionId = frame.function_id
proc get_return_target(frame: CallFrame): Option[Int] = frame.return_target
proc set_return_target(frame: CallFrame, target: Int): Unit =
    frame.return_target = Some(target)
proc get_defer_stack(frame: CallFrame): List[DeferInfo] = frame.defer_stack
proc push_defer(frame: CallFrame, handler: String, locals: Array<Value>): Unit =
    frame.defer_stack = frame.defer_stack.push(DeferInfo(handler, frame.ip, locals))
proc pop_defer(frame: CallFrame): Option[DeferInfo] =
    if frame.defer_stack.is_empty():
        return None
    let defer = frame.defer_stack.last
    frame.defer_stack = frame.defer_stack.pop()
    return Some(defer)
proc get_exception_state(frame: CallFrame): Option[ExceptionState] = frame.exception_state
proc set_exception_state(frame: CallFrame, state: ExceptionState): Unit =
    frame.exception_state = Some(state)

# Frame operations for control flow
# The same frame model supports all execution tiers
# Reference VM, Bytecode VM, JIT/AOT all use the same CallFrame concept

# Frame serialization for debugging/dump tools
proc frame_to_string(frame: CallFrame): String =
    "Frame[func=" + frame.function_id.source_name + 
    " ip=" + frame.ip.ToString() +
    " slots=" + frame.locals.len.ToString() +
    " exception=" + (if frame.exception_state != None else "none") + "]"
