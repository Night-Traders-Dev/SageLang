gc_disable()
# -----------------------------------------
# interpreter.sage - Tree-walking interpreter for SageLang
# Self-hosted implementation (Phase 13)
# -----------------------------------------

from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER, STMT_MATCH
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
    let e = {}
    e["parent"] = parent
    e["vals"] = {}
    return e

proc env_define(env, name, value):
    env["vals"][name] = value

proc env_get(env, name):
    if dict_has(env["vals"], name):
        return env["vals"][name]
    if env["parent"] != nil:
        return env_get(env["parent"], name)
    raise "Undefined variable '" + name + "'"

proc env_set(env, name, value):
    if dict_has(env["vals"], name):
        env["vals"][name] = value
        return true
    if env["parent"] != nil:
        return env_set(env["parent"], name, value)
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
    let r = {}
    r["kind"] = SIGNAL_BREAK
    r["value"] = nil
    return r

proc result_continue():
    let r = {}
    r["kind"] = SIGNAL_CONTINUE
    r["value"] = nil
    return r

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

proc call_native(name, args):
    if name == "str":
        return value_to_string(args[0])
    if name == "len":
        let x = args[0]
        if type(x) == "string":
            return len(x)
        if type(x) == "array":
            return len(x)
        if type(x) == "dict":
            return len(dict_keys(x))
        return 0
    if name == "tonumber":
        let x = args[0]
        if type(x) == "number":
            return x
        if type(x) == "string":
            return tonumber(x)
        return 0
    if name == "push":
        push(args[0], args[1])
        return nil
    if name == "pop":
        return pop(args[0])
    if name == "array_extend":
        let arr = args[0]
        let other = args[1]
        let i = 0
        while i < len(other):
            push(arr, other[i])
            i = i + 1
        return nil
    if name == "range":
        let argc = len(args)
        if argc == 1:
            return range(args[0])
        if argc == 2:
            return range(args[0], args[1])
        return []
    if name == "type":
        let x = args[0]
        if x == nil:
            return "nil"
        if x == true or x == false:
            return "bool"
        if type(x) == "number":
            return "number"
        if type(x) == "string":
            return "string"
        if type(x) == "array":
            return "array"
        if type(x) == "dict":
            if dict_has(x, "__interp_type"):
                let vt = x["__interp_type"]
                if vt == "function":
                    return "function"
                if vt == "native":
                    return "native"
                if vt == "class":
                    return "class"
                if vt == "instance":
                    return "instance"
            return "dict"
        return type(x)
    if name == "input":
        return input()
    if name == "clock":
        return clock()
    if name == "chr":
        return chr(args[0])
    if name == "ord":
        return ord(args[0])
    if name == "slice":
        return slice(args[0], args[1], args[2])
    if name == "split":
        return split(args[0], args[1])
    if name == "join":
        return join(args[0], args[1])
    if name == "replace":
        return replace(args[0], args[1], args[2])
    if name == "upper":
        return upper(args[0])
    if name == "lower":
        return lower(args[0])
    if name == "strip":
        return strip(args[0])
    if name == "dict_keys":
        return dict_keys(args[0])
    if name == "dict_values":
        return dict_values(args[0])
    if name == "dict_has":
        return dict_has(args[0], args[1])
    if name == "dict_delete":
        dict_delete(args[0], args[1])
        return nil
    if name == "startswith":
        return startswith(args[0], args[1])
    if name == "endswith":
        return endswith(args[0], args[1])
    if name == "contains":
        return contains(args[0], args[1])
    if name == "indexof":
        return indexof(args[0], args[1])
    runtime_error(-1, "Unknown native function: " + name, nil)

# -----------------------------------------
# Register builtins into an environment
# -----------------------------------------

proc register_native(env, name, arity):
    let f = {}
    f["__interp_type"] = "native"
    f["name"] = name
    f["arity"] = arity
    env_define(env, name, f)

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

# -----------------------------------------
# Expression evaluation
# -----------------------------------------

proc eval_expr(expr, env):
    if expr == nil:
        return nil
    g_depth = g_depth + 1
    if g_depth > MAX_RECURSION:
        g_depth = g_depth - 1
        runtime_error(get_expr_line(expr), "Maximum recursion depth exceeded", "limit is " + str(MAX_RECURSION) + " frames")
    let result = eval_expr_impl(expr, env)
    g_depth = g_depth - 1
    return result

proc eval_expr_impl(expr, env):
    let etype = expr.type

    # --- Literals ---
    if etype == EXPR_NUMBER:
        return expr.value

    if etype == EXPR_STRING:
        return expr.value

    if etype == EXPR_BOOL:
        return expr.value

    if etype == EXPR_NIL:
        return nil

    # --- Variable ---
    if etype == EXPR_VARIABLE:
        let name = expr.name.text
        try:
            return env_get(env, name)
        catch err:
            runtime_error(expr.name.line, "Undefined variable '" + name + "'", nil)

    # --- Binary ---
    if etype == EXPR_BINARY:
        return eval_binary(expr, env)

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

    # --- Await (stub) ---
    if etype == EXPR_AWAIT:
        return eval_expr(expr.expression, env)

    runtime_error(-1, "Unknown expression type: " + str(etype), nil)

# -----------------------------------------
# Binary expression evaluation
# -----------------------------------------

proc eval_binary(expr, env):
    let op_type = expr.op.type

    # Unary not
    if op_type == TOKEN_NOT:
        let left = eval_expr(expr.left, env)
        return not is_truthy(left)

    # Unary bitwise not (~)
    if op_type == TOKEN_TILDE:
        let left = eval_expr(expr.left, env)
        if type(left) == "number":
            # ~n == -(n + 1) for two's complement integers
            let n = tonumber(str(left))
            return 0 - n - 1
        raise "Bitwise NOT requires a number operand"

    # Short-circuit: or
    if op_type == TOKEN_OR:
        let left = eval_expr(expr.left, env)
        if is_truthy(left):
            return true
        let right = eval_expr(expr.right, env)
        return is_truthy(right)

    # Short-circuit: and
    if op_type == TOKEN_AND:
        let left = eval_expr(expr.left, env)
        if not is_truthy(left):
            return false
        let right = eval_expr(expr.right, env)
        return is_truthy(right)

    let left = eval_expr(expr.left, env)
    let right = eval_expr(expr.right, env)

    # Equality
    if op_type == TOKEN_EQ:
        return left == right
    if op_type == TOKEN_NEQ:
        return left != right

    # Comparison
    if op_type == TOKEN_GT:
        return left > right
    if op_type == TOKEN_LT:
        return left < right
    if op_type == TOKEN_GTE:
        return left >= right
    if op_type == TOKEN_LTE:
        return left <= right

    # Arithmetic
    if op_type == TOKEN_PLUS:
        if type(left) == "number" and type(right) == "number":
            return left + right
        if type(left) == "string" and type(right) == "string":
            return left + right
        if type(left) == "string":
            return left + value_to_string(right)
        if type(right) == "string":
            return value_to_string(left) + right
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

    # Bitwise operators
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
# Call expression evaluation
# -----------------------------------------

proc eval_call(expr, env):
    let callee_expr = expr.callee

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
        let res = exec_stmt(callee["body"], func_env)
        if res["kind"] == SIGNAL_RETURN:
            return res["value"]
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
        return result_normal(nil)

    let stype = stmt.type

    # --- Print ---
    if stype == STMT_PRINT:
        let val = eval_expr(stmt.expression, env)
        print value_to_string(val)
        return result_normal(nil)

    # --- Expression statement ---
    if stype == STMT_EXPRESSION:
        let val = eval_expr(stmt.expression, env)
        return result_normal(val)

    # --- Let ---
    if stype == STMT_LET:
        let val = nil
        if stmt.initializer != nil:
            val = eval_expr(stmt.initializer, env)
        let name = stmt.name.text
        env_define(env, name, val)
        return result_normal(nil)

    # --- Block ---
    if stype == STMT_BLOCK:
        return exec_block(stmt.statements, env)

    # --- If ---
    if stype == STMT_IF:
        let cond = eval_expr(stmt.condition, env)
        if is_truthy(cond):
            return exec_stmt(stmt.then_branch, env)
        elif stmt.else_branch != nil:
            return exec_stmt(stmt.else_branch, env)
        return result_normal(nil)

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
            if res["kind"] == SIGNAL_RETURN:
                return res
            if res["kind"] == SIGNAL_BREAK:
                break
            if res["kind"] == SIGNAL_CONTINUE:
                continue
        return result_normal(nil)

    # --- For ---
    if stype == STMT_FOR:
        let iterable = eval_expr(stmt.iterable, env)
        if type(iterable) != "array":
            runtime_error(stmt.variable.line, "for loop iterable must be an array", "got value of type '" + type(iterable) + "'")
        let loop_env = env_new(env)
        let var_name = stmt.variable.text
        let i = 0
        while i < len(iterable):
            env_define(loop_env, var_name, iterable[i])
            let res = exec_stmt(stmt.body, loop_env)
            if res["kind"] == SIGNAL_RETURN:
                return res
            if res["kind"] == SIGNAL_BREAK:
                break
            if res["kind"] == SIGNAL_CONTINUE:
                i = i + 1
                continue
            i = i + 1
        return result_normal(nil)

    # --- Proc ---
    if stype == STMT_PROC:
        let name = stmt.name.text
        let func = {}
        func["__interp_type"] = "function"
        func["name"] = name
        func["params"] = stmt.params
        func["body"] = stmt.body
        func["closure"] = env
        env_define(env, name, func)
        return result_normal(nil)

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
        return result_normal(nil)

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
        # Check module cache first
        if dict_has(g_module_cache, mod_name):
            let mod_env = g_module_cache[mod_name]
            import_bind(stmt, mod_name, mod_env, env)
            return result_normal(nil)
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
        return result_normal(nil)

    # --- Async proc (treat as regular proc) ---
    if stype == STMT_ASYNC_PROC:
        let name = stmt.name.text
        let func = {}
        func["__interp_type"] = "function"
        func["name"] = name
        func["params"] = stmt.params
        func["body"] = stmt.body
        func["closure"] = env
        env_define(env, name, func)
        return result_normal(nil)

    # --- Defer / Match / Yield (stubs) ---
    if stype == STMT_DEFER:
        return result_normal(nil)
    if stype == STMT_MATCH:
        return result_normal(nil)
    if stype == STMT_YIELD:
        return result_normal(nil)

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
    return result_normal(nil)

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
