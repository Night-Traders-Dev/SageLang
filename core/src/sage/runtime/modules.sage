# ============================================================================
# Runtime Modules - Module system
# ============================================================================
# Module state belongs to InterpreterContext
# Track: module ID, canonical path, source identity, dependencies,
# cache entry, capability requirements
# Normalize module references before caching
# ============================================================================

# Module ID structure
class ModuleId {
    let canonical_path: String    // Normalized path
    let hash: Int                 // Hash for fast comparison
}

# Module state in InterpreterContext
class ModuleState {
    let module_cache: Dict<ModuleId, Module>
    let module_paths: List<String>      // Search paths
    let loading_stack: List<ModuleId>   // Currently loading modules (for cycle detection)
    let capability_checks: Bool         // Whether to enforce capability checks
}

# Get or create module state
proc get_module_state(ctx: InterpreterContext): ModuleState =
    if ctx.module_state == None:
        ctx.module_state = ModuleState(
            module_cache: {} as Dict<ModuleId, Module>,
            module_paths: [".", "lib", "core/src/sage", "core/lib", 
                          "/usr/local/share/sage/lib", "/usr/local/share/sage/src/sage"],
            loading_stack: [],
            capability_checks: true
        )
    return ctx.module_state

# Resolve a module name to a canonical path
proc resolve_module(ctx: InterpreterContext, name: String): String =
    let state = get_module_state(ctx)
    let paths = state.module_paths
    let i = 0
    while i < len(paths):
        let candidate = paths[i] + "/" + name
        if file_exists(candidate + ".sage"):
            return candidate + ".sage"
        if file_exists(candidate):
            return candidate
        i = i + 1
    raise NameError("Module '" + name + "' not found in search paths")

# Normalize module reference (from pipeline.md line 746)
proc normalize_module_ref(path: String): String =
    // Resolve relative paths, remove .sage extension, etc.
    // This ensures consistent caching
    let abs = realpath(path)
    return abs

# Load a module
proc load_module(ctx: InterpreterContext, name: String): Module =
    let state = get_module_state(ctx)
    let canonical = normalize_module_ref(resolve_module(ctx, name))
    let module_id = ModuleId(canonical_path: canonical, hash: canonical.hash())
    
    // Check cache
    if dict_has(state.module_cache, module_id):
        let cached = state.module_cache[module_id]
        cached.cache_entry.load_count = cached.cache_entry.load_count + 1
        return cached
    
    // Check for circular dependency
    if module_id in state.loading_stack:
        raise RuntimeError("Circular module dependency: " + canonical)
    
    // Add to loading stack
    state.loading_stack = state.loading_stack.push(module_id)
    
    // Load the module
    let source = file_read(canonical)
    let ast = parse_source(source, canonical)
    let ir = compile_to_ir(ast, ctx)
    
    // Create module
    let module = Module(
        module_id: module_id,
        canonical_path: canonical,
        source_identity: source,
        dependencies: [],
        cache_entry: ModuleCacheEntry(
            ast: ast,
            ir: ir,
            bytecode: compile_to_bytecode(ir),
            compiled: true,
            load_count: 1,
            last_loaded: now()
        ),
        capability_reqs: extract_capabilities(ast)
    )
    
    // Verify capabilities (pipeline.md line 765-771)
    if state.capability_checks:
        verify_capabilities(module.capability_reqs, ctx)
    
    // Cache and return
    state.module_cache[module_id] = module
    state.loading_stack = state.loading_stack.pop()
    
    return module

# Verify capability requirements
proc verify_capabilities(reqs: List<Capability>, ctx: InterpreterContext): Unit =
    let caps = ctx.host_capabilities
    for req in reqs:
        if not capability_check(caps, req):
            raise CapabilityError("Module requires capability: " + req.name)

# Extract capabilities from AST
proc extract_capabilities(ast: AST_InModule): List<Capability> =
    // Analyze AST for imports, FFI calls, filesystem access, etc.
    // Return list of required capabilities
    return []

# Module unloading (for development/testing)
proc unload_module(ctx: InterpreterContext, name: String): Bool =
    let state = get_module_state(ctx)
    let canonical = normalize_module_ref(resolve_module(ctx, name))
    let module_id = ModuleId(canonical_path: canonical, hash: canonical.hash())
    if dict_has(state.module_cache, module_id):
        state.module_cache.remove(module_id)
        return true
    return false
