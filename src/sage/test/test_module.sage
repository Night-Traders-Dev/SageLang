gc_disable()
# Tests for module.sage (module system)
import io
import module

let passed = 0
let failed = 0

proc assert_eq(a, b, msg):
    if a == b:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ")"

proc assert_true(v, msg):
    if v:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

# ============================================================================
# Module Name Validation
# ============================================================================

assert_eq(module.is_valid_module_name("math"), true, "valid: math")
assert_eq(module.is_valid_module_name("my_module"), true, "valid: my_module")
assert_eq(module.is_valid_module_name("lib.utils"), true, "valid: lib.utils")
assert_eq(module.is_valid_module_name(""), false, "invalid: empty")
assert_eq(module.is_valid_module_name(nil), false, "invalid: nil")
assert_eq(module.is_valid_module_name("../etc/passwd"), false, "invalid: path traversal ..")
assert_eq(module.is_valid_module_name("foo/bar"), false, "invalid: slash")
# Backslash: chr(92)
let bs_name = "foo" + chr(92) + "bar"
assert_eq(module.is_valid_module_name(bs_name), false, "invalid: backslash")

# ============================================================================
# ModuleCache
# ============================================================================

let cache = module.ModuleCache()
assert_eq(len(cache.search_paths), 3, "default search paths count")
assert_eq(cache.search_paths[0], ".", "search path 0 = .")
assert_eq(cache.search_paths[1], "./lib", "search path 1 = ./lib")
assert_eq(cache.search_paths[2], "./modules", "search path 2 = ./modules")

# Find in empty cache
assert_eq(cache.find("nonexistent"), nil, "find empty cache")

# Add a module
let mod1 = module.Module("test_mod", "/tmp/test_mod.sage")
cache.add(mod1)
let found = cache.find("test_mod")
assert_true(found != nil, "find added module")
assert_eq(found.name, "test_mod", "found module name")
assert_eq(found.path, "/tmp/test_mod.sage", "found module path")

# Find still nil for unknown
assert_eq(cache.find("other"), nil, "find unknown after add")

# Add search path
cache.add_search_path("/custom/path")
assert_eq(len(cache.search_paths), 4, "search paths after add")
assert_eq(cache.search_paths[3], "/custom/path", "custom search path")

# ============================================================================
# Module Object
# ============================================================================

let mod2 = module.Module("mymod", "/path/to/mymod.sage")
assert_eq(mod2.name, "mymod", "module name")
assert_eq(mod2.path, "/path/to/mymod.sage", "module path")
assert_eq(mod2.source, nil, "module source initially nil")
assert_eq(mod2.is_loaded, false, "module not loaded initially")
assert_eq(mod2.is_loading, false, "module not loading initially")

# ============================================================================
# Path Resolution
# ============================================================================

# Create test directory and file
let test_dir = "/tmp/sage_test_modules"
io.writefile(test_dir + "/testmod.sage", "let x = 42")

let cache2 = module.ModuleCache()
cache2.add_search_path(test_dir)

let path = module.resolve_module_path(cache2, "testmod")
assert_true(path != nil, "resolve existing module")
assert_true(contains(path, "testmod.sage"), "resolved path contains filename")

# Nonexistent module
let path2 = module.resolve_module_path(cache2, "nonexistent_xyz")
assert_eq(path2, nil, "resolve nonexistent = nil")

# Invalid module name
let path3 = module.resolve_module_path(cache2, "../etc/passwd")
assert_eq(path3, nil, "resolve invalid name = nil")

# ============================================================================
# load_module
# ============================================================================

let cache3 = module.ModuleCache()
cache3.add_search_path(test_dir)

let loaded = module.load_module(cache3, "testmod")
assert_true(loaded != nil, "load_module found")
assert_eq(loaded.name, "testmod", "loaded module name")
assert_eq(loaded.is_loaded, false, "loaded not yet executed")

# Load again returns cached
let loaded2 = module.load_module(cache3, "testmod")
assert_eq(loaded2.name, "testmod", "cached module returned")

# Load nonexistent
let loaded3 = module.load_module(cache3, "no_such_module_xyz")
assert_eq(loaded3, nil, "load nonexistent = nil")

# ============================================================================
# register_native_module
# ============================================================================

module.init_module_system()
let exports = {}
exports["pi"] = 3.14
exports["e"] = 2.71
module.register_native_module("test_math", exports)

let native_cache = module.get_cache()
let native_mod = native_cache.find("test_math")
assert_true(native_mod != nil, "registered native module found")
assert_eq(native_mod.is_loaded, true, "native module is loaded")
assert_eq(native_mod.exports["pi"], 3.14, "native module export pi")
assert_eq(native_mod.exports["e"], 2.71, "native module export e")

# ============================================================================
# Circular dependency detection
# ============================================================================

let circ_mod = module.Module("circular", "/tmp/circular.sage")
circ_mod.is_loading = true
let exec_called = false
proc dummy_execute(source, env):
    exec_called = true
    return true
let circ_result = module.execute_module(circ_mod, dummy_execute)
assert_eq(circ_result, false, "circular dependency detected")
assert_eq(exec_called, false, "execute not called for circular")

# ============================================================================
# Module execution
# ============================================================================

let exec_mod = module.Module("exec_test", "/tmp/sage_test_modules/testmod.sage")
exec_mod.env = {}
let did_execute = false
proc test_execute(source, env):
    did_execute = true
    return true
let exec_result = module.execute_module(exec_mod, test_execute)
assert_eq(exec_result, true, "execute_module success")
assert_eq(did_execute, true, "execute callback called")
assert_eq(exec_mod.is_loaded, true, "module marked loaded")
assert_eq(exec_mod.is_loading, false, "module not loading after exec")

# Execute again (already loaded)
did_execute = false
let exec_result2 = module.execute_module(exec_mod, test_execute)
assert_eq(exec_result2, true, "execute already loaded")
assert_eq(did_execute, false, "not called again for loaded")

print ""
print "Module tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All module tests passed!"
