# ============================================================================
# Sandbox Resource Limits - Execution time, memory, allocation limits
# ============================================================================
# Support for optional resource thresholds
# Configuration via CLI flags: --sandbox-memory, --sandbox-time, etc.
# Limit modes: warn, error, stop
# Import depth protection
# Circular import detection
# ============================================================================

import sandbox.sage as sandbox
import sandbox.events.sage as events

# Resource limits configuration
class ResourceLimitsConfig {
    let max_execution_time: Int      // in milliseconds, 0 = unlimited
    let max_memory: Int              // in bytes, 0 = unlimited
    let max_allocations: Int         // 0 = unlimited
    let max_module_count: Int        // 0 = unlimited
    let max_import_depth: Int        // 0 = unlimited
}

# Default resource limits
proc sandbox_default_limits(): ResourceLimitsConfig =
    ResourceLimitsConfig(
        max_execution_time: 0,
        max_memory: 0,
        max_allocations: 0,
        max_module_count: 0,
        max_import_depth: 64
    )

# Limit check result
enum SandboxLimitResult {
    ALLOW
    WARN
    ERROR
    STOP
}

# Check resource limits and return result
proc sandbox_check_limits(config: ResourceLimitsConfig, 
                          execution_time_ms: Float64,
                          memory_bytes: Int,
                          allocation_count: Int,
                          module_count: Int,
                          import_depth: Int): SandboxLimitResult =
    // Check execution time limit
    if config.max_execution_time > 0 and execution_time_ms > config.max_execution_time:
        return SandboxLimitResult.STOP
    
    // Check memory limit
    if config.max_memory > 0 and memory_bytes > config.max_memory:
        return SandboxLimitResult.STOP
    
    // Check allocation limit
    if config.max_allocations > 0 and allocation_count > config.max_allocations:
        return SandboxLimitResult.STOP
    
    // Check module count limit
    if config.max_module_count > 0 and module_count > config.max_module_count:
        return SandboxLimitResult.STOP
    
    // Check import depth limit
    if import_depth > config.max_import_depth:
        return SandboxLimitResult.STOP
    
    return SandboxLimitResult.ALLOW

# Limit mode configuration
class LimitModeConfig {
    let mode: String  // "warn", "error", "stop"
    let auto_terminate: Bool
}

# Get limit mode string
proc sandbox_limit_mode_string(mode: String): String =
    match mode:
        "warn": return "warning"
        "error": return "ResourceLimitError"
        "stop": return "terminates execution"
    return "unknown"

# ============================================================================
# Import Depth Protection
# ============================================================================

# Track import depth during module loading
let import_depth_stack: List[String] = []

# Push import depth
proc sandbox_push_import_depth(module_name: String): Unit =
    import_depth_stack = import_depth_stack + [module_name]

# Pop import depth
proc sandbox_pop_import_depth(): Option[String] =
    if import_depth_stack.is_empty():
        return none
    let top = import_depth_stack.last()
    import_depth_stack = import_depth_stack[:-1]
    return Some(top)

# Current import depth
proc sandbox_current_import_depth(): Int =
    import_depth_stack.len

# Check if import depth exceeds limit
proc sandbox_check_import_depth(max_depth: Int): Bool =
    import_depth_stack.len > max_depth

# ============================================================================
# Circular Import Detection
# ============================================================================

# Module loading states
let module_loading_state: Dict[String, String] = ""  // "UNSEEN", "LOADING", "LOADED", "FAILED"

# Track module loading state
proc sandbox_track_module_state(module_name: String, state: String): Unit =
    module_loading_state[module_name] = state

# Get module loading state
proc sandbox_get_module_state(module_name: String): Option[String] =
    if dict_has(module_loading_state, module_name):
        return Some(module_loading_state[module_name])
    return none

# Detect circular import
proc sandbox_detect_circular_import(module_name: String): Bool =
    // Check if module is currently being loaded (state = "LOADING")
    // and an attempt is made to import it again
    let state = sandbox_get_module_state(module_name)
    return state == "LOADING"

# Emit circular import event
proc sandbox_emit_circular_import(module_name: String, cycle_path: List[String]): Unit =
    if sandbox.SANDBOX_ENABLED:
        events.events.sandbox.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_EXCEPTION,
            none,
            none,
            {
                "type": "circular_import",
                "module": module_name,
                "path": cycle_path
            }
        )

# ============================================================================
# Limit Modes
# ============================================================================

# Warn mode: produce a warning but continue execution
proc sandbox_limit_mode_warn(message: String): Unit =
    print "SANDBOX WARNING: " + message

# Error mode: raise ResourceLimitError
proc sandbox_limit_mode_error(message: String): Unit =
    // Would raise a ResourceLimitError
    // For now, print error
    print "SANDBOX ERROR: " + message

# Stop mode: terminate execution
proc sandbox_limit_mode_stop(message: String): Unit =
    // Would terminate execution
    print "SANDBOX STOP: " + message
    // In real implementation: raise SystemExit or similar

# ============================================================================
# CLI Limit Flags Integration
# ============================================================================

# Parse CLI limit flags
proc sandbox_parse_limit_flags(args: Array<String>): ResourceLimitsConfig =
    let config = sandbox.sandbox_default_limits()
    let i = 0
    while i < len(args):
        let arg = args[i]
        match arg:
            "--sandbox-memory":
                i = i + 1
                if i < len(args):
                    let val = args[i]
                    if val != "0":
                        config.max_memory = val.toInt()
            "--sandbox-time":
                i = i + 1
                if i < len(args):
                    let val = args[i]
                    if val != "0":
                        config.max_execution_time = val.toInt() * 1000  // Convert seconds to ms
            "--sandbox-allocations":
                i = i + 1
                if i < len(args):
                    let val = args[i]
                    if val != "0":
                        config.max_allocations = val.toInt()
            "--sandbox-max-modules":
                i = i + 1
                if i < len(args):
                    let val = args[i]
                    if val != "0":
                        config.max_module_count = val.toInt()
            "--sandbox-max-import-depth":
                i = i + 1
                if i < len(args):
                    let val = args[i]
                    if val != "0":
                        config.max_import_depth = val.toInt()
        i = i + 1
    return config

# ============================================================================
# Backend Parity (sage vs sage-c)
# ============================================================================

# Ensure compatible report structure between sage and sage-c
# The report structure should be the same, with metrics that may differ
# by implementation being indicated as to source and accuracy

# Example compatible report structure:
# {
#     "program": {
#         "path": "app.sage",
#         "runtime_ms": 42.8
#     },
#     "resources": {
#         "memory_peak": 1887436,
#         "allocations": 2842
#     },
#     "modules": [...],
#     "graph": {...}
# }

# Each metric should indicate:
# - source: "runtime_counter", "estimated", "host_metric"
# - accuracy: "exact", "approximate", "unavailable"

# ============================================================================
# CLI Specification (from sandbox.md sections 21-23)
# ============================================================================

# Minimum CLI flags:
# sage --sandbox program.sage
# sage-c --sandbox program.sage

# Modes:
# --sandbox=summary       - Tracks: program runtime, module imports, module load time, total memory, peak memory
# --sandbox=standard      - Tracks: module graph, module resources, execution time, resource snapshots, errors, cache activity (recommended default)
# --sandbox=detailed      - Tracks: function activity, allocation events, detailed module timing, resource timeline, event stream

# Reports:
# --sandbox-report=file.json  - JSON export of sandbox data

# Export:
# --sandbox-export=text     - Text format
# --sandbox-export=json     - JSON format
# --sandbox-export=graph    - Module dependency graph
# --sandbox-export=dot      - DOT format (future)

# Limits:
# --sandbox-memory=128MB    - Maximum memory limit
# --sandbox-time=30s        - Maximum execution time limit
# --sandbox-max-modules=256 - Maximum module count limit
# --sandbox-max-import-depth=64 - Maximum import depth limit

# Environment configuration:
# SAGE_SANDBOX=1              - Enable sandbox
# SAGE_SANDBOX_MODE=standard  - Set mode
# SAGE_SANDBOX_MEMORY=128MB   - Set memory limit

# Compatibility requirements:
# - Sandbox must preserve: program output, import behavior, module cache behavior, exceptions, execution order, language semantics
# - Sandbox must not modify: AST behavior, module resolution, import order, program values
# - Unless an explicit Sandbox resource limit terminates execution

# Backend parity:
# sage report === sage-c report (for same program where metrics are available)
# Metrics may differ by implementation but report structure must be compatible
# Report must indicate: metric source, accuracy, availability