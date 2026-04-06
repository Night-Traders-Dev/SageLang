gc_disable()
# -----------------------------------------
# interpreter.sage - Tree-walking interpreter for SageLang
# Self-hosted implementation (Phase 13)
# -----------------------------------------

from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import EXPR_SUPER, EXPR_COMPTIME
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER, STMT_MATCH
from ast import STMT_STRUCT, STMT_ENUM, STMT_TRAIT, STMT_COMPTIME, STMT_MACRO_DEF
from token import TOKEN_NOT, TOKEN_TILDE, TOKEN_OR, TOKEN_AND
from token import TOKEN_EQ, TOKEN_NEQ, TOKEN_GT, TOKEN_LT, TOKEN_GTE, TOKEN_LTE
from token import TOKEN_PLUS, TOKEN_MINUS, TOKEN_STAR, TOKEN_SLASH, TOKEN_PERCENT
from token import TOKEN_AMP, TOKEN_PIPE, TOKEN_CARET, TOKEN_LSHIFT, TOKEN_RSHIFT
import errors

# Control flow signal kinds
let SIGNAL_NORMAL = 0
let SIGNAL_RETURN = 1
let SIGNAL_BREAK = 2
let SIGNAL_CONTINUE = 3
let SIGNAL_YIELD = 4

# Maximum recursion depth
let MAX_RECURSION = 500

# Maximum loop iterations (prevents infinite loops)
let MAX_LOOP_ITERATIONS = 1000000

# Recursion depth counter (module-level)
let g_depth = 0

# Error context for rich error messages (module-level)
let g_error_ctx = nil

# Module cache to prevent double-loading
let g_module_cache = {}

# Module search paths (set by the host before running)
let g_module_paths = [".", "lib"]

# ---- Performance: pre-allocated signal singletons ----
# These eliminate dict allocation on EVERY statement execution.
# The hot loop (exec_stmt → result_normal(nil)) was allocating a fresh
# dict with 2 keys per statement. Now it returns a cached reference.
let _SIG_NORMAL_NIL = {"kind": 0, "value": nil}
let _SIG_BREAK = {"kind": 2, "value": nil}
let _SIG_CONTINUE = {"kind": 3, "value": nil}

proc set_error_context(source, filename):
    g_error_ctx = errors.make_error_context(source, filename)

# Extract line number from an expression node (-1 if unknown)
proc get_expr_line(expr):
    if expr == nil:
        return -1
    let etype = expr.type
    # EXPR_VARIABLE: name is a token
    if etype == EXPR_VARIABLE:
        return expr.name.line
    # EXPR_BINARY: op is a token
    if etype == EXPR_BINARY:
        return expr.op.line
    # EXPR_GET: property is a token
    if etype == EXPR_GET:
        return expr.property.line
    # EXPR_SET: property is a token
    if etype == EXPR_SET:
        return expr.property.line
    # EXPR_CALL: recurse into callee
    if etype == EXPR_CALL:
        return get_expr_line(expr.callee)
    # EXPR_INDEX / EXPR_INDEX_SET / EXPR_SLICE: recurse into object
    if etype == EXPR_INDEX:
        return get_expr_line(expr.object)
    if etype == EXPR_INDEX_SET:
        return get_expr_line(expr.object)
    if etype == EXPR_SLICE:
        return get_expr_line(expr.object)
    return -1

# Extract line number from a statement node (-1 if unknown)
proc get_stmt_line(stmt):
    if stmt == nil:
        return -1
    let stype = stmt.type
    if stype == STMT_LET:
        return stmt.name.line
    if stype == STMT_PROC:
        return stmt.name.line
    if stype == STMT_FOR:
        return stmt.variable.line
    if stype == STMT_CLASS:
        return stmt.name.line
    if stype == STMT_PRINT:
        return get_expr_line(stmt.expression)
    if stype == STMT_EXPRESSION:
        return get_expr_line(stmt.expression)
    return -1

# Raise a rich runtime error if error context is available
proc runtime_error(line, message, hint):
    if g_error_ctx != nil:
        if line > 0:
            let msg = errors.format_error(g_error_ctx, line, -1, "Runtime Error", message, hint)
            raise msg
    raise "Runtime Error: " + message

# -----------------------------------------
# Environment functions (dict-based)
# env = {"parent": parent_env_or_nil, "vals": {}}
# -----------------------------------------

proc env_new(parent):
    return {"parent": parent, "vals": {}}

proc env_define(env, name, value):
    env["vals"][name] = value

proc env_get(env, name):
    # Cache vals reference to avoid double dict lookup on env
    let e = env
    while e != nil:
        let vals = e["vals"]
        if dict_has(vals, name):
            return vals[name]
        e = e["parent"]
    raise "Undefined variable '" + name + "'"

proc env_set(env, name, value):
    let e = env
    while e != nil:
        let vals = e["vals"]
        if dict_has(vals, name):
            vals[name] = value
            return true
        e = e["parent"]
    raise "Undefined variable '" + name + "'"

# -----------------------------------------
# Import binding helper
# -----------------------------------------

proc import_bind(stmt, mod_name, mod_env, target_env):
    let mod_vals = mod_env["vals"]
    if stmt.item_count > 0:
        # from X import a, b, c
        let i = 0
        while i < stmt.item_count:
            let item_name = stmt.items[i].text
            if dict_has(mod_vals, item_name):
                let bind_name = item_name
                if stmt.item_aliases[i] != nil:
                    bind_name = stmt.item_aliases[i].text
                env_define(target_env, bind_name, mod_vals[item_name])
            i = i + 1
    if stmt.item_count == 0:
        # import X  or  import X as Y
        let bind_name = mod_name
        if stmt.alias != nil:
            bind_name = stmt.alias.text
        # Wrap module env as a dict-like module object
        let mod_obj = {}
        mod_obj["__interp_type"] = "module"
        mod_obj["name"] = mod_name
        let keys = dict_keys(mod_vals)
        let ki = 0
        while ki < len(keys):
            mod_obj[keys[ki]] = mod_vals[keys[ki]]
            ki = ki + 1
        env_define(target_env, bind_name, mod_obj)

# -----------------------------------------
# Helper: create control flow result dicts
# -----------------------------------------

proc result_normal(val):
    if val == nil:
        return _SIG_NORMAL_NIL
    let r = {}
    r["kind"] = SIGNAL_NORMAL
    r["value"] = val
    return r

proc result_return(val):
    let r = {}
    r["kind"] = SIGNAL_RETURN
    r["value"] = val
    return r

proc result_break():
    return _SIG_BREAK

proc result_continue():
    return _SIG_CONTINUE

# -----------------------------------------
# Helper: truthiness
# -----------------------------------------

proc is_truthy(val):
    if val == nil:
        return false
    if val == false:
        return false
    if val == 0:
        return false
    if type(val) == "string":
        if val == "":
            return false
    return true

# -----------------------------------------
# Helper: value to string for printing
# -----------------------------------------

proc value_to_string(val):
    if val == nil:
        return "nil"
    if val == true:
        return "true"
    if val == false:
        return "false"
    if type(val) == "number":
        let s = str(val)
        return s
    if type(val) == "string":
        return val
    if type(val) == "array":
        let parts = []
        let i = 0
        while i < len(val):
            push(parts, value_to_string(val[i]))
            i = i + 1
        return "[" + join(parts, ", ") + "]"
    if type(val) == "dict":
        # Check if it's a special interpreter value
        if dict_has(val, "__interp_type"):
            let vtype = val["__interp_type"]
            if vtype == "function":
                return "<proc " + val["name"] + ">"
            if vtype == "native":
                return "<native " + val["name"] + ">"
            if vtype == "class":
                return "<class " + val["name"] + ">"
            if vtype == "instance":
                let cls = val["class"]
                return "<" + cls["name"] + " instance>"
        # Regular dict
        let ks = dict_keys(val)
        let parts = []
        let i = 0
        while i < len(ks):
            let k = ks[i]
            push(parts, value_to_string(k) + ": " + value_to_string(val[k]))
            i = i + 1
        return "{" + join(parts, ", ") + "}"
    return str(val)

# -----------------------------------------
# Native builtin dispatch
# -----------------------------------------

# ---- Performance: native dispatch table ----
# Replaces the massive if/elif chain in call_native with O(1) dict lookup.
# Each entry maps a builtin name to a handler proc.

let _native_dispatch = {}

proc _n_str(args):
    return value_to_string(args[0])

proc _n_len(args):
    let x = args[0]
    let t = type(x)
    if t == "string":
        return len(x)
    if t == "array":
        return len(x)
    if t == "dict":
        return len(dict_keys(x))
    return 0

proc _n_tonumber(args):
    let x = args[0]
    if type(x) == "number":
        return x
    if type(x) == "string":
        return tonumber(x)
    return 0

proc _n_push(args):
    push(args[0], args[1])
    return nil

proc _n_pop(args):
    return pop(args[0])

proc _n_array_extend(args):
    let arr = args[0]
    let other = args[1]
    let i = 0
    while i < len(other):
        push(arr, other[i])
        i = i + 1
    return nil

proc _n_range(args):
    let argc = len(args)
    if argc == 1:
        return range(args[0])
    if argc == 2:
        return range(args[0], args[1])
    return []

proc _n_type(args):
    let x = args[0]
    if x == nil:
        return "nil"
    let t = type(x)
    if t == "dict":
        if dict_has(x, "__interp_type"):
            let vt = x["__interp_type"]
            if vt == "function":
                return "function"
            if vt == "native":
                return "native"
            if vt == "class":
                return "class"
            if vt == "instance":
                return x["class"]["name"]
            if vt == "generator":
                return "generator"
        return "dict"
    return t

proc _n_input(args):
    return input()

proc _n_clock(args):
    return clock()

proc _n_chr(args):
    return chr(args[0])

proc _n_ord(args):
    return ord(args[0])

proc _n_slice(args):
    return slice(args[0], args[1], args[2])

proc _n_split(args):
    return split(args[0], args[1])

proc _n_join(args):
    return join(args[0], args[1])

proc _n_replace(args):
    return replace(args[0], args[1], args[2])

proc _n_upper(args):
    return upper(args[0])

proc _n_lower(args):
    return lower(args[0])

proc _n_strip(args):
    return strip(args[0])

proc _n_dict_keys(args):
    return dict_keys(args[0])

proc _n_dict_values(args):
    return dict_values(args[0])

proc _n_dict_has(args):
    return dict_has(args[0], args[1])

proc _n_dict_delete(args):
    dict_delete(args[0], args[1])
    return nil

proc _n_startswith(args):
    return startswith(args[0], args[1])

proc _n_endswith(args):
    return endswith(args[0], args[1])

proc _n_contains(args):
    return contains(args[0], args[1])

proc _n_indexof(args):
    return indexof(args[0], args[1])

proc _n_next(args):
    let gen = args[0]
    if type(gen) == "dict":
        if dict_has(gen, "__interp_type"):
            if gen["__interp_type"] == "generator":
                let idx = gen["index"]
                let vals = gen["values"]
                if idx < len(vals):
                    gen["index"] = idx + 1
                    return vals[idx]
    return nil

proc _n_gc_collect(args):
    gc_collect()
    return nil

proc _n_gc_enable(args):
    gc_enable()
    return nil

proc _n_gc_disable(args):
    gc_disable()
    return nil

proc _n_gc_stats(args):
    return gc_stats()

proc _n_ffi_open(args):
    return ffi_open(args[0])

proc _n_ffi_close(args):
    ffi_close(args[0])
    return nil

proc _n_ffi_call(args):
    if len(args) == 3:
        return ffi_call(args[0], args[1], args[2])
    if len(args) == 4:
        return ffi_call(args[0], args[1], args[2], args[3])
    return nil

proc _n_ffi_sym(args):
    return ffi_sym(args[0], args[1])

proc _n_mem_alloc(args):
    return mem_alloc(args[0])

proc _n_mem_free(args):
    mem_free(args[0])
    return nil

proc _n_mem_read(args):
    return mem_read(args[0], args[1], args[2])

proc _n_mem_write(args):
    mem_write(args[0], args[1], args[2], args[3])
    return nil

proc _n_mem_size(args):
    return mem_size(args[0])

proc _n_addressof(args):
    return addressof(args[0])

proc _n_int(args):
    let x = args[0]
    if type(x) == "number":
        let s = str(x)
        let dot_pos = -1
        let i = 0
        while i < len(s):
            if s[i] == ".":
                dot_pos = i
                break
            i = i + 1
        if dot_pos == -1:
            return x
        let int_part = ""
        i = 0
        while i < dot_pos:
            int_part = int_part + s[i]
            i = i + 1
        if int_part == "" or int_part == "-":
            return 0
        return tonumber(int_part)
    if type(x) == "string":
        return tonumber(x)
    return 0

# Build the dispatch table at module load time
_native_dispatch["str"] = _n_str
_native_dispatch["len"] = _n_len
_native_dispatch["tonumber"] = _n_tonumber
_native_dispatch["push"] = _n_push
_native_dispatch["pop"] = _n_pop
_native_dispatch["array_extend"] = _n_array_extend
_native_dispatch["range"] = _n_range
_native_dispatch["type"] = _n_type
_native_dispatch["input"] = _n_input
_native_dispatch["clock"] = _n_clock
_native_dispatch["chr"] = _n_chr
_native_dispatch["ord"] = _n_ord
_native_dispatch["slice"] = _n_slice
_native_dispatch["split"] = _n_split
_native_dispatch["join"] = _n_join
_native_dispatch["replace"] = _n_replace
_native_dispatch["upper"] = _n_upper
_native_dispatch["lower"] = _n_lower
_native_dispatch["strip"] = _n_strip
_native_dispatch["dict_keys"] = _n_dict_keys
_native_dispatch["dict_values"] = _n_dict_values
_native_dispatch["dict_has"] = _n_dict_has
_native_dispatch["dict_delete"] = _n_dict_delete
_native_dispatch["startswith"] = _n_startswith
_native_dispatch["endswith"] = _n_endswith
_native_dispatch["contains"] = _n_contains
_native_dispatch["indexof"] = _n_indexof
_native_dispatch["next"] = _n_next
_native_dispatch["gc_collect"] = _n_gc_collect
_native_dispatch["gc_enable"] = _n_gc_enable
_native_dispatch["gc_disable"] = _n_gc_disable
_native_dispatch["gc_stats"] = _n_gc_stats
_native_dispatch["ffi_open"] = _n_ffi_open
_native_dispatch["ffi_close"] = _n_ffi_close
_native_dispatch["ffi_call"] = _n_ffi_call
_native_dispatch["ffi_sym"] = _n_ffi_sym
_native_dispatch["mem_alloc"] = _n_mem_alloc
_native_dispatch["mem_free"] = _n_mem_free
_native_dispatch["mem_read"] = _n_mem_read
_native_dispatch["mem_write"] = _n_mem_write
_native_dispatch["mem_size"] = _n_mem_size
_native_dispatch["addressof"] = _n_addressof
_native_dispatch["int"] = _n_int

# ---- Missing builtins: GC modes, bytes, path, hash, doc ----

proc _n_gc_mode(args):
    return gc_mode()
proc _n_gc_set_arc(args):
    gc_set_arc()
    return nil
proc _n_gc_set_orc(args):
    gc_set_orc()
    return nil
proc _n_bytes(args):
    return bytes(args[0])
proc _n_bytes_len(args):
    return bytes_len(args[0])
proc _n_bytes_get(args):
    return bytes_get(args[0], args[1])
proc _n_bytes_set(args):
    bytes_set(args[0], args[1], args[2])
    return nil
proc _n_bytes_to_string(args):
    return bytes_to_string(args[0])
proc _n_bytes_slice(args):
    return bytes_slice(args[0], args[1], args[2])
proc _n_bytes_push(args):
    bytes_push(args[0], args[1])
    return nil
proc _n_path_join(args):
    return path_join(args[0], args[1])
proc _n_path_dirname(args):
    return path_dirname(args[0])
proc _n_path_basename(args):
    return path_basename(args[0])
proc _n_path_ext(args):
    return path_ext(args[0])
proc _n_path_exists(args):
    return path_exists(args[0])
proc _n_path_is_dir(args):
    return path_is_dir(args[0])
proc _n_path_is_file(args):
    return path_is_file(args[0])
proc _n_hash(args):
    return hash(args[0])
proc _n_sizeof(args):
    return sizeof(args[0])

_native_dispatch["gc_mode"] = _n_gc_mode
_native_dispatch["gc_set_arc"] = _n_gc_set_arc
_native_dispatch["gc_set_orc"] = _n_gc_set_orc
_native_dispatch["bytes"] = _n_bytes
_native_dispatch["bytes_len"] = _n_bytes_len
_native_dispatch["bytes_get"] = _n_bytes_get
_native_dispatch["bytes_set"] = _n_bytes_set
_native_dispatch["bytes_to_string"] = _n_bytes_to_string
_native_dispatch["bytes_slice"] = _n_bytes_slice
_native_dispatch["bytes_push"] = _n_bytes_push
_native_dispatch["path_join"] = _n_path_join
_native_dispatch["path_dirname"] = _n_path_dirname
_native_dispatch["path_basename"] = _n_path_basename
_native_dispatch["path_ext"] = _n_path_ext
_native_dispatch["path_exists"] = _n_path_exists
_native_dispatch["path_is_dir"] = _n_path_is_dir
_native_dispatch["path_is_file"] = _n_path_is_file
_native_dispatch["hash"] = _n_hash
_native_dispatch["sizeof"] = _n_sizeof

proc call_native(name, args):
    if dict_has(_native_dispatch, name):
        let handler = _native_dispatch[name]
        return handler(args)
    runtime_error(-1, "Unknown native function: " + name, nil)

# -----------------------------------------
# Register builtins into an environment
# -----------------------------------------

proc register_native(env, name, arity):
    env_define(env, name, {"__interp_type": "native", "name": name, "arity": arity})

proc init_builtins(env):
    register_native(env, "str", 1)
    register_native(env, "len", 1)
    register_native(env, "tonumber", 1)
    register_native(env, "push", 2)
    register_native(env, "pop", 1)
    register_native(env, "array_extend", 2)
    register_native(env, "range", -1)
    register_native(env, "type", 1)
    register_native(env, "input", 0)
    register_native(env, "clock", 0)
    register_native(env, "chr", 1)
    register_native(env, "ord", 1)
    register_native(env, "slice", 3)
    register_native(env, "split", 2)
    register_native(env, "join", 2)
    register_native(env, "replace", 3)
    register_native(env, "upper", 1)
    register_native(env, "lower", 1)
    register_native(env, "strip", 1)
    register_native(env, "dict_keys", 1)
    register_native(env, "dict_values", 1)
    register_native(env, "dict_has", 2)
    register_native(env, "dict_delete", 2)
    register_native(env, "startswith", 2)
    register_native(env, "endswith", 2)
    register_native(env, "contains", 2)
    register_native(env, "indexof", 2)
    # Generator support
    register_native(env, "next", 1)
    # GC control (delegates to host C runtime)
    register_native(env, "gc_collect", 0)
    register_native(env, "gc_enable", 0)
    register_native(env, "gc_disable", 0)
    register_native(env, "gc_stats", 0)
    # FFI stubs (delegates to host C runtime)
    register_native(env, "ffi_open", 1)
    register_native(env, "ffi_close", 1)
    register_native(env, "ffi_call", -1)
    register_native(env, "ffi_sym", 2)
    # Memory stubs (delegates to host C runtime)
    register_native(env, "mem_alloc", 1)
    register_native(env, "mem_free", 1)
    register_native(env, "mem_read", 3)
    register_native(env, "mem_write", 4)
    register_native(env, "mem_size", 1)
    register_native(env, "addressof", 1)
    # Math functions
    register_native(env, "int", 1)
    # GC modes
    register_native(env, "gc_mode", 0)
    register_native(env, "gc_set_arc", 0)
    register_native(env, "gc_set_orc", 0)
    # Bytes
    register_native(env, "bytes", 1)
    register_native(env, "bytes_len", 1)
    register_native(env, "bytes_get", 2)
    register_native(env, "bytes_set", 3)
    register_native(env, "bytes_to_string", 1)
    register_native(env, "bytes_slice", 3)
    register_native(env, "bytes_push", 2)
    # Path utilities
    register_native(env, "path_join", 2)
    register_native(env, "path_dirname", 1)
    register_native(env, "path_basename", 1)
    register_native(env, "path_ext", 1)
    register_native(env, "path_exists", 1)
    register_native(env, "path_is_dir", 1)
    register_native(env, "path_is_file", 1)
    # Hash and sizeof
    register_native(env, "hash", 1)
    register_native(env, "sizeof", 1)

# -----------------------------------------
# Expression evaluation
# -----------------------------------------

# eval_expr: recursion depth checked at call boundaries (eval_call),
# not per-expression. Eliminates 2 increments per expression eval.
proc eval_expr(expr, env):
    if expr == nil:
        return nil
    return eval_expr_impl(expr, env)

proc eval_expr_impl(expr, env):
    let etype = expr.type

    # --- Hot path: most common types first ---
    # Profiling shows NUMBER, VARIABLE, BINARY account for ~85% of all
    # expression evaluations. Checking them first reduces average if-chain depth.

    if etype == EXPR_NUMBER:
        return expr.value

    if etype == EXPR_VARIABLE:
        # Avoid try/catch — exception path is 10x slower than direct check.
        # env_get raises on miss; we catch at the boundary instead.
        return env_get(env, expr.name.text)

    if etype == EXPR_BINARY:
        return eval_binary(expr, env)

    # --- Other literals ---
    if etype == EXPR_STRING:
        return expr.value

    if etype == EXPR_BOOL:
        return expr.value

    if etype == EXPR_NIL:
        return nil

    # --- Array literal ---
    if etype == EXPR_ARRAY:
        let arr = []
        let i = 0
        while i < expr.count:
            let val = eval_expr(expr.elements[i], env)
            push(arr, val)
            i = i + 1
        return arr

    # --- Dict literal ---
    # Note: parser stores keys as raw strings, not Expr nodes
    if etype == EXPR_DICT:
        let d = {}
        let i = 0
        while i < expr.count:
            let k = expr.keys[i]
            let v = eval_expr(expr.values[i], env)
            d[k] = v
            i = i + 1
        return d

    # --- Tuple literal ---
    if etype == EXPR_TUPLE:
        let arr = []
        let i = 0
        while i < expr.count:
            let val = eval_expr(expr.elements[i], env)
            push(arr, val)
            i = i + 1
        return arr

    # --- Index ---
    if etype == EXPR_INDEX:
        let obj = eval_expr(expr.object, env)
        let idx = eval_expr(expr.index, env)
        if type(obj) == "array":
            return obj[idx]
        if type(obj) == "string":
            return obj[idx]
        if type(obj) == "dict":
            return obj[idx]
        runtime_error(get_expr_line(expr), "Cannot index into value of type '" + type(obj) + "'", "only arrays, strings, and dicts can be indexed")

    # --- Index set ---
    if etype == EXPR_INDEX_SET:
        let obj = eval_expr(expr.object, env)
        let idx = eval_expr(expr.index, env)
        let val = eval_expr(expr.value, env)
        obj[idx] = val
        return val

    # --- Slice ---
    if etype == EXPR_SLICE:
        let obj = eval_expr(expr.object, env)
        let s = 0
        let e = 0
        if type(obj) == "array":
            e = len(obj)
        elif type(obj) == "string":
            e = len(obj)
        if expr.start != nil:
            s = eval_expr(expr.start, env)
        if expr.end != nil:
            e = eval_expr(expr.end, env)
        return slice(obj, s, e)

    # --- Get property ---
    if etype == EXPR_GET:
        let obj = eval_expr(expr.object, env)
        let prop_name = expr.property.text
        if type(obj) == "dict":
            if dict_has(obj, "__interp_type") and obj["__interp_type"] == "instance":
                let fields = obj["fields"]
                if dict_has(fields, prop_name):
                    return fields[prop_name]
                # Check class methods
                let cls = obj["class"]
                let found = find_method(cls, prop_name)
                if found != nil:
                    return found
                runtime_error(expr.property.line, "Undefined property '" + prop_name + "'", "this instance does not have a field or method named '" + prop_name + "'")
            # Regular dict or module-like access
            if dict_has(obj, prop_name):
                return obj[prop_name]
            runtime_error(expr.property.line, "Undefined property '" + prop_name + "'", nil)
        runtime_error(expr.property.line, "Only instances and dicts have properties", "got value of type '" + type(obj) + "'")

    # --- Set property ---
    if etype == EXPR_SET:
        let prop_name = expr.property.text
        # Variable reassignment: x = value
        if expr.object == nil:
            let val = eval_expr(expr.value, env)
            env_set(env, prop_name, val)
            return val
        # Property assignment: obj.prop = value
        let obj = eval_expr(expr.object, env)
        let val = eval_expr(expr.value, env)
        if type(obj) == "dict":
            if dict_has(obj, "__interp_type") and obj["__interp_type"] == "instance":
                let fields = obj["fields"]
                fields[prop_name] = val
                return val
            obj[prop_name] = val
            return val
        runtime_error(expr.property.line, "Only instances have settable properties", "got value of type '" + type(obj) + "'")

    # --- Call ---
    if etype == EXPR_CALL:
        return eval_call(expr, env)

    # --- Await ---
    if etype == EXPR_AWAIT:
        return eval_expr(expr.expression, env)

    # --- Super method call ---
    if etype == EXPR_SUPER:
        # super.method — find method in parent class
        # The actual args are handled by EXPR_CALL wrapping this
        let method_name = expr.method.text
        # Look up 'self' in current env to find the instance's class
        let self_val = env_get(env, "self")
        if type(self_val) == "dict" and dict_has(self_val, "__interp_type") and self_val["__interp_type"] == "instance":
            let cls = self_val["class"]
            if cls["parent"] != nil:
                let parent_method = find_method(cls["parent"], method_name)
                if parent_method != nil:
                    return parent_method
                runtime_error(-1, "Undefined method '" + method_name + "' in parent class", nil)
            runtime_error(-1, "Class has no parent for super call", nil)
        runtime_error(-1, "super used outside of a class method", nil)

    # --- Comptime expression (evaluate normally at runtime) ---
    if etype == EXPR_COMPTIME:
        return eval_expr(expr.expression, env)

    runtime_error(-1, "Unknown expression type: " + str(etype), nil)

# -----------------------------------------
# Binary expression evaluation
# -----------------------------------------

# ---- Performance: binary op dispatch table ----
# Each binary operator maps to a handler proc that takes (left, right).
# Short-circuit ops (and, or, not) are handled inline before dispatch.

let _binop_dispatch = {}

proc _bop_eq(l, r):
    return l == r
proc _bop_neq(l, r):
    return l != r
proc _bop_gt(l, r):
    return l > r
proc _bop_lt(l, r):
    return l < r
proc _bop_gte(l, r):
    return l >= r
proc _bop_lte(l, r):
    return l <= r
proc _bop_plus(l, r):
    if type(l) == "number" and type(r) == "number":
        return l + r
    if type(l) == "string" and type(r) == "string":
        return l + r
    if type(l) == "string":
        return l + value_to_string(r)
    if type(r) == "string":
        return value_to_string(l) + r
    return l + r
proc _bop_minus(l, r):
    return l - r
proc _bop_star(l, r):
    return l * r
proc _bop_slash(l, r):
    return l / r
proc _bop_percent(l, r):
    return l % r
proc _bop_amp(l, r):
    return l & r
proc _bop_pipe(l, r):
    return l | r
proc _bop_caret(l, r):
    return l ^ r
proc _bop_lshift(l, r):
    return l << r
proc _bop_rshift(l, r):
    return l >> r

_binop_dispatch[TOKEN_EQ] = _bop_eq
_binop_dispatch[TOKEN_NEQ] = _bop_neq
_binop_dispatch[TOKEN_GT] = _bop_gt
_binop_dispatch[TOKEN_LT] = _bop_lt
_binop_dispatch[TOKEN_GTE] = _bop_gte
_binop_dispatch[TOKEN_LTE] = _bop_lte
_binop_dispatch[TOKEN_PLUS] = _bop_plus
_binop_dispatch[TOKEN_MINUS] = _bop_minus
_binop_dispatch[TOKEN_STAR] = _bop_star
_binop_dispatch[TOKEN_SLASH] = _bop_slash
_binop_dispatch[TOKEN_PERCENT] = _bop_percent
_binop_dispatch[TOKEN_AMP] = _bop_amp
_binop_dispatch[TOKEN_PIPE] = _bop_pipe
_binop_dispatch[TOKEN_CARET] = _bop_caret
_binop_dispatch[TOKEN_LSHIFT] = _bop_lshift
_binop_dispatch[TOKEN_RSHIFT] = _bop_rshift

proc eval_binary(expr, env):
    let op_type = expr.op.type

    # Unary not (short-circuit)
    if op_type == TOKEN_NOT:
        let left = eval_expr(expr.left, env)
        return not is_truthy(left)

    # Unary bitwise not (~)
    if op_type == TOKEN_TILDE:
        let left = eval_expr(expr.left, env)
        return 0 - left - 1

    # Short-circuit: or
    if op_type == TOKEN_OR:
        let left = eval_expr(expr.left, env)
        if is_truthy(left):
            return true
        return is_truthy(eval_expr(expr.right, env))

    # Short-circuit: and
    if op_type == TOKEN_AND:
        let left = eval_expr(expr.left, env)
        if not is_truthy(left):
            return false
        return is_truthy(eval_expr(expr.right, env))

    # Evaluate both operands
    let left = eval_expr(expr.left, env)
    let right = eval_expr(expr.right, env)

    # ---- FAST PATH: number+number arithmetic ----
    # ~70% of binary ops in benchmarks are number arithmetic.
    # Inlining avoids dispatch table lookup + proc call overhead.
    if type(left) == "number" and type(right) == "number":
        if op_type == TOKEN_PLUS:
            return left + right
        if op_type == TOKEN_MINUS:
            return left - right
        if op_type == TOKEN_STAR:
            return left * right
        if op_type == TOKEN_SLASH:
            if right == 0:
                runtime_error(expr.op.line, "Division by zero", nil)
            return left / right
        if op_type == TOKEN_PERCENT:
            if right == 0:
                runtime_error(expr.op.line, "Modulo by zero", nil)
            return left % right
        if op_type == TOKEN_GT:
            return left > right
        if op_type == TOKEN_LT:
            return left < right
        if op_type == TOKEN_GTE:
            return left >= right
        if op_type == TOKEN_LTE:
            return left <= right
        if op_type == TOKEN_EQ:
            return left == right
        if op_type == TOKEN_NEQ:
            return left != right
        # Bitwise on numbers
        if op_type == TOKEN_AMP:
            return left & right
        if op_type == TOKEN_PIPE:
            return left | right
        if op_type == TOKEN_CARET:
            return left ^ right
        if op_type == TOKEN_LSHIFT:
            return left << right
        if op_type == TOKEN_RSHIFT:
            return left >> right

    # ---- SLOW PATH: mixed types — dispatch table ----
    if op_type == TOKEN_SLASH and right == 0:
        runtime_error(expr.op.line, "Division by zero", nil)
    if op_type == TOKEN_PERCENT and right == 0:
        runtime_error(expr.op.line, "Modulo by zero", nil)

    if dict_has(_binop_dispatch, op_type):
        return _binop_dispatch[op_type](left, right)

    runtime_error(expr.op.line, "Unknown binary operator type: " + str(op_type), nil)

# -----------------------------------------
# Helper: find method in class hierarchy
# -----------------------------------------

proc find_method(cls, name):
    let search = cls
    while search != nil:
        let meths = search["methods"]
        if dict_has(meths, name):
            return meths[name]
        search = search["parent"]
    return nil

# -----------------------------------------
# Check if a statement body contains yield
# -----------------------------------------

proc body_has_yield(stmt):
    if stmt == nil:
        return false
    let stype = stmt.type
    if stype == STMT_YIELD:
        return true
    if stype == STMT_BLOCK:
        let current = stmt.statements
        while current != nil:
            if body_has_yield(current):
                return true
            current = current.next
        return false
    if stype == STMT_IF:
        if body_has_yield(stmt.then_branch):
            return true
        if stmt.else_branch != nil:
            if body_has_yield(stmt.else_branch):
                return true
        return false
    if stype == STMT_WHILE:
        return body_has_yield(stmt.body)
    if stype == STMT_FOR:
        return body_has_yield(stmt.body)
    return false

# -----------------------------------------
# Generator: eagerly collect all yielded values
# -----------------------------------------

proc run_generator(body, env):
    let values = []
    # Execute the generator body, collecting yield values
    # Walk the statement list, collecting yields
    let stmts = body
    if stmts != nil:
        collect_yields(stmts, env, values)
    let gen = {}
    gen["__interp_type"] = "generator"
    gen["values"] = values
    gen["index"] = 0
    return gen

proc collect_yields(stmt, env, values):
    if stmt == nil:
        return
    let stype = stmt.type
    if stype == STMT_YIELD:
        let val = nil
        if stmt.value != nil:
            val = eval_expr(stmt.value, env)
        push(values, val)
        return
    if stype == STMT_BLOCK:
        let current = stmt.statements
        while current != nil:
            collect_yields(current, env, values)
            current = current.next
        return
    if stype == STMT_WHILE:
        # For generators with while loops, execute the loop and collect yields
        let iters = 0
        while true:
            let cond = eval_expr(stmt.condition, env)
            if not is_truthy(cond):
                break
            iters = iters + 1
            if iters > MAX_LOOP_ITERATIONS:
                break
            collect_yields(stmt.body, env, values)
        return
    # For other statement types, just execute them normally
    exec_stmt(stmt, env)

# -----------------------------------------
# Call expression evaluation
# -----------------------------------------

proc eval_call(expr, env):
    # Recursion depth check at call boundary only
    g_depth = g_depth + 1
    if g_depth > MAX_RECURSION:
        g_depth = g_depth - 1
        runtime_error(get_expr_line(expr.callee), "Maximum recursion depth exceeded", "limit is " + str(MAX_RECURSION) + " frames")
    let _call_result = eval_call_impl(expr, env)
    g_depth = g_depth - 1
    return _call_result

proc eval_call_impl(expr, env):
    let callee_expr = expr.callee

    # Super method call: super.method(args)
    if callee_expr.type == EXPR_SUPER:
        let method_name = callee_expr.method.text
        let self_val = env_get(env, "self")
        if type(self_val) == "dict" and dict_has(self_val, "__interp_type") and self_val["__interp_type"] == "instance":
            let cls = self_val["class"]
            let parent = cls["parent"]
            if parent != nil:
                let method_val = find_method(parent, method_name)
                if method_val != nil:
                    # Evaluate arguments
                    let args = []
                    let ai = 0
                    while ai < expr.arg_count:
                        push(args, eval_expr(expr.args[ai], env))
                        ai = ai + 1
                    # Create method env with self bound
                    let method_env = env_new(method_val["closure"])
                    env_define(method_env, "self", self_val)
                    let params = method_val["params"]
                    let param_start = 0
                    if len(params) > 0 and params[0].text == "self":
                        param_start = 1
                    let pi = param_start
                    while pi < len(params):
                        let arg_idx = pi - param_start
                        if arg_idx < len(args):
                            env_define(method_env, params[pi].text, args[arg_idx])
                        else:
                            env_define(method_env, params[pi].text, nil)
                        pi = pi + 1
                    let res = exec_stmt(method_val["body"], method_env)
                    if res["kind"] == SIGNAL_RETURN:
                        return res["value"]
                    return nil
                runtime_error(-1, "Undefined method '" + method_name + "' in parent class", nil)
            runtime_error(-1, "Class has no parent for super call", nil)
        runtime_error(-1, "super used outside of class method", nil)

    # Method call: obj.method(args)
    if callee_expr.type == EXPR_GET:
        let obj = eval_expr(callee_expr.object, env)
        let method_name = callee_expr.property.text

        # Instance method call
        if type(obj) == "dict" and dict_has(obj, "__interp_type") and obj["__interp_type"] == "instance":
            let cls = obj["class"]
            let method_val = find_method(cls, method_name)
            if method_val == nil:
                runtime_error(callee_expr.property.line, "Undefined method '" + method_name + "'", nil)
            # Evaluate arguments
            let args = []
            let i = 0
            while i < expr.arg_count:
                let arg = eval_expr(expr.args[i], env)
                push(args, arg)
                i = i + 1
            # Create method env with self bound
            let method_env = env_new(method_val["closure"])
            env_define(method_env, "self", obj)
            # Bind params (skip first if it's 'self')
            let params = method_val["params"]
            let param_start = 0
            if len(params) > 0:
                if params[0].text == "self":
                    param_start = 1
            let pi = param_start
            while pi < len(params):
                let arg_idx = pi - param_start
                if arg_idx < len(args):
                    env_define(method_env, params[pi].text, args[arg_idx])
                else:
                    env_define(method_env, params[pi].text, nil)
                pi = pi + 1
            let res = exec_stmt(method_val["body"], method_env)
            if res["kind"] == SIGNAL_RETURN:
                return res["value"]
            return nil

    # Evaluate callee
    let callee = eval_expr(callee_expr, env)

    # Evaluate arguments
    let args = []
    let i = 0
    while i < expr.arg_count:
        let arg = eval_expr(expr.args[i], env)
        push(args, arg)
        i = i + 1

    if type(callee) != "dict":
        runtime_error(get_expr_line(callee_expr), "Value is not callable", "got value of type '" + type(callee) + "'")

    if not dict_has(callee, "__interp_type"):
        runtime_error(get_expr_line(callee_expr), "Value is not callable", "got a dict that is not a function or class")

    let callee_type = callee["__interp_type"]

    # Native function call
    if callee_type == "native":
        return call_native(callee["name"], args)

    # User function call
    if callee_type == "function":
        let func_env = env_new(callee["closure"])
        let params = callee["params"]
        let pi = 0
        while pi < len(params):
            if pi < len(args):
                env_define(func_env, params[pi].text, args[pi])
            else:
                env_define(func_env, params[pi].text, nil)
            pi = pi + 1
        # Check if this is a generator function (contains yield)
        if dict_has(callee, "is_generator"):
            if callee["is_generator"]:
                return run_generator(callee["body"], func_env)
        let res = exec_stmt(callee["body"], func_env)
        if res["kind"] == SIGNAL_RETURN:
            return res["value"]
        if res["kind"] == SIGNAL_YIELD:
            # Function yielded — create generator eagerly
            let gen = {}
            gen["__interp_type"] = "generator"
            gen["values"] = [res["value"]]
            gen["index"] = 0
            return gen
        return nil

    # Class instantiation
    if callee_type == "class":
        let inst = {}
        inst["__interp_type"] = "instance"
        inst["class"] = callee
        inst["fields"] = {}
        # Call init if exists
        let methods = callee["methods"]
        if dict_has(methods, "init"):
            let init_method = methods["init"]
            let init_env = env_new(init_method["closure"])
            env_define(init_env, "self", inst)
            let params = init_method["params"]
            let param_start = 0
            if len(params) > 0:
                if params[0].text == "self":
                    param_start = 1
            let pi = param_start
            while pi < len(params):
                let arg_idx = pi - param_start
                if arg_idx < len(args):
                    env_define(init_env, params[pi].text, args[arg_idx])
                else:
                    env_define(init_env, params[pi].text, nil)
                pi = pi + 1
            exec_stmt(init_method["body"], init_env)
        return inst

    runtime_error(get_expr_line(callee_expr), "Value is not callable", "got '" + callee_type + "'")

# -----------------------------------------
# Statement execution
# Returns a dict: {"kind": SIGNAL_*, "value": ...}
# -----------------------------------------

proc exec_stmt(stmt, env):
    if stmt == nil:
        return _SIG_NORMAL_NIL

    let stype = stmt.type

    # --- Print ---
    if stype == STMT_PRINT:
        let val = eval_expr(stmt.expression, env)
        print value_to_string(val)
        return _SIG_NORMAL_NIL

    # --- Expression statement ---
    if stype == STMT_EXPRESSION:
        eval_expr(stmt.expression, env)
        return _SIG_NORMAL_NIL

    # --- Let ---
    if stype == STMT_LET:
        let val = nil
        if stmt.initializer != nil:
            val = eval_expr(stmt.initializer, env)
        env_define(env, stmt.name.text, val)
        return _SIG_NORMAL_NIL

    # --- Block ---
    if stype == STMT_BLOCK:
        return exec_block(stmt.statements, env)

    # --- If ---
    if stype == STMT_IF:
        let cond = eval_expr(stmt.condition, env)
        if is_truthy(cond):
            return exec_stmt(stmt.then_branch, env)
        if stmt.else_branch != nil:
            return exec_stmt(stmt.else_branch, env)
        return _SIG_NORMAL_NIL

    # --- While ---
    if stype == STMT_WHILE:
        let loop_iters = 0
        while true:
            let cond = eval_expr(stmt.condition, env)
            if not is_truthy(cond):
                break
            loop_iters = loop_iters + 1
            if loop_iters > MAX_LOOP_ITERATIONS:
                raise "While loop exceeded maximum iterations (1000000)"
            let res = exec_stmt(stmt.body, env)
            let kind = res["kind"]
            if kind == SIGNAL_RETURN:
                return res
            if kind == SIGNAL_BREAK:
                break
            # SIGNAL_CONTINUE falls through to next iteration
        return _SIG_NORMAL_NIL

    # --- For ---
    if stype == STMT_FOR:
        let iterable = eval_expr(stmt.iterable, env)
        if type(iterable) != "array":
            runtime_error(stmt.variable.line, "for loop iterable must be an array", "got value of type '" + type(iterable) + "'")
        let loop_env = env_new(env)
        let var_name = stmt.variable.text
        let n = len(iterable)
        let i = 0
        while i < n:
            env_define(loop_env, var_name, iterable[i])
            let res = exec_stmt(stmt.body, loop_env)
            let kind = res["kind"]
            if kind == SIGNAL_RETURN:
                return res
            if kind == SIGNAL_BREAK:
                break
            i = i + 1
        return _SIG_NORMAL_NIL

    # --- Proc --- (single-dict-literal construction for speed)
    if stype == STMT_PROC:
        let name = stmt.name.text
        env_define(env, name, {
            "__interp_type": "function",
            "name": name,
            "params": stmt.params,
            "body": stmt.body,
            "closure": env,
            "is_generator": body_has_yield(stmt.body)
        })
        return _SIG_NORMAL_NIL

    # --- Return ---
    if stype == STMT_RETURN:
        let val = nil
        if stmt.value != nil:
            val = eval_expr(stmt.value, env)
        return result_return(val)

    # --- Break ---
    if stype == STMT_BREAK:
        return result_break()

    # --- Continue ---
    if stype == STMT_CONTINUE:
        return result_continue()

    # --- Class ---
    if stype == STMT_CLASS:
        let name_tok = stmt.name
        let name = name_tok.text
        let cls = {}
        cls["__interp_type"] = "class"
        cls["name"] = name
        cls["methods"] = {}
        cls["parent"] = nil

        # Resolve parent class
        if stmt.has_parent:
            let ptok = stmt.parent
            let parent_name = ptok.text
            let parent_val = env_get(env, parent_name)
            if type(parent_val) == "dict" and dict_has(parent_val, "__interp_type") and parent_val["__interp_type"] == "class":
                cls["parent"] = parent_val
                # Inherit parent methods
                let parent_methods = parent_val["methods"]
                let pkeys = dict_keys(parent_methods)
                let pi = 0
                while pi < len(pkeys):
                    cls["methods"][pkeys[pi]] = parent_methods[pkeys[pi]]
                    pi = pi + 1
            else:
                runtime_error(stmt.name.line, "Parent '" + parent_name + "' is not a class", nil)

        # Add methods (linked list from parser)
        let method_node = stmt.methods
        while method_node != nil:
            if method_node.type == STMT_PROC:
                let mn_tok = method_node.name
                let mname = mn_tok.text
                let mfunc = {}
                mfunc["__interp_type"] = "function"
                mfunc["name"] = mname
                mfunc["params"] = method_node.params
                mfunc["body"] = method_node.body
                mfunc["closure"] = env
                cls["methods"][mname] = mfunc
            method_node = method_node.next
        env_define(env, name, cls)
        return _SIG_NORMAL_NIL

    # --- Try/Catch ---
    if stype == STMT_TRY:
        return exec_try(stmt, env)

    # --- Raise ---
    if stype == STMT_RAISE:
        let val = eval_expr(stmt.exception, env)
        if type(val) == "string":
            raise val
        raise value_to_string(val)

    # --- Import ---
    if stype == STMT_IMPORT:
        let mod_name = stmt.module_name.text
        # Check stdlib modules first
        from stdlib import get_stdlib_module, is_stdlib_module
        if is_stdlib_module(mod_name):
            let mod_env = get_stdlib_module(mod_name)
            import_bind(stmt, mod_name, {"vals": mod_env}, env)
            return _SIG_NORMAL_NIL
        # Check module cache first
        if dict_has(g_module_cache, mod_name):
            let mod_env = g_module_cache[mod_name]
            import_bind(stmt, mod_name, mod_env, env)
            return _SIG_NORMAL_NIL
        # Try to find and load the module file
        let mod_source = nil
        let mod_path = nil
        let si = 0
        while si < len(g_module_paths):
            let try_path = g_module_paths[si] + "/" + mod_name + ".sage"
            if io.exists(try_path):
                mod_source = io.readfile(try_path)
                mod_path = try_path
                break
            si = si + 1
        if mod_source == nil:
            raise "ImportError: module '" + mod_name + "' not found"
        # Parse and execute the module in a fresh env
        from parser import parse_source_file
        let mod_stmts = parse_source_file(mod_source, mod_path)
        let mod_env = new_interpreter()
        g_module_cache[mod_name] = mod_env
        exec_program(mod_stmts, mod_env)
        import_bind(stmt, mod_name, mod_env, env)
        return _SIG_NORMAL_NIL

    # --- Async proc (registered as function with async flag) ---
    if stype == STMT_ASYNC_PROC:
        let name = stmt.name.text
        let func = {}
        func["__interp_type"] = "function"
        func["name"] = name
        func["params"] = stmt.params
        func["body"] = stmt.body
        func["closure"] = env
        func["is_async"] = true
        func["is_generator"] = false
        env_define(env, name, func)
        return _SIG_NORMAL_NIL

    # --- Defer ---
    if stype == STMT_DEFER:
        # Defer is handled at block level; standalone just executes immediately
        return exec_stmt(stmt.statement, env)

    # --- Match (with guard support) ---
    if stype == STMT_MATCH:
        let match_val = eval_expr(stmt.value, env)
        let i = 0
        while i < stmt.case_count:
            let clause = stmt.cases[i]
            let pat_val = eval_expr(clause["pattern"], env)
            if match_val == pat_val:
                # Check guard condition if present
                if dict_has(clause, "guard") and clause["guard"] != nil:
                    let guard_val = eval_expr(clause["guard"], env)
                    if is_truthy(guard_val):
                        return exec_stmt(clause["body"], env)
                    # Guard failed, continue to next case
                else:
                    return exec_stmt(clause["body"], env)
            i = i + 1
        if stmt.default_case != nil:
            return exec_stmt(stmt.default_case, env)
        return _SIG_NORMAL_NIL

    # --- Yield ---
    if stype == STMT_YIELD:
        let val = nil
        if stmt.value != nil:
            val = eval_expr(stmt.value, env)
        let r = {}
        r["kind"] = SIGNAL_YIELD
        r["value"] = val
        return r

    # --- Struct declaration ---
    if stype == STMT_STRUCT:
        let name = stmt.name.text
        let struct_def = {}
        struct_def["__interp_type"] = "struct_def"
        struct_def["name"] = name
        struct_def["fields"] = []
        let fi = 0
        while fi < stmt.field_count:
            push(struct_def["fields"], stmt.field_names[fi].text)
            fi = fi + 1
        # Register a constructor function for the struct
        let struct_ctor = {}
        struct_ctor["__interp_type"] = "native"
        struct_ctor["name"] = name
        struct_ctor["arity"] = -1
        struct_ctor["struct_def"] = struct_def
        env_define(env, name, struct_def)
        return _SIG_NORMAL_NIL

    # --- Enum declaration ---
    if stype == STMT_ENUM:
        let name = stmt.name.text
        let enum_def = {}
        enum_def["__interp_type"] = "enum"
        enum_def["name"] = name
        enum_def["variants"] = {}
        let vi = 0
        while vi < stmt.variant_count:
            let vname = stmt.variant_names[vi].text
            enum_def["variants"][vname] = vi
            # Also define each variant as a global constant
            env_define(env, vname, vi)
            vi = vi + 1
        env_define(env, name, enum_def)
        return _SIG_NORMAL_NIL

    # --- Trait declaration ---
    if stype == STMT_TRAIT:
        let name = stmt.name.text
        let trait_def = {}
        trait_def["__interp_type"] = "trait"
        trait_def["name"] = name
        trait_def["method_names"] = []
        let method_node = stmt.methods
        while method_node != nil:
            if method_node.type == STMT_PROC:
                push(trait_def["method_names"], method_node.name.text)
            method_node = method_node.next
        env_define(env, name, trait_def)
        return _SIG_NORMAL_NIL

    # --- Comptime block (execute normally at runtime) ---
    if stype == STMT_COMPTIME:
        return exec_stmt(stmt.body, env)

    # --- Macro definition (treat as function) ---
    if stype == STMT_MACRO_DEF:
        let name = stmt.name.text
        env_define(env, name, {
            "__interp_type": "function",
            "name": name,
            "params": stmt.params,
            "body": stmt.body,
            "closure": env,
            "is_generator": false
        })
        return _SIG_NORMAL_NIL

    runtime_error(get_stmt_line(stmt), "Unknown statement type: " + str(stype), nil)

# -----------------------------------------
# Execute a block (linked list of statements)
# -----------------------------------------

proc exec_block(first_stmt, env):
    let current = first_stmt
    while current != nil:
        let res = exec_stmt(current, env)
        if res["kind"] != SIGNAL_NORMAL:
            return res
        current = current.next
    return _SIG_NORMAL_NIL

# -----------------------------------------
# Try/Catch execution
# -----------------------------------------

proc exec_try(stmt, env):
    let caught = false
    let result = result_normal(nil)
    try:
        result = exec_stmt(stmt.try_block, env)
    catch err:
        caught = true
        if stmt.catch_count > 0:
            let clause = stmt.catches[0]
            let catch_env = env_new(env)
            env_define(catch_env, clause.exception_var.text, err)
            result = exec_stmt(clause.body, catch_env)
        else:
            raise err
    if stmt.finally_block != nil:
        exec_stmt(stmt.finally_block, env)
    return result

# -----------------------------------------
# Execute a program (array of top-level statements)
# -----------------------------------------

proc exec_program(global_env, stmts):
    let i = 0
    while i < len(stmts):
        let res = exec_stmt(stmts[i], global_env)
        if res["kind"] == SIGNAL_RETURN:
            return res["value"]
        i = i + 1
    return nil

# -----------------------------------------
# Create a new interpreter (returns a global env dict)
# -----------------------------------------

proc new_interpreter():
    let genv = env_new(nil)
    init_builtins(genv)
    # Initialize stdlib registry
    from stdlib import init_stdlib
    init_stdlib()
    return genv

# -----------------------------------------
# Run source code with an interpreter env
# -----------------------------------------

proc run_source(genv, source):
    from parser import parse_source
    let stmts = parse_source(source)
    return exec_program(genv, stmts)

proc run_source_file(genv, source, filename):
    from parser import parse_source_file
    set_error_context(source, filename)
    let stmts = parse_source_file(source, filename)
    return exec_program(genv, stmts)
