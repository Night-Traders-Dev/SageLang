gc_disable()
# Foreign function interface helpers and C interop utilities
# Wraps FFI primitives with higher-level patterns

# ============================================================================
# Library loading
# ============================================================================

proc load_library(path):
    let lib = {}
    lib["path"] = path
    lib["handle"] = nil
    lib["symbols"] = {}
    lib["loaded"] = false
    # Actual loading would use ffi_open
    try:
        lib["handle"] = ffi_open(path)
        lib["loaded"] = true
    catch e:
        lib["error"] = e
    return lib

proc close_library(lib):
    if lib["loaded"] and lib["handle"] != nil:
        ffi_close(lib["handle"])
        lib["loaded"] = false

# ============================================================================
# Function binding
# ============================================================================

# Bind a C function by name
proc bind(lib, func_name, return_type, param_types):
    let binding = {}
    binding["library"] = lib
    binding["name"] = func_name
    binding["return_type"] = return_type
    binding["param_types"] = param_types
    binding["sym"] = nil
    if lib["loaded"]:
        try:
            binding["sym"] = ffi_sym(lib["handle"], func_name)
        catch e:
            binding["error"] = e
    lib["symbols"][func_name] = binding
    return binding

# Call a bound function
proc call(binding, args):
    if binding["sym"] == nil:
        raise "Symbol not loaded: " + binding["name"]
    return ffi_call(binding["sym"], args)

# ============================================================================
# Type conversion helpers
# ============================================================================

# C type size constants
let SIZEOF_CHAR = 1
let SIZEOF_SHORT = 2
let SIZEOF_INT = 4
let SIZEOF_LONG = 8
let SIZEOF_FLOAT = 4
let SIZEOF_DOUBLE = 8
let SIZEOF_POINTER = 8

# C type names
let TYPE_VOID = "void"
let TYPE_INT = "int"
let TYPE_LONG = "long"
let TYPE_FLOAT = "float"
let TYPE_DOUBLE = "double"
let TYPE_STRING = "string"
let TYPE_POINTER = "pointer"

# Pack an integer into bytes (little-endian)
proc pack_i32(value):
    let bytes = []
    push(bytes, value & 255)
    push(bytes, (value >> 8) & 255)
    push(bytes, (value >> 16) & 255)
    push(bytes, (value >> 24) & 255)
    return bytes

# Unpack bytes to integer (little-endian)
proc unpack_i32(bytes, offset):
    return bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216

proc pack_i64(value):
    let bytes = pack_i32(value & 4294967295)
    let hi = pack_i32((value >> 32) & 4294967295)
    for i in range(4):
        push(bytes, hi[i])
    return bytes

proc unpack_i64(bytes, offset):
    let lo = unpack_i32(bytes, offset)
    let hi = unpack_i32(bytes, offset + 4)
    return lo + hi * 4294967296

# ============================================================================
# Struct helpers (wraps struct_def/struct_new/struct_get/struct_set)
# ============================================================================

proc define_struct(name, fields):
    let s = {}
    s["name"] = name
    s["fields"] = fields
    s["field_names"] = []
    s["field_types"] = []
    for i in range(len(fields)):
        push(s["field_names"], fields[i][0])
        push(s["field_types"], fields[i][1])
    return s

proc struct_size(struct_def):
    let total = 0
    let types = struct_def["field_types"]
    for i in range(len(types)):
        let t = types[i]
        if t == "byte":
            total = total + 1
        if t == "short":
            total = total + 2
        if t == "int":
            total = total + 4
        if t == "long":
            total = total + 8
        if t == "float":
            total = total + 4
        if t == "double":
            total = total + 8
    return total

# ============================================================================
# Platform detection
# ============================================================================

proc shared_lib_extension():
    import sys
    let p = sys.platform
    if p == "linux":
        return ".so"
    if p == "darwin":
        return ".dylib"
    if p == "windows":
        return ".dll"
    return ".so"

proc lib_prefix():
    import sys
    let p = sys.platform
    if p == "windows":
        return ""
    return "lib"

# Build a platform-specific library path
proc lib_path(name):
    return lib_prefix() + name + shared_lib_extension()
