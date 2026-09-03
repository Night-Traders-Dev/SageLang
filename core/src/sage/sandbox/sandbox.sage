// ============================================================================
# Sandbox - Runtime observability and monitoring system for SageLang
# ============================================================================
// Pure Sage implementation for portability and self-hosted compatibility
// Activation: optional via --sandbox flag
// Design principle: "Sage Sandbox must observe the runtime without becoming a
// required runtime dependency or changing program semantics."
// ============================================================================

// Sandbox activation state
let SANDBOX_ENABLED = false

// Sandbox mode constants
let SANDBOX_MODE_OFF = 0
let SANDBOX_MODE_SUMMARY = 1
let SANDBOX_MODE_STANDARD = 2
let SANDBOX_MODE_DETAILED = 3

// Sandbox configuration
class SandboxConfig {
    let mode: Int
    let enable_modules: Bool
    let enable_resources: Bool
    let enable_functions: Bool
    let enable_timeline: Bool
    let enable_errors: Bool
    let max_memory: Option<Int>  // in bytes, 0 = unlimited
    let max_time: Option<Int>    // in milliseconds, 0 = unlimited
    let max_allocations: Option<Int>
    let max_module_count: Int
    let max_import_depth: Int
    let sample_rate: Int         // 1 = all, 10 = 1/10, 100 = 1/100
}

// Default sandbox configuration
proc sandbox_config_default(): SandboxConfig = SandboxConfig(
    mode: SANDBOX_MODE_STANDARD,
    enable_modules: true,
    enable_resources: true,
    enable_functions: true,
    enable_timeline: true,
    enable_errors: true,
    max_memory: none,
    max_time: none,
    max_allocations: none,
    max_module_count: 0,  // 0 = unlimited
    max_import_depth: 64,
    sample_rate: 1
)

// Sandbox context for a single execution
class SandboxContext {
    let enabled: Bool
    let mode: Int
    let program_id: String
    let program_path: String
    let module_registry: Dict<String, ModuleInfo>
    let module_graph: ModuleGraph
    let resource_tracker: ResourceTracker
    let event_stream: EventStream
    let profiler: SandboxProfiler
    let limits: SandboxLimits
    let configuration: SandboxConfig
    let start_time: Float64
    let status: String
}

// Module information
class ModuleInfo {
    let id: String              // Unique module identifier (e.g., "module:crypto:ab12")
    let name: String            // Module name (e.g., "crypto")
    let path: String            // Canonical path (e.g., "std/crypto.sage")
    let state: String           // "UNSEEN", "LOADING", "LOADED", "FAILED"
    let importers: Dict<String, ModuleEdge>  // importer_name -> ModuleEdge
    let dependencies: Dict<String, ModuleInfo>  // dependency_name -> ModuleInfo
    let load_time: Float64      // Time in seconds
    let execution_time: Float64 // Time in seconds
    let direct_resources: ResourceStats
    let inclusive_resources: ResourceStats
    let load_count: Int
    let cache_hits: Int
    let status: String
}

// Module edge (import relationship)
class ModuleEdge {
    let importer_id: String     // Module ID of importer
    let imported_id: String     // Module ID of imported
    let import_type: String     // "direct", "lazy", etc.
    let timestamp: Float64
    let load_time: Float64
    let status: String          // "success", "error", "cache_hit"
}

// Module graph
class ModuleGraph {
    let nodes: Dict<String, ModuleInfo>
    let edges: Dict<String, List<ModuleEdge>>
    // Edge key format: "importer_id:imported_id"
}

// Resource statistics
class ResourceStats {
    let memory_current: Int     // Current memory in bytes
    let memory_peak: Int        // Peak memory in bytes
    let allocations: Int        // Allocation count
    let objects: Int            // Object count
    let execution_time: Float64 // Execution time in seconds
    let cpu_time: Float64       // CPU time in seconds
}

// Resource tracker
class ResourceTracker {
    let program_start_memory: Int
    let program_peak_memory: Int
    let allocations: Int
    let objects: Int
    let execution_start: Float64
    let peak_execution_time: Float64
    let module_deltas: Dict<String, ResourceStats>  // module_name -> ResourceStats
    let current_module: Option[String]  // Currently executing module
}

// Event types
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

// Sandbox event
class SandboxEvent {
    let id: Int              // Event sequence number
    let type: Int            // Event type constant
    let timestamp: Float64   // Time in seconds since program start
    let module_id: Option[String]
    let function_id: Option[String]
    let payload: Dict<String, Value>
    let resource_snapshot: Option[ResourceSnapshot]
}

// Resource snapshot
class ResourceSnapshot {
    let timestamp: Float64
    let memory_current: Int
    let memory_peak: Int
    let allocations: Int
    let objects: Int
    let execution_time: Float64
    let cpu_time: Float64
}

// Event bus (simple implementation)
class EventBus {
    let handlers: Dict<String, List<(SandboxEvent -> None)>>
    
    proc handler(name: String, handler: (SandboxEvent -> None)): Unit =
        if not dict_has(handlers, name):
            handlers[name] = []
        handlers[name] = handlers[name] + handler
    
    proc emit(type: Int, module_id: Option[String] = none, 
              function_id: Option[String] = none, payload: Dict<String, Value> = {}): Unit =
        let event = SandboxEvent(
            id: event_bus_next_id,
            type: type,
            timestamp: runtime_current_time(),
            module_id: module_id,
            function_id: function_id,
            payload: payload,
            resource_snapshot: none
        )
        event_bus_next_id = event_bus_next_id + 1
        let handlers_list = dict_get(handlers, type, [])
        for handler in handlers_list:
            handler(event)
}

// Singleton event bus
let event_bus = EventBus()
let event_bus_next_id = 0

// Runtime helper functions
proc runtime_current_time(): Float64 = // Use host clock or approximate
    // For pure Sage implementation, use approximate time
    0.0  // Would be provided by host runtime

// Sandbox configuration from CLI
proc sandbox_cli_config(args: Array<String>): SandboxConfig =
    let config = sandbox_config_default()
    let i = 0
    while i < len(args):
        let arg = args[i]
        match arg:
            "--sandbox":
                config.mode = SANDBOX_MODE_STANDARD
            "--sandbox=summary":
                config.mode = SANDBOX_MODE_SUMMARY
            "--sandbox=standard":
                config.mode = SANDBOX_MODE_STANDARD
            "--sandbox=detailed":
                config.mode = SANDBOX_MODE_DETAILED
            "--sandbox-memory":
                i = i + 1
                if i < len(args):
                    config.max_memory = Some(args[i].toInt())
            "--sandbox-time":
                i = i + 1
                if i < len(args):
                    config.max_time = Some(args[i].toInt())
            "--sandbox-max-modules":
                i = i + 1
                if i < len(args):
                    config.max_module_count = args[i].toInt()
            "--sandbox-max-import-depth":
                i = i + 1
                if i < len(args):
                    config.max_import_depth = args[i].toInt()
            "--sandbox-sample":
                i = i + 1
                if i < len(args):
                    config.sample_rate = args[i].toInt()
        i = i + 1
    return config

// Sandbox enable/disable
proc sandbox_enable(ctx: InterpreterContext): Unit =
    SANDBOX_ENABLED = true
    ctx.sandbox_context = SandboxContext(
        enabled: true,
        mode: sandbox_cli_config(/* args */ []).mode,
        program_id: "program",
        program_path: "<cmdline>",
        module_registry: {} as Dict<String, ModuleInfo>,
        module_graph: ModuleGraph(nodes: {}, edges: {}),
        resource_tracker: ResourceTracker(
            program_start_memory: 0,
            program_peak_memory: 0,
            allocations: 0,
            objects: 0,
            execution_start: 0.0,
            peak_execution_time: 0.0,
            module_deltas: {} as Dict<String, ResourceStats>,
            current_module: none
        ),
        event_stream: EventBus(),
        profiler: SandboxProfiler(),
        limits: SandboxLimits(
            max_memory: sandbox_cli_config(/* args */ []).max_memory,
            max_time: sandbox_cli_config(/* args */ []).max_time,
            max_allocations: sandbox_cli_config(/* args */ []).max_allocations,
            max_module_count: sandbox_cli_config(/* args */ []).max_module_count,
            max_import_depth: sandbox_cli_config(/* args */ []).max_import_depth
        ),
        configuration: sandbox_cli_config(/* args */ []),
        start_time: runtime_current_time(),
        status: "running"
    )
    // Emit program start event
    event_bus.emit(SANDBOX_EVENT_PROGRAM_START, none, none, {})

proc sandbox_disable(ctx: InterpreterContext): Unit =
    SANDBOX_ENABLED = false
    if ctx.sandbox_context != none:
        ctx.sandbox_context.status = "disabled"
        event_bus.emit(SANDBOX_EVENT_PROGRAM_END, none, none, {})
    ctx.sandbox_context = none

// InterpreterContext integration
// Add sandbox_context field to InterpreterContext
// (Would be added to runtime/context.sage)

// Module import tracking
proc sandbox_module_import_request(module_name: String, ctx: InterpreterContext): Unit =
    if not SANDBOX_ENABLED or ctx.sandbox_context == none:
        return
    
    let config = ctx.sandbox_context.configuration
    if not config.enable_modules:
        return
    
    // Emit import request event
    event_bus.emit(
        SANDBOX_EVENT_MODULE_IMPORT_REQUEST,
        none,  // module_id would be resolved later
        none,
        {"module_name": module_name}
    )

proc sandbox_module_resolved(module_name: String, module_info: ModuleInfo, ctx: InterpreterContext): Unit =
    if not SANDBOX_ENABLED or ctx.sandbox_context == none:
        return
    
    let config = ctx.sandbox_context.configuration
    if not config.enable_modules:
        return
    
    // Update module registry
    ctx.sandbox_context.module_registry[module_name] = module_info
    
    // Update module graph
    // ... (would add node and edge)
    
    // Emit resolved event
    event_bus.emit(
        SANDBOX_EVENT_MODULE_RESOLVED,
        none,
        none,
        {"module_name": module_name, "module_info": module_info}
    )

proc sandbox_module_load_begin(module_name: String, ctx: InterpreterContext): Unit =
    if not SANDBOX_ENABLED or ctx.sandbox_context == none:
        return
    
    let config = ctx.sandbox_context.configuration
    if not config.enable_modules:
        return
    
    // Record start time
    // ... 
    
    // Emit load begin event
    event_bus.emit(
        SANDBOX_EVENT_MODULE_LOAD_BEGIN,
        none,
        none,
        {"module_name": module_name}
    )

proc sandbox_module_load_complete(module_name: String, load_time: Float64, ctx: InterpreterContext): Unit =
    if not SANDBOX_ENABLED or ctx.sandbox_context == none:
        return
    
    let config = ctx.sandbox_context.configuration
    if not config.enable_modules:
        return
    
    // Update module info
    // ...
    
    // Emit load complete event
    event_bus.emit(
        SANDBOX_EVENT_MODULE_LOAD_COMPLETE,
        none,
        none,
        {"module_name": module_name, "load_time": load_time}
    )

proc sandbox_module_cache_hit(module_name: String, ctx: InterpreterContext): Unit =
    if not SANDBOX_ENABLED or ctx.sandbox_context == none:
        return
    
    event_bus.emit(
        SANDBOX_EVENT_MODULE_CACHE_HIT,
        none,
        none,
        {"module_name": module_name}
    )

proc sandbox_module_load_error(module_name: String, error: String, ctx: InterpreterContext): Unit =
    if not SANDBOX_ENABLED or ctx.sandbox_context == none:
        return
    
    event_bus.emit(
        SANDBOX_EVENT_MODULE_LOAD_ERROR,
        none,
        none,
        {"module_name": module_name, "error": error}
    )

// Resource tracking
proc sandbox_resource_snapshot(ctx: InterpreterContext): ResourceSnapshot =
    if ctx.sandbox_context == none:
        return ResourceSnapshot(
            timestamp: 0.0,
            memory_current: 0,
            memory_peak: 0,
            allocations: 0,
            objects: 0,
            execution_time: 0.0,
            cpu_time: 0.0
        )
    
    // Get current resource usage
    // Would use host runtime counters or pure Sage estimates
    return ResourceSnapshot(
        timestamp: runtime_current_time(),
        memory_current: 0,  // Would get from host
        memory_peak: 0,     // Would get from host
        allocations: 0,     // Would count from host
        objects: 0,         // Would count from host
        execution_time: runtime_current_time() - ctx.sandbox_context.start_time,
        cpu_time: 0.0       // Would get from host
    )

// Function monitoring
let function_monitor_enabled = false
let function_enter_handlers: List<(Value -> None)> = []
let function_exit_handlers: List<(Value -> None)> = []

proc function_monitor_enable(): Unit =
    function_monitor_enabled = true

proc function_monitor_disable(): Unit =
    function_monitor_enabled = false

proc function_enter_hook(value: Value): Unit =
    if function_monitor_enabled:
        for handler in function_enter_handlers:
            handler(value)

proc function_exit_hook(value: Value): Unit =
    if function_monitor_enabled:
        for handler in function_exit_handlers:
            handler(value)

// ============================================================================
# Sandbox CLI Integration
# ============================================================================

// Sandbox CLI modes
proc sandbox_mode_to_string(mode: Int): String =
    match mode:
        SANDBOX_MODE_OFF: return "off"
        SANDBOX_MODE_SUMMARY: return "summary"
        SANDBOX_MODE_STANDARD: return "standard"
        SANDBOX_MODE_DETAILED: return "detailed"
    return "unknown"

// ============================================================================
# Zero-Cost Disabled Path
# ============================================================================

// When sandbox is disabled, all operations should be no-ops
proc sandbox_disabled_check(): Bool =
    not SANDBOX_ENABLED

// All sandbox functions should check this at the start and return early if disabled
// The EventBus.emit and other operations should be bound to no-op functions when disabled

// ============================================================================
# Compatibility
# ============================================================================

// Ensure sandbox does not change program semantics
// All operations are conditional on SANDBOX_ENABLED flag
// When disabled, all tracking is a no-op

// The sandbox should preserve:
// - Program output
// - Import behavior  
// - Module cache behavior
// - Exceptions
// - Execution order
// - Language semantics

// Verification:
// sage --sandbox hello.sage should produce same output as sage hello.sage
// sage-c --sandbox hello.sage should produce compatible report