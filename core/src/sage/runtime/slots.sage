// ============================================================================
# Runtime Slots - Lexical slot management
# ============================================================================
// Replace environment chain with resolved slot
// name | environment chain | dictionary lookup
// with:
// name | resolved slot | frame storage
//
// Preserve:
//   shadowing, closures, captured mutation, nested functions
// ============================================================================

// Slot representation
class Slot {
    let index: Int       // Slot index in the frame
    let scope: Scope     // Lexical scope information
    let captured: Bool   // Whether this slot is captured by a closure
    let mutable: Bool    // Whether the slot can be mutated
}

// Scope enumeration for slot tracking
let SCOPE_GLOBAL = 0
let SCOPE_LOCAL = 1
let SCOPE_CLOSURE = 2
let SCOPE_MODULE = 3

// Frame structure with slots
class Frame {
    let function_id: FunctionId
    let return_address: Int
    let slot_base: Int       // Base slot index for this frame
    let slot_count: Int      // Number of slots in this frame
    let locals: Array<Value> // Local values stored in slots
    let closure: Option<Frame> // Capturing closure frame, if any
    let defer_stack: List<DeferInfo> // Defer stack for this frame
    let exception_state: Option[ExceptionState] // Current exception state
}

// Scope tracking for slot resolution
class SlotResolver {
    // Map variable names to slot indices
    let slot_map: Dict<String, Int>
    let scope_chain: List<Frame>
    let next_slot: Int
    
    proc init(): SlotResolver = SlotResolver(
        slot_map: {} as Dict<String, Int>,
        scope_chain: [],
        next_slot: 0
    )
    
    // Bind a variable to a slot
    proc bind(name: String): Int =
        let idx = next_slot
        slot_map[name] = idx
        next_slot = next_slot + 1
        return idx
    
    // Lookup a variable by name, returns slot index
    proc lookup(name: String): Option<Int> =
        if dict_has(slot_map, name):
            return Some(slot_map[name])
        // Search parent scopes
        let i = 0
        while i < scope_chain.len:
            let parent_idx = scope_chain[i].slot_map.get(name, None)
            if parent_idx != None:
                return Some(parent_idx)
            i = i + 1
        return None
    
    // Enter a new scope
    proc enter_scope(): SlotResolver =
        let new_resolver = SlotResolver(
            slot_map: slot_map,
            scope_chain: scope_chain.push(current_frame),
            next_slot: next_slot
        )
        return new_resolver
    
    // Exit a scope
    proc exit_scope(): SlotResolver =
        let new_resolver = SlotResolver(
            slot_map: slot_map,
            scope_chain: scope_chain.pop(),
            next_slot: next_slot
        )
        return new_resolver
}

// Slot access helpers
proc slot_load(frame: Frame, slot_index: Int): Value =
    if slot_index < frame.slot_count:
        return frame.locals[slot_index - frame.slot_base]
    raise "Slot index out of range"

proc slot_store(frame: Frame, slot_index: Int, value: Value): Unit =
    if slot_index < frame.slot_count:
        frame.locals[slot_index - frame.slot_base] = value
        return
    raise "Slot index out of range"

// Compact runtime object slot layout
// Instance fields use slot indices rather than dynamic dictionaries
// Class defines shape ID -> field slot mapping
// User dictionaries remain fully dynamic (unchanged)

// Slot optimization for closures
// Captured slots are stored in the capturing frame
// Closure creation copies captured slot values into the closure environment
// Closure mutation goes through the original slot

// Module slot management
// Module bindings are stored in module table entries
// Module slots are resolved at compile time, not runtime
