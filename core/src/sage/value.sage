# SageLang Value Utilities (self-hosted port)
#
# Value type constants and helpers for the self-hosted compiler pipeline.
# In the self-hosted interpreter, values are native Sage values,
# but this module provides type-checking helpers and constructors
# for the compiler's internal representation.

# Type name constants
let TYPE_NIL = "nil"
let TYPE_NUMBER = "number"
let TYPE_BOOL = "bool"
let TYPE_STRING = "string"
let TYPE_ARRAY = "array"
let TYPE_DICT = "dict"
let TYPE_FUNCTION = "function"

# Check if a value is truthy (Sage semantics: only false and nil are falsy)
proc is_truthy(val):
    if val == false:
        return false
    if val == nil:
        return false
    return true

# Check if a value is falsy
proc is_falsy(val):
    return not is_truthy(val)

# Check value type
proc is_nil(val):
    return type(val) == TYPE_NIL

proc is_number(val):
    return type(val) == TYPE_NUMBER

proc is_bool(val):
    return type(val) == TYPE_BOOL

proc is_string(val):
    return type(val) == TYPE_STRING

proc is_array(val):
    return type(val) == TYPE_ARRAY

proc is_dict(val):
    return type(val) == TYPE_DICT

# Safe type coercion
proc to_number(val):
    if type(val) == TYPE_NUMBER:
        return val
    if type(val) == TYPE_STRING:
        return tonumber(val)
    if type(val) == TYPE_BOOL:
        if val:
            return 1
        return 0
    return 0

proc to_string(val):
    return str(val)

proc to_bool(val):
    return is_truthy(val)

# Deep equality check (works for arrays and dicts unlike ==)
proc deep_equal(a, b):
    let ta = type(a)
    let tb = type(b)
    if ta != tb:
        return false
    if ta == TYPE_ARRAY:
        if len(a) != len(b):
            return false
        for i in range(len(a)):
            if not deep_equal(a[i], b[i]):
                return false
        return true
    if ta == TYPE_DICT:
        let ka = dict_keys(a)
        let kb = dict_keys(b)
        if len(ka) != len(kb):
            return false
        for k in ka:
            if not dict_has(b, k):
                return false
            if not deep_equal(a[k], b[k]):
                return false
        return true
    # Primitive comparison
    return a == b

# Deep clone a value
proc deep_clone(val):
    let t = type(val)
    if t == TYPE_ARRAY:
        let result = []
        for item in val:
            push(result, deep_clone(item))
        return result
    if t == TYPE_DICT:
        let result = {}
        let keys = dict_keys(val)
        for k in keys:
            result[k] = deep_clone(val[k])
        return result
    # Primitives are immutable
    return val

# Pretty-print a value with type info
proc inspect(val):
    let t = type(val)
    if t == TYPE_NIL:
        return "<nil>"
    if t == TYPE_NUMBER:
        return "<number: " + str(val) + ">"
    if t == TYPE_BOOL:
        if val:
            return "<bool: true>"
        return "<bool: false>"
    if t == TYPE_STRING:
        return "<string: " + chr(34) + val + chr(34) + ">"
    if t == TYPE_ARRAY:
        return "<array[" + str(len(val)) + "]>"
    if t == TYPE_DICT:
        return "<dict[" + str(len(dict_keys(val))) + "]>"
    return "<" + t + ">"
