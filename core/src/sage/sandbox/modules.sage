# ============================================================================
# Sandbox Module Observability - Module tracking, import relationships, dependency graph
# ============================================================================
# Primary feature: module observability
# Every import should generate an event
# Module identity uses Module ID (not just name)
# Import relationship tracking: who imported what
# Module graph construction and views
# ============================================================================

import sandbox.sage as sandbox
import sandbox.events.sage as events

# Module tracker - tracks all imported modules
class ModuleTracker {
    let module_registry: Dict[String, sandbox.ModuleInfo]
    let module_graph: sandbox.ModuleGraph
    let import_depth: Int
    let max_import_depth: Int
    
    proc init(max_import_depth: Int): ModuleTracker =
        ModuleTracker(
            module_registry: {} as Dict<String, sandbox.ModuleInfo>,
            module_graph: sandbox.ModuleGraph(nodes: {}, edges: {}),
            import_depth: 0,
            max_import_depth: max_import_depth
        )
    
    // Track a module import request
    proc track_import_request(module_name: String): Unit =
        if not sandbox.SANDBOX_ENABLED:
            return
        
        // Emit import request event
        events.events.sandbox.events.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_MODULE_IMPORT_REQUEST,
            none,
            none,
            {"module_name": module_name}
        )
    
    // Track module resolution
    proc track_module_resolved(module_name: String, module_info: sandbox.ModuleInfo): Unit =
        if not sandbox.SANDBOX_ENABLED:
            return
        
        // Update module registry
        module_registry[module_name] = module_info
        
        // Update module graph
        // ... (would add node and edge)
        
        // Emit resolved event
        events.events.sandbox.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_MODULE_RESOLVED,
            none,
            none,
            {"module_name": module_name, "module_info": module_info}
        )
    
    // Track module load begin
    proc track_module_load_begin(module_name: String): Unit =
        if not sandbox.SANDBOX_ENABLED:
            return
        
        events.events.sandbox.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_MODULE_LOAD_BEGIN,
            none,
            none,
            {"module_name": module_name}
        )
    
    // Track module load complete
    proc track_module_load_complete(module_name: String, load_time: Float64): Unit =
        if not sandbox.SANDBOX_ENABLED:
            return
        
        // Emit load complete event
        events.events.sandbox.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_MODULE_LOAD_COMPLETE,
            none,
            none,
            {"module_name": module_name, "load_time": load_time}
        )
    
    // Track cache hit
    proc track_module_cache_hit(module_name: String): Unit =
        if not sandbox.SANDBOX_ENABLED:
            return
        
        events.events.sandbox.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_MODULE_CACHE_HIT,
            none,
            none,
            {"module_name": module_name}
        )
    
    // Track module load error
    proc track_module_load_error(module_name: String, error: String): Unit =
        if not sandbox.SANDBOX_ENABLED:
            return
        
        events.events.sandbox.sandbox.sandbox.sandbox.event_bus.emit(
            sandbox.events.sandbox.SANDBOX_EVENT_MODULE_LOAD_ERROR,
            none,
            none,
            {"module_name": module_name, "error": error}
        )
    
    // Get module info
    proc get_module_info(module_name: String): Option[sandbox.ModuleInfo] =
        if dict_has(module_registry, module_name):
            return Some(module_registry[module_name])
        return none
    
    // Get all module info
    proc get_all_module_info(): Dict<String, sandbox.ModuleInfo> =
        module_registry
    
    // Check if module is loaded
    proc is_module_loaded(module_name: String): Bool =
        dict_has(module_registry, module_name)
}

# Global module tracker instance
let module_tracker = ModuleTracker(64)  // default max import depth

# Convenience functions
proc sandbox_track_import_request(module_name: String): Unit =
    module_tracker.track_import_request(module_name)

proc sandbox_track_module_resolved(module_name: String, module_info: sandbox.ModuleInfo): Unit =
    module_tracker.track_module_resolved(module_name, module_info)

proc sandbox_track_module_load_begin(module_name: String): Unit =
    module_tracker.track_module_load_begin(module_name)

proc sandbox_track_module_load_complete(module_name: String, load_time: Float64): Unit =
    module_tracker.track_module_load_complete(module_name, load_time)

proc sandbox_track_module_cache_hit(module_name: String): Unit =
    module_tracker.track_module_cache_hit(module_name)

proc sandbox_track_module_load_error(module_name: String, error: String): Unit =
    module_tracker.track_module_load_error(module_name, error)

proc sandbox_get_module_info(module_name: String): Option[sandbox.ModuleInfo] =
    module_tracker.get_module_info(module_name)

proc sandbox_get_all_module_info(): Dict<String, sandbox.ModuleInfo> =
    module_tracker.get_all_module_info()

proc sandbox_is_module_loaded(module_name: String): Bool =
    module_tracker.is_module_loaded(module_name)