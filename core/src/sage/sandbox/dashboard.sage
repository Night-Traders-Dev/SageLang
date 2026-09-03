# ============================================================================
# Sandbox Dashboard - Terminal-based dashboard architecture
# ============================================================================
# First dashboard should be terminal-based, pure Sage implementation
# Recommended: Pure Sage TUI
# ============================================================================

import sandbox.sage as sandbox
import sandbox.events.sage as events
import sandbox.resources.sage as resources
import sandbox.limits.sage as limits

# Dashboard modes
let DASHBOARD_MODE_OVERVIEW = 0
let DASHBOARD_MODE_MODULES = 1
let DASHBOARD_MODE_RESOURCES = 2
let DASHBOARD_MODE_TIMELINE = 3
let DASHBOARD_MODE_ERRORS = 4

# Dashboard state
class DashboardState {
    let mode: Int
    let show_help: Bool
    let filter_module: Option[String]
}

# Create default dashboard state
proc dashboard_state_default(): DashboardState =
    DashboardState(
        mode: DASHBOARD_MODE_OVERVIEW,
        show_help: false,
        filter_module: none
    )

# Dashboard rendering functions

# Render the main dashboard screen
proc dashboard_render_main(ctx: sandbox.InterpreterContext, state: DashboardState): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "SAGE SANDBOX                              " + 
           (if state.mode == DASHBOARD_MODE_OVERVIEW then "RUNNING" else "") + "\n"
    sb = sb + "========================================================\n\n"
    sb = sb + "Program: " + ctx.sandbox_context.program_path + "\n"
    sb = sb + "Runtime: " + ctx.sandbox_context.resource_tracker.execution_time.ToString() + " ms\n"
    sb = sb + "Peak Memory: " + ctx.sandbox_context.resource_tracker.program_peak_memory.ToString() + " bytes\n\n"
    sb = sb + "MODULES: " + ctx.sandbox_context.module_registry.len.ToString() + "\n\n"
    sb = sb + "SELECTED: (none)\n\n"
    sb = sb + "Load Time:      -- ms\n"
    sb = sb + "Execution:      -- ms\n"
    sb = sb + "Memory:         -- bytes\n"
    sb = sb + "Allocations:    --\n\n"
    sb = sb + "--------------------------------------------------------\n"
    sb = sb + "  [ ] Module view       M\n"
    sb = sb + "  [ ] Resource view     R\n"
    sb = sb + "  [ ] Timeline          T\n"
    sb = sb + "  [ ] Errors            E\n"
    sb = sb + "  [ ] Help              H\n"
    sb = sb + "  [ ] Quit              Q\n"
    sb = sb + "========================================================\n"
    return sb

# Render module dashboard
proc dashboard_render_modules(ctx: sandbox.InterpreterContext, state: DashboardState): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "SAGE SANDBOX - MODULE VIEW\n"
    sb = sb + "================================\n\n"
    sb = sb + "Program: " + ctx.sandbox_context.program_path + "\n\n"
    
    // Show module tree
    sb = sb + "Module Tree:\n"
    for (name, info) in ctx.sandbox_context.module_registry:
        sb = sb + "  ▼ " + name + "\n"
        // Would show dependencies
        sb = sb + "    ├── Dependencies: " + info.importers.len.ToString() + "\n"
    sb = sb + "\n"
    
    // Selected module details (if filtered)
    if state.filter_module != none and dict_has(ctx.sandbox_context.module_registry, state.filter_module):
        let info = ctx.sandbox_context.module_registry[state.filter_module]
        sb = sb + "SELECTED: " + state.filter_module + "\n\n"
        sb = sb + "Load Time:      " + info.load_time.ToString() + " ms\n"
        sb = sb + "Memory:         " + info.direct_resources.memory_peak.ToString() + " bytes\n"
        sb = sb + "Imported By:    " + info.importers.keys.ToString() + "\n\n"
        sb = sb + "  [ ] Back          B\n"
    else:
        sb = sb + "SELECTED: (none)\n\n"
    
    sb = sb + "  [ ] Overview          O\n"
    sb = sb + "  [ ] Resource view     R\n"
    sb = sb + "  [ ] Timeline          T\n"
    sb = sb + "  [ ] Errors            E\n"
    sb = sb + "  [ ] Back              B\n"
    sb = sb + "  [ ] Quit              Q\n"
    return sb

# Render resource dashboard
proc dashboard_render_resources(ctx: sandbox.InterpreterContext, state: DashboardState): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "SAGE SANDBOX - RESOURCE VIEW\n"
    sb = sb + "================================\n\n"
    sb = sb + "Program: " + ctx.sandbox_context.program_path + "\n\n"
    sb = sb + "Runtime: " + ctx.sandbox_context.resource_tracker.execution_time.ToString() + " ms\n"
    sb = sb + "Peak Memory: " + ctx.sandbox_context.resource_tracker.program_peak_memory.ToString() + " bytes\n\n"
    sb = sb + "Allocations: " + resource_tracker.allocations.ToString() + "\n"
    sb = sb + "Objects:     " + resource_tracker.objects.ToString() + "\n\n"
    sb = sb + "Module Resources:\n"
    for (name, info) in ctx.sandbox_context.module_registry:
        sb = sb + "  " + name + ": " + info.direct_resources.memory_peak.ToString() + " bytes direct, "
        sb = sb + info.inclusive_resources.memory_peak.ToString() + " bytes inclusive\n"
    sb = sb + "\n"
    sb = sb + "  [ ] Overview          O\n"
    sb = sb + "  [ ] Module view       M\n"
    sb = sb + "  [ ] Timeline          T\n"
    sb = sb + "  [ ] Errors            E\n"
    sb = sb + "  [ ] Back              B\n"
    sb = sb + "  [ ] Quit              Q\n"
    return sb

# Render timeline dashboard
proc dashboard_render_timeline(ctx: sandbox.InterpreterContext, state: DashboardState): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "SAGE SANDBOX - TIMELINE\n"
    sb = sb + "================================\n\n"
    sb = sb + "Program: " + ctx.sandbox_context.program_path + "\n\n"
    sb = sb + "Timeline of events:\n"
    // Would show chronological timeline of module loads, events, etc.
    sb = sb + "  0 ms      program start\n"
    sb = sb + "  2 ms      crypto import\n"
    sb = sb + "  5 ms      hash import\n"
    sb = sb + "  8 ms      crypto complete\n\n"
    sb = sb + "  [ ] Overview          O\n"
    sb = sb + "  [ ] Module view       M\n"
    sb = sb + "  [ ] Resource view     R\n"
    sb = sb + "  [ ] Errors            E\n"
    sb = sb + "  [ ] Back              B\n"
    sb = sb + "  [ ] Quit              Q\n"
    return sb

# Render errors dashboard
proc dashboard_render_errors(ctx: sandbox.InterpreterContext, state: DashboardState): String =
    if ctx.sandbox_context == none:
        return "Sandbox not enabled"
    
    let sb = ""
    sb = sb + "SAGE SANDBOX - ERRORS\n"
    sb = sb + "================================\n\n"
    sb = sb + "Program: " + ctx.sandbox_context.program_path + "\n\n"
    sb = sb + "No errors recorded.\n\n"
    // Would show any errors that occurred
    sb = sb + "\n"
    sb = sb + "  [ ] Overview          O\n"
    sb = sb + "  [ ] Module view       M\n"
    sb = sb + "  [ ] Resource view     R\n"
    sb = sb + "  [ ] Timeline          T\n"
    sb = sb + "  [ ] Back              B\n"
    sb = sb + "  [ ] Quit              Q\n"
    return sb

# Handle dashboard navigation
proc dashboard_handle_navigation(key: String, ctx: sandbox.InterpreterContext, state: DashboardState): DashboardState =
    match key:
        "M": return dashboard_state_default() with mode = DASHBOARD_MODE_MODULES
        "R": return dashboard_state_default() with mode = DASHBOARD_MODE_RESOURCES
        "T": return dashboard_state_default() with mode = DASHBOARD_MODE_TIMELINE
        "E": return dashboard_state_default() with mode = DASHBOARD_MODE_ERRORS
        "O": return dashboard_state_default() with mode = DASHBOARD_MODE_OVERVIEW
        "B": return dashboard_state_default()  // Back
        "H": return dashboard_state_default() with show_help = not state.show_help
        "Q": return dashboard_state_default() with show_help = false  // Quit
        _: return state

# ============================================================================
# Dashboard Initialization
# ============================================================================

# Initialize dashboard with given mode
proc dashboard_init(mode: Int): DashboardState =
    dashboard_state_default() with mode = mode

# Run dashboard loop (pseudo-code - would be integrated with CLI)
# This would be called from the main CLI after program execution
proc dashboard_run(ctx: sandbox.InterpreterContext): None =
    let state = dashboard_init(DASHBOARD_MODE_OVERVIEW)
    
    // Main loop would handle keyboard input
    // For now, just render the initial overview
    print dashboard_render_main(ctx, state)

# ============================================================================
# CLI Integration (from sandbox.md sections 21-23)
# ============================================================================

# Dashboard TUI controls (from section 44):
# ↑ ↓: Navigate
# Enter: Expand module
# M: Module view
# R: Resource view
# T: Timeline
# E: Errors
# Q: Quit dashboard
# F: Filter modules
# /: Search

# Example dashboard modes from section 26:
#
# OVERVIEW:
# ──────────────────────────────────────────────────────────
# │ SAGE SANDBOX                             RUNNING          │
# ├──────────────────────────────────────────────────────────┤
# │ Program       app.sage                                    │
# │ Runtime       42.8 ms                                     │
# │ Memory        1.2 MB / Peak 1.8 MB                        │
# │ Modules       12                                           │
# │ Events        248                                          │
# ├──────────────────────────────────────────────────────────┤
# │ SELECTED: crypto                                          │
# │                                                          │
# │ Load Time:      4.8 ms                                    │
# │ Execution:      12.4 ms                                   │
# │ Memory:         128 KB                                    │
# │ Imported By:    main                                      │
# └──────────────────────────────────────────────────────────┤
# │ SELECTED: crypto                                          │
# │                                                          │
# │ Load Time:      4.8 ms                                    │
# │ Execution:      12.4 ms                                   │
# │ Memory:         128 KB                                    │
# │ Imported By:    main                                      │
# └──────────────────────────────────────────────────────────┤
#
# MODULE TREE:
# ──────────────────────────────────────────────────────────
# main
# │
# ├── ▼ crypto
# │   ├── ▼ hash
# │   │    ├── Dependencies: 2
# │   │    └── Dependencies: random
# │   │
# │   └── ▼ network
# │        ├── ▼ socket
# │        │    ├── Dependencies: 3
# │        │    └── Dependencies: protocol
# │        │
# │        └── ▼ protocol
# │
# └── ▼ ui
#
# Each node should display optional metrics:
# crypto
# ├── Load: 4.8 ms
# ├── Memory: 128 KB
# └── Dependencies: 2