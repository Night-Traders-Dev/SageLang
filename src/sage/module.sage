gc_disable()
# SageLang Module System (self-hosted port)
#
# Handles:
# - Module cache (loaded modules indexed by name)
# - Search path resolution (./, ./lib/, ./modules/)
# - File loading and parsing
# - Circular dependency detection
# - Import types: import X, from X import Y, import X as Y
import io

let MAX_SEARCH_PATHS = 16

# ============================================================================
# Module Cache
# ============================================================================

class ModuleCache:
    proc init():
        # modules: dict of name -> Module
        self.modules = {}
        # search_paths: list of directory paths
        self.search_paths = []
        # Add default search paths
        push(self.search_paths, ".")
        push(self.search_paths, "./lib")
        push(self.search_paths, "./modules")

    proc add_search_path(path):
        # MAX_SEARCH_PATHS = 16; hardcoded because class methods can't see module-level lets
        if len(self.search_paths) >= 16:
            print "Error: Maximum search paths exceeded"
            return
        push(self.search_paths, path)

    proc find(name):
        if dict_has(self.modules, name):
            return self.modules[name]
        return nil

    proc add(mod):
        self.modules[mod.name] = mod

class Module:
    proc init(name, path):
        self.name = name
        self.path = path
        self.source = nil
        self.env = nil
        self.is_loaded = false
        self.is_loading = false
        self.exports = {}

# Global module cache
let g_cache = nil

# ============================================================================
# Module Name Validation
# ============================================================================

# Validate module name: only allow alphanumeric, underscore, dot (no path separators)
proc is_valid_module_name(name):
    if name == nil:
        return false
    if len(name) == 0:
        return false
    for i in range(len(name)):
        let c = name[i]
        if c == "/":
            return false
        # Backslash check (chr(92) = backslash)
        if c == chr(92):
            return false
        # Check for ".." sequences
        if c == "." and i + 1 < len(name) and name[i + 1] == ".":
            return false
    return true

# ============================================================================
# Path Resolution
# ============================================================================

# Resolve module path by searching in search paths
proc resolve_module_path(cache, name):
    if not is_valid_module_name(name):
        print "Error: Invalid module name " + chr(39) + name + chr(39) + " (path traversal not allowed)"
        return nil
    for i in range(len(cache.search_paths)):
        let search_dir = cache.search_paths[i]
        # Try .sage extension
        let path = search_dir + "/" + name + ".sage"
        let content = io.readfile(path)
        if content != nil:
            return path
        # Try __init__.sage in a directory
        let init_path = search_dir + "/" + name + "/__init__.sage"
        let init_content = io.readfile(init_path)
        if init_content != nil:
            return init_path
    return nil

# ============================================================================
# Module Loading
# ============================================================================

# Load a module (find or create in cache)
proc load_module(cache, name):
    # Check cache first
    let existing = cache.find(name)
    if existing != nil:
        return existing
    # Resolve path
    let path = resolve_module_path(cache, name)
    if path == nil:
        print "Error: Could not find module " + chr(39) + name + chr(39)
        return nil
    # Create module
    let mod = Module(name, path)
    cache.add(mod)
    return mod

# Execute a module (parse + interpret its source)
# The execute_fn parameter is a callback that takes (source, env) and runs it.
# This avoids circular dependency with interpreter.sage.
proc execute_module(mod, execute_fn):
    if mod.is_loaded:
        return true
    if mod.is_loading:
        print "Error: Circular dependency detected for module " + chr(39) + mod.name + chr(39)
        return false
    mod.is_loading = true
    # Read source if needed
    if mod.source == nil:
        mod.source = io.readfile(mod.path)
    if mod.source == nil:
        mod.is_loading = false
        return false
    # Execute the module source
    let result = execute_fn(mod.source, mod.env)
    mod.is_loading = false
    if result:
        mod.is_loaded = true
    return result

# ============================================================================
# Import Functions
# ============================================================================

# Import entire module: import math
proc import_all(env, module_name, execute_fn):
    if g_cache == nil:
        init_module_system()
    let mod = load_module(g_cache, module_name)
    if mod == nil:
        return false
    if not mod.is_loaded:
        if not execute_module(mod, execute_fn):
            return false
    # Add module to environment
    env[module_name] = mod.exports
    return true

# Import specific items: from math import sin, cos
proc import_from(env, module_name, items, aliases, execute_fn):
    if g_cache == nil:
        init_module_system()
    let mod = load_module(g_cache, module_name)
    if mod == nil:
        return false
    if not mod.is_loaded:
        if not execute_module(mod, execute_fn):
            return false
    for i in range(len(items)):
        let item_name = items[i]
        let bind_name = item_name
        if aliases != nil and i < len(aliases) and aliases[i] != nil:
            bind_name = aliases[i]
        if dict_has(mod.exports, item_name):
            env[bind_name] = mod.exports[item_name]
        else:
            print "Error: Module " + chr(39) + module_name + chr(39) + " has no attribute " + chr(39) + item_name + chr(39)
            return false
    return true

# Import with alias: import math as m
proc import_as(env, module_name, alias, execute_fn):
    if g_cache == nil:
        init_module_system()
    let mod = load_module(g_cache, module_name)
    if mod == nil:
        return false
    if not mod.is_loaded:
        if not execute_module(mod, execute_fn):
            return false
    env[alias] = mod.exports
    return true

# ============================================================================
# Module System Init/Cleanup
# ============================================================================

# Initialize the module system
proc init_module_system():
    if g_cache == nil:
        g_cache = ModuleCache()

# Get the global cache
proc get_cache():
    if g_cache == nil:
        init_module_system()
    return g_cache

# Register a pre-loaded native module (e.g., stdlib modules)
proc register_native_module(name, exports):
    if g_cache == nil:
        init_module_system()
    let mod = Module(name, nil)
    mod.is_loaded = true
    mod.exports = exports
    g_cache.add(mod)
