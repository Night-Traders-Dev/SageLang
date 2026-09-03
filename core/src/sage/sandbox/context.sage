# ============================================================================
# Sandbox Context - Integration with InterpreterContext
# ============================================================================
# SandboxContext should be owned by InterpreterContext rather than global mutable state
# Target architecture per pipeline.md:
# InterpreterContext
# ├── global_env
# ├── module_cache
# ├── profiler
# ├── capabilities
# └── sandbox_context
#
# When disabled: sandbox_context = nil
# Normal runtime should avoid Sandbox logic wherever possible
# ============================================================================

import sandbox.sage as sandbox

# Add sandbox_context field to InterpreterContext
# This would be done in runtime/context.sage
# class InterpreterContext {
#     ...
#     let sandbox_context: Option[SandboxContext]
# }

# Initialize sandbox_context as nil
proc interpreter_context_init_sandbox(ctx: InterpreterContext): Unit =
    ctx.sandbox_context = none

# Enable sandbox for an interpreter instance
proc interpreter_context_enable_sandbox(ctx: InterpreterContext, config: sandbox.SandboxConfig): Unit =
    sandbox.sandbox_enable(ctx)
    // Initialize with config
    ctx.sandbox_context = sandbox.SandboxContext(
        enabled: true,
        mode: config.mode,
        program_id: "program",
        program_path: "<cmdline>",
        module_registry: {} as Dict<String, sandbox.ModuleInfo>,
        module_graph: sandbox.ModuleGraph(nodes: {} as Dict<String, sandbox.ModuleInfo>, edges: {} as Dict<String, List<sandbox.ModuleEdge>>),
        resource_tracker: sandbox.ResourceTracker(
            program_start_memory: 0,
            program_peak_memory: 0,
            allocations: 0,
            objects: 0,
            execution_start: runtime_current_time(),
            peak_execution_time: 0.0,
            module_deltas: {} as Dict<String, sandbox.ResourceStats>,
            current_module: none
        ),
        event_stream: sandbox.event_bus,
        profiler: sandbox.SandboxProfiler(),
        limits: sandbox.SandboxLimits(
            max_memory: config.max_memory,
            max_time: config.max_time,
            max_allocations: config.max_allocations,
            max_module_count: config.max_module_count,
            max_import_depth: config.max_import_depth
        ),
        configuration: config,
        start_time: runtime_current_time(),
        status: "running"
    )
    // Emit program start event
    sandbox.event_bus.emit(sandbox.SANDBOX_EVENT_PROGRAM_START, none, none, {})

# Disable sandbox for an interpreter instance
proc interpreter_context_disable_sandbox(ctx: InterpreterContext): Unit =
    sandbox.sandbox_disable(ctx)

# Check if sandbox is enabled for current context
proc interpreter_context_sandbox_enabled(ctx: InterpreterContext): Bool =
    SANDBOX_ENABLED and ctx.sandbox_context != none and ctx.sandbox_context.enabled

# Sandbox configuration from CLI flags
proc interpreter_context_from_cli(ctx: InterpreterContext, args: Array<String>): sandbox.SandboxConfig =
    sandbox.sandbox_cli_config(args)

# Module import tracking hooks (would be called from frontend/resolver or interpreter)
proc interpreter_context_module_import(ctx: InterpreterContext, module_name: String): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        sandbox.sandbox_module_import_request(module_name, ctx)

# Module resolution hooks
proc interpreter_context_module_resolved(ctx: InterpreterContext, module_name: String, module_info: sandbox.ModuleInfo): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        sandbox.sandbox_module_resolved(module_name, module_info, ctx)

# Module load hooks
proc interpreter_context_module_load_begin(ctx: InterpreterContext, module_name: String): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        sandbox.sandbox_module_load_begin(module_name, ctx)

proc interpreter_context_module_load_complete(ctx: InterpreterContext, module_name: String, load_time: Float64): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        sandbox.sandbox_module_load_complete(module_name, load_time, ctx)

# Cache hit hook
proc interpreter_context_module_cache_hit(ctx: InterpreterContext, module_name: String): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        sandbox.sandbox_module_cache_hit(module_name, ctx)

# Load error hook
proc interpreter_context_module_load_error(ctx: InterpreterContext, module_name: String, error: String): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        sandbox.sandbox_module_load_error(module_name, error, ctx)

# Resource snapshot
proc interpreter_context_resource_snapshot(ctx: InterpreterContext): sandbox.ResourceSnapshot =
    if sandbox.interpreter_context_sandbox_enabled(ctx):
        return sandbox.sandbox_resource_snapshot(ctx)
    return sandbox.ResourceSnapshot(
        timestamp: 0.0,
        memory_current: 0,
        memory_peak: 0,
        allocations: 0,
        objects: 0,
        execution_time: 0.0,
        cpu_time: 0.0
    )

# Function monitoring hooks
proc interpreter_context_function_enter(ctx: InterpreterContext, fn_val: Value): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx) and sandbox.function_monitor_enabled:
        sandbox.function_enter_hook(fn_val)

proc interpreter_context_function_exit(ctx: InterpreterContext, fn_val: Value): Unit =
    if sandbox.interpreter_context_sandbox_enabled(ctx) and sandbox.function_monitor_enabled:
        sandbox.function_exit_hook(fn_val)

# ============================================================================
# Sandbox Profiler (optional detailed profiling)
# ============================================================================

class SandboxProfiler {
    let function_stats: Dict<String, sandbox.FunctionStats>
    let module_stats: sandbox.ModuleStats
    
    // Function statistics
    class FunctionStats {
        let function_id: String
        let name: String
        let module_id: String
        let call_count: Int
        let total_time: Float64
        let self_time: Float64
        let inclusive_time: Float64
        let allocation_count: Int
    }
    
    class ModuleStats {
        let module_id: String
        let name: String
        let call_count: Int
        let total_time: Float64
        let self_time: Float64
        let inclusive_time: Float64
        let allocation_count: Int
    }
}

# ============================================================================
# Sandbox Limits
# ============================================================================

class SandboxLimits {
    let max_memory: Option<Int>     // in bytes, 0 = unlimited
    let max_time: Option<Int>       // in milliseconds, 0 = unlimited
    let max_allocations: Option<Int>
    let max_module_count: Int       // 0 = unlimited
    let max_import_depth: Int
}

# Check limits and potentially trigger actions
proc sandbox_check_limits(ctx: InterpreterContext, limits: sandbox.SandboxLimits): Bool =
    // Check memory limit
    if limits.max_memory != 0:
        // Would check current memory usage
        true  // Placeholder
    else:
        true
    
    // Check time limit
    if limits.max_time != 0:
        // Would check elapsed time
        true  // Placeholder
    else:
        true
    
    // Check allocation limit
    if limits.max_allocations != none:
        // Would check allocation count
        true  // Placeholder
    else:
        true
    
    // Check module count limit
    if ctx.sandbox_context.module_registry.len > limits.max_module_count and limits.max_module_count > 0:
        return false
    return true

# ============================================================================
# Report Generation
# ============================================================================

# Generate text report
proc sandbox_generate_text_report(ctx: InterpreterContext): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "SAGE SANDBOX REPORT\n"
    sb = sb + "==================\n\n"
    sb = sb + "Program: " + ctx.sandbox_context.program_path + "\n"
    sb = sb + "Runtime: " + ctx.sandbox_context.resource_tracker.execution_time.ToString() + " ms\n"
    sb = sb + "Peak Memory: " + ctx.sandbox_context.resource_tracker.program_peak_memory.ToString() + " bytes\n"
    sb = sb + "\n"
    sb = sb + "Modules:\n"
    for (name, info) in ctx.sandbox_context.module_registry:
        sb = sb + "  " + name + ": load_time=" + info.load_time.ToString() + "ms, "
        sb = sb + "memory=" + info.direct_resources.memory_peak.ToString() + "bytes, "
        sb = sb + "imported_by=" + info.importers.keys.ToString() + "\n"
    sb = sb + "\n"
    sb = sb + "Events: " + ctx.sandbox_context.event_stream.handlers.len.ToString() + "\n"
    sb = sb + "Status: " + ctx.sandbox_context.status + "\n"
    return sb

# Generate JSON report
proc sandbox_generate_json_report(ctx: InterpreterContext): String =
    if ctx.sandbox_context == none:
        return "{}"
    
    // Build JSON object as string
    let sb = "{"
    sb = sb + "\"program\": \"" + ctx.sandbox_context.program_path + "\", "
    sb = sb + "\"runtime_ms\": " + ctx.sandbox_context.resource_tracker.execution_time.ToString() + ", "
    sb = sb + "\"peak_memory\": " + ctx.sandbox_context.resource_tracker.program_peak_memory.ToString()
    sb = sb + "}"
    return sb

# ============================================================================
# Export Formats
# ============================================================================

# Export module graph as text
proc sandbox_export_graph_text(ctx: InterpreterContext): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "Module Dependency Graph\n"
    sb = sb + "-----------------------\n"
    for (name, info) in ctx.sandbox_context.module_registry:
        sb = sb + name + "\n"
        for (dep_name, dep_info) in info.dependencies:
            sb = sb + "  -> " + dep_name + "\n"
    return sb

# ============================================================================
# Default Configuration and CLI Entry
# ============================================================================

# Default sandbox configuration
proc sandbox_default_config(): sandbox.SandboxConfig =
    sandbox.sandbox_config_default()

# CLI entry point configuration
proc sandbox_cli_entry(args: Array<String>): sandbox.SandboxConfig =
    // Parse --sandbox flags
    let config = sandbox.sandbox_default_config()
    
    let i = 0
    while i < len(args):
        let arg = args[i]
        match arg:
            "--sandbox":
                config.mode = sandbox.SANDBOX_MODE_STANDARD
            "--sandbox=summary":
                config.mode = sandbox.SANDBOX_MODE_SUMMARY
            "--sandbox=standard":
                config.mode = sandbox.SANDBOX_MODE_STANDARD
            "--sandbox=detailed":
                config.mode = sandbox.SANDBOX_MODE_DETAILED
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

# ============================================================================
# Zero-Cost Disabled Path Guarantee
# ============================================================================

# When SANDBOX_ENABLED is false:
# - All sandbox tracking is a no-op
# - EventBus.emit with disabled type is a no-op
# - Function monitors are no-ops
# - Resource tracking does not increment counters
# - No memory is allocated for sandbox data structures
# - Dashboard is not displayed
# - CLI --sandbox flag has no effect

# The architecture ensures:
# sage program.sage              === (no sandbox) === sage program.sage
# sage --sandbox program.sage    === (minimal overhead) === approximately same

# Verification:
# Running without --sandbox should produce identical output to running with --sandbox
# (modulo the optional dashboard display which is separate from program output)
# The sandbox must not modify AST behavior, change module resolution,
# change import order, or change program values.

# ============================================================================