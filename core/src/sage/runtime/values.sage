# ============================================================================
# Runtime Values - Common value model shared across all execution tiers
# ============================================================================
# All tiers must share a common value model for:
#
# nil, booleans, numbers, strings, arrays, dictionaries, functions,
# classes, instances, modules, generators, native handles
# ============================================================================

# Tag enumeration for value types
let TAG_NIL = 0
let TAG_BOOL = 1
let TAG_NUMBER = 2
let TAG_STRING = 3
let TAG_ARRAY = 4
let TAG_DICT = 5
let TAG_TUPLE = 6
let TAG_FUNCTION = 7
let TAG_GENERATOR = 8

# Value structure definition
class Value {
    let tag: Int
    let data: Union {
        let is_nil: Bool = false
        let bool_val: Bool = false
        let num_val: Double = 0.0
        let str_val: String = ""
        let arr_val: Array<Value> = []
        let dict_val: Dict<String, Value> = {}
        let tuple_val: Tuple<Value> = []
        let fn_val: Function = null
        let gen_val: Generator = null
    }
}

# Nil singleton
let nil: Value = Value(TAG_NIL, {is_nil: true})

# Boolean helpers
let true_val: Value = Value(TAG_BOOL, {bool_val: true})
let false_val: Value = Value(TAG_BOOL, {bool_val: false})

# Number value creation
proc value_number(n: Double): Value = Value(TAG_NUMBER, {num_val: n})

# String value creation
proc value_string(s: String): Value = Value(TAG_STRING, {str_val: s})

# Array value creation
proc value_array(elements: Array<Value>): Value = Value(TAG_ARRAY, {arr_val: elements})

# Dictionary value creation
proc value_dict(entries: Dict<String, Value>): Value = Value(TAG_DICT, {dict_val: entries})

# Tuple value creation
proc value_tuple(elements: Array<Value>): Value = Value(TAG_TUPLE, {tuple_val: elements})

# Function value creation
proc value_function(
    id: FunctionId,
    body: IR_Instr,
    params: Array<String>,
    defaults: Array<Value>,
    closure: Env,
    profile: FunctionProfile
): Value = Value(TAG_FUNCTION, {fn_val: Function(id, body, params, defaults, closure, profile)})

# Generator value creation
proc value_generator(
    frame: Frame,
    resume_state: GeneratorResumeState
): Value = Value(TAG_GENERATOR, {gen_val: Generator(frame, resume_state)})

# Truthiness determination (same across all tiers)
proc is_truthy(val: Value): Bool =
    if val.tag == TAG_NIL:
        return false
    if val.tag == TAG_BOOL:
        return val.data.bool_val
    if val.tag == TAG_NUMBER:
        return val.data.num_val != 0.0
    if val.tag == TAG_STRING:
        return val.data.str_val != ""
    if val.tag == TAG_ARRAY:
        return val.data.arr_val.len > 0
    if val.tag == TAG_DICT:
        return val.data.dict_val.len > 0
    if val.tag == TAG_TUPLE:
        return val.data.tuple_val.len > 0
    if val.tag == TAG_FUNCTION:
        return true
    if val.tag == TAG_GENERATOR:
        return true
    return true

# Value equality (used for comparisons)
proc value_eq(a: Value, b: Value): Bool =
    if a.tag != b.tag:
        return false
    return a.data == b.data

# Hash value for dict keys
proc value_hash(val: Value): Int =
    match val.tag:
        TAG_NIL: return 0
        TAG_BOOL: return if val.data.bool_val then 1 else 2
        TAG_NUMBER: return val.data.num_val.toInt()
        TAG_STRING: return val.data.str_val.hash
        TAG_ARRAY: return val.data.arr_val.map { value_hash(_) }.fold(0, +)
        TAG_DICT: return val.data.dict_val.keys.map { value_hash(val_dict[it]) }.fold(0, +)
        TAG_TUPLE: return val.data.tuple_val.map { value_hash(_) }.fold(0, +)
        TAG_FUNCTION: return val.data.fn_val.id.hash
        TAG_GENERATOR: return val.data.gen_val.frame.hash
    return 0

# Common value conversion to string (for diagnostics)
proc value_to_string(val: Value): String =
    match val.tag:
        TAG_NIL: return "nil"
        TAG_BOOL: return if val.data.bool_val then "true" else "false"
        TAG_NUMBER: return val.data.num_val.toString()
        TAG_STRING: return "\"" + val.data.str_val + "\""
        TAG_ARRAY: return "[" + val.data.arr_val.map { value_to_string(_) }.join(", ") + "]"
        TAG_DICT: return "{" + val.data.dict_val.keys.map { k + ": " + value_to_string(val.data.dict_val[k]) }.join(", ") + "}"
        TAG_TUPLE: return "(" + val.data.tuple_val.map { value_to_string(_) }.join(", ") + ")"
        TAG_FUNCTION: return "<fn " + val.data.fn_val.id.source_name + ">"
        TAG_GENERATOR: return "<gen " + str(val.data.gen_val.frame.id) + ">"
    return "unknown"

# Default constructor for testing
let tag_map = [
    TAG_NIL: "NIL",
    TAG_BOOL: "BOOL",
    TAG_NUMBER: "NUMBER", 
    TAG_STRING: "STRING",
    TAG_ARRAY: "ARRAY",
    TAG_DICT: "DICT",
    TAG_TUPLE: "TUPLE",
    TAG_FUNCTION: "FUNCTION",
    TAG_GENERATOR: "GENERATOR"
]
let TAG_NAMES = [TAG_NIL, TAG_BOOL, TAG_NUMBER, TAG_STRING, TAG_ARRAY, TAG_DICT, TAG_TUPLE, TAG_FUNCTION, TAG_GENERATOR].map { tag_map[_] or "UNKNOWN" }
