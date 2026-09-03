// ============================================================================
# Sandbox Event System - Common event model for all Sandbox activity
# ============================================================================
// All Sandbox activity should use this common event model.
// Event types define what happened; the EventBus dispatches them.
// Event system should avoid expensive allocations when possible.
// Recommended modes: OFF, SUMMARY, STANDARD, DETAILED
// ============================================================================

// Event ID counter (module-global, reset per program execution)
let sandbox_event_next_id = 0

// Sandbox event types
let SANDBOX_EVENT_PROGRAM_START = 0
let SANDBOX_EVENT_PROGRAM_END = 1
let SANDBOX_EVENT_MODULE_IMPORT_REQUEST = 2
let SANDBOX_EVENT_MODULE_RESOLVED = 3
let SANDBOX_EVENT_MODULE_LOAD_BEGIN = 4
let SANDBOX_EVENT_MODULE_LOAD_COMPLETE = 5
let SANDBOX_EVENT_MODULE_CACHE_HIT = 6
let SANDBOX_EVENT_MODULE_LOAD_ERROR = 7
let SANDBOX_EVENT_FUNCTION_ENTER = 8
let SANDBOX_EVENT_FUNCTION_EXIT = 9
let SANDBOX_EVENT_ALLOCATION = 10
let SANDBOX_EVENT_DEALLOCATION = 11
let SANDBOX_EVENT_RESOURCE_SNAPSHOT = 12
let SANDBOX_EVENT_RESOURCE_LIMIT = 13
let SANDBOX_EVENT_EXCEPTION = 13
let SANDBOX_EVENT_RUNTIME_ERROR = 14

// Sandbox event structure
class SandboxEvent {
    let id: Int              // Unique event sequence number
    let type: Int            // One of the SANDBOX_EVENT_* constants
    let timestamp: Float64   // Time in seconds since program start
    let module_id: Option[String]  // Module ID if applicable
    let function_id: Option[String]  // Function ID if applicable
    let payload: Dict<String, Any>  // Event-specific data
    let resource_snapshot: Option[ResourceSnapshot]  // Resource snapshot if applicable
}

// Resource snapshot for events
class ResourceSnapshot {
    let timestamp: Float64
    let memory_current: Int
    let memory_peak: Int
    let allocations: Int
    let objects: Int
    let execution_time: Float64
    let cpu_time: Float64
}

// Event bus (singleton, no-op when sandbox disabled)
class EventBus {
    // Handler type: takes a SandboxEvent and returns nothing
    let handlers: Dict<String, List<(SandboxEvent -> None)>>
    
    // Initialize handler dict
    proc init(): EventBus = EventBus(
        handlers: {} as Dict<String, List<(SandboxEvent -> None)>>
    )
    
    // Register a handler for an event type
    proc handler(name: String, handler: (SandboxEvent -> None)): Unit =
        if not dict_has(handlers, name):
            handlers[name] = []
        handlers[name] = handlers[name] + handler
    
    // Emit an event to all registered handlers
    // When sandbox is disabled, this should be a no-op
    proc emit(type: Int, module_id: Option[String] = none, 
              function_id: Option[String] = none, 
              payload: Dict<String, Any> = {}): Unit =
        if not SANDBOX_ENABLED:
            return  // Zero-cost disabled path
        
        let event = SandboxEvent(
            id: sandbox_event_next_id,
            type: type,
            timestamp: runtime_current_time(),
            module_id: module_id,
            function_id: function_id,
            payload: payload,
            resource_snapshot: none
        )
        sandbox_event_next_id = sandbox_event_next_id + 1
        
        let handlers_list = dict_get(handlers, type, [])
        for handler in handlers_list:
            handler(event)
}

// Singleton event bus instance
let event_bus = EventBus().init()

// Runtime time helper (would be provided by host)
// Returns current time in seconds since program start
proc runtime_current_time(): Float64 =
    // In pure Sage implementation, this would use host runtime clock
    // or approximate time based on operations
    0.0  // Placeholder - host would provide actual time

// Event types as strings for debugging
proc event_type_to_string(type: Int): String =
    match type:
        SANDBOX_EVENT_PROGRAM_START: return "PROGRAM_START"
        SANDBOX_EVENT_PROGRAM_END: return "PROGRAM_END"
        SANDBOX_EVENT_MODULE_IMPORT_REQUEST: return "MODULE_IMPORT_REQUEST"
        SANDBOX_EVENT_MODULE_RESOLVED: return "MODULE_RESOLVED"
        SANDBOX_EVENT_MODULE_LOAD_BEGIN: return "MODULE_LOAD_BEGIN"
        SANDBOX_EVENT_MODULE_LOAD_COMPLETE: return "MODULE_LOAD_COMPLETE"
        SANDBOX_EVENT_MODULE_CACHE_HIT: return "MODULE_CACHE_HIT"
        SANDBOX_EVENT_MODULE_LOAD_ERROR: return "MODULE_LOAD_ERROR"
        SANDBOX_EVENT_FUNCTION_ENTER: return "FUNCTION_ENTER"
        SANDBOX_EVENT_FUNCTION_EXIT: return "FUNCTION_EXIT"
        SANDBOX_EVENT_ALLOCATION: return "ALLOCATION"
        SANDBOX_EVENT_DEALLOCATION: return "DEALLOCATION"
        SANDBOX_EVENT_RESOURCE_SNAPSHOT: return "RESOURCE_SNAPSHOT"
        SANDBOX_EVENT_RESOURCE_LIMIT: return "RESOURCE_LIMIT"
        SANDBOX_EVENT_EXCEPTION: return "EXCEPTION"
        SANDBOX_EVENT_RUNTIME_ERROR: return "RUNTIME_ERROR"
    return "UNKNOWN"

// ============================================================================
# Event Handler Registration (for frontend/interpreter integration)
# ============================================================================

// Register handlers for Sandbox events from the interpreter/frontend
// These would be called from the interpreter when sandbox is enabled

proc sandbox_register_program_start_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_PROGRAM_START, handler)

proc sandbox_register_program_end_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_PROGRAM_END, handler)

proc sandbox_register_module_import_request_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_MODULE_IMPORT_REQUEST, handler)

proc sandbox_register_module_resolved_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_MODULE_RESOLVED, handler)

proc sandbox_register_module_load_begin_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_MODULE_LOAD_BEGIN, handler)

proc sandbox_register_module_load_complete_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_MODULE_LOAD_COMPLETE, handler)

proc sandbox_register_module_cache_hit_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_MODULE_CACHE_HIT, handler)

proc sandbox_register_module_load_error_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_MODULE_LOAD_ERROR, handler)

proc sandbox_register_function_enter_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_FUNCTION_ENTER, handler)

proc sandbox_register_function_exit_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_FUNCTION_EXIT, handler)

proc sandbox_register_allocation_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_ALLOCATION, handler)

proc sandbox_register_deallocation_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_DEALLOCATION, handler)

proc sandbox_register_resource_snapshot_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_RESOURCE_SNAPSHOT, handler)

proc sandbox_register_resource_limit_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_RESOURCE_LIMIT, handler)

proc sandbox_register_exception_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_EXCEPTION, handler)

proc sandbox_register_runtime_error_handler(handler: (SandboxEvent -> None)): Unit =
    event_bus.handler(SANDBOX_EVENT_RUNTIME_ERROR, handler)

// ============================================================================
# Sandbox Modes
# ============================================================================

// Sandbox mode constants
let SANDBOX_MODE_OFF = 0
let SANDBOX_MODE_SUMMARY = 1
let SANDBOX_MODE_STANDARD = 2
let SANDBOX_MODE_DETAILED = 3

// Mode descriptions
proc sandbox_mode_description(mode: Int): String =
    match mode:
        SANDBOX_MODE_OFF: return "No tracking. Normal execution."
        SANDBOX_MODE_SUMMARY: return "Summary mode: program runtime, module imports, module load time, total memory, peak memory."
        SANDBOX_MODE_STANDARD: return "Standard mode: module graph, module resources, execution time, resource snapshots, errors, cache activity."
        SANDBOX_MODE_DETAILED: return "Detailed mode: function activity, allocation events, detailed module timing, resource timeline, event stream."
    return "unknown"

// Sandbox mode configuration
class SandboxModeConfig {
    let mode: Int
    let enable_modules: Bool
    let enable_resources: Bool
    let enable_functions: Bool
    let enable_timeline: Bool
    let enable_errors: Bool
    let sample_rate: Int  // 1 = all events, 10 = 1/10 sampled, 100 = 1/100 sampled
}

// Default modes
proc sandbox_summary_config(): SandboxModeConfig =
    SandboxModeConfig(
        mode: SANDBOX_MODE_SUMMARY,
        enable_modules: true,
        enable_resources: true,
        enable_functions: false,
        enable_timeline: true,
        enable_errors: true,
        sample_rate: 1
    )

proc sandbox_standard_config(): SandboxModeConfig =
    SandboxModeConfig(
        mode: SANDBOX_MODE_STANDARD,
        enable_modules: true,
        enable_resources: true,
        enable_functions: true,
        enable_timeline: true,
        enable_errors: true,
        sample_rate: 1
    )

proc sandbox_detailed_config(): SandboxModeConfig =
    SandboxModeConfig(
        mode: SANDBOX_MODE_DETAILED,
        enable_modules: true,
        enable_resources: true,
        enable_functions: true,
        enable_timeline: true,
        enable_errors: true,
        sample_rate: 1
    )

// ============================================================================
# Sampling Support
# ============================================================================

// Check if an event should be sampled based on sample_rate
proc sandbox_should_sample(sample_rate: Int): Bool =
    // Simple deterministic sampling
    // In production, would use a proper random or round-robin approach
    if sample_rate <= 1:
        return true
    if sample_rate >= 100:
        return false
    // 1/in sample_rate chance
    import random
    return random.random() < (1.0 / Float64(sample_rate))

// ============================================================================
# Sandbox Limits and Enforcement
# ============================================================================

// Resource limit check result
enum SandboxLimitResult {
    ALLOW
    WARN
    ERROR
    STOP
}

// Check a resource limit and return result
proc sandbox_check_resource_limit(
    limit_type: String,
    current: Int,
    limit: Int
): SandboxLimitResult =
    if limit == 0:
        return SandboxLimitResult.ALLOW  // Unlimited
    if current >= limit:
        // Determine result based on configuration
        // This would be checked per-mode
        return SandboxLimitResult.WARN  // Placeholder
    return SandboxLimitResult.ALLOW

// ============================================================================
# Integration with Interpreter Hooks
# ============================================================================

// These hooks would be called from the interpreter main loop
// when sandbox is enabled

// Program lifecycle hooks
proc sandbox_hook_program_start(): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(SANDBOX_EVENT_PROGRAM_START, none, none, {})

proc sandbox_hook_program_end(): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(SANDBOX_EVENT_PROGRAM_END, none, none, {})

// Module import hooks
proc sandbox_hook_module_import_request(module_name: String): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_MODULE_IMPORT_REQUEST,
            none,
            none,
            {"module_name": module_name}
        )

proc sandbox_hook_module_resolved(module_name: String, module_info: sandbox.ModuleInfo): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_MODULE_RESOLVED,
            none,
            none,
            {"module_name": module_name, "module_info": module_info}
        )

proc sandbox_hook_module_load_begin(module_name: String): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_MODULE_LOAD_BEGIN,
            none,
            none,
            {"module_name": module_name}
        )

proc sandbox_hook_module_load_complete(module_name: String, load_time: Float64): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_MODULE_LOAD_COMPLETE,
            none,
            none,
            {"module_name": module_name, "load_time": load_time}
        )

proc sandbox_hook_module_cache_hit(module_name: String): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_MODULE_CACHE_HIT,
            none,
            none,
            {"module_name": module_name}
        )

proc sandbox_hook_module_load_error(module_name: String, error: String): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_MODULE_LOAD_ERROR,
            none,
            none,
            {"module_name": module_name, "error": error}
        )

// Function monitoring hooks
proc sandbox_hook_function_enter(fn_val: Value): Unit =
    if SANDBOX_ENABLED and sandbox.function_monitor_enabled:
        function_enter_hook(fn_val)
        event_bus.emit(
            SANDBOX_EVENT_FUNCTION_ENTER,
            none,
            {"function_id": fn_val.ToString() if fn_val != none else none},
            {}
        )

proc sandbox_hook_function_exit(fn_val: Value): Unit =
    if SANDBOX_ENABLED and sandbox.function_monitor_enabled:
        function_exit_hook(fn_val)
        event_bus.emit(
            SANDBOX_EVENT_FUNCTION_EXIT,
            none,
            {"function_id": fn_val.ToString() if fn_val != none else none},
            {}
        )

// Resource snapshot hook
proc sandbox_hook_resource_snapshot(): Unit =
    if SANDBOX_ENABLED:
        snapshot = sandbox.sandbox_resource_snapshot(/* ctx */)
        event_bus.emit(
            SANDBOX_EVENT_RESOURCE_SNAPSHOT,
            none,
            none,
            {"snapshot": snapshot}
        )

// Exception hook
proc sandbox_hook_exception(exception: Value): Unit =
    if SANDBOX_ENABLED:
        event_bus.emit(
            SANDBOX_EVENT_EXCEPTION,
            none,
            none,
            {"exception": exception}
        )

// Resource limit hook
proc sandbox_hook_resource_limit(limit_type: String, current: Int, limit: Int): Unit =
    if SANDBOX_ENABLED:
        result = sandbox.sandbox_check_resource_limit(limit_type, current, limit)
        event_bus.emit(
            SANDBOX_EVENT_RESOURCE_LIMIT,
            none,
            none,
            {"limit_type": limit_type, "current": current, "limit": limit, "result": result}
        )