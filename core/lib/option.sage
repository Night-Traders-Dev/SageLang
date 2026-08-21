gc_disable()
# safety.sage — Safety library for SageLang
# Provides Option[T] type, ownership markers, and thread-safety traits.
# Uses comptime for type tag constants and @inline for hot accessors.

# ============================================================================
# Option type tag constants — evaluated at compile time
# ============================================================================

comptime:
    let _OPTION_TYPE = "Option"

# ============================================================================
# Option Type — replacement for nil in safe contexts
# ============================================================================

# Create a Some value (wraps a non-nil value)
@inline
proc Some(value):
    let opt = {}
    opt["__type"] = _OPTION_TYPE
    opt["__has_value"] = true
    opt["__value"] = value
    return opt

# Create a None value (represents absence)
@inline
proc None():
    let opt = {}
    opt["__type"] = _OPTION_TYPE
    opt["__has_value"] = false
    opt["__value"] = nil
    return opt

# Check if an Option contains a value
@inline
proc is_some(opt):
    if type(opt) == "dict":
        if dict_has(opt, "__type"):
            return opt["__has_value"]
    return false

# Check if an Option is None
@inline
proc is_none(opt):
    return not is_some(opt)

# Unwrap an Option — raises if None
@inline
proc unwrap(opt):
    if is_some(opt):
        return opt["__value"]
    raise "PANIC: called unwrap() on a None value"

# Unwrap with a default value if None
@inline
proc unwrap_or(opt, default_val):
    if is_some(opt):
        return opt["__value"]
    return default_val

# Unwrap with a function to compute default if None
@inline
proc unwrap_or_else(opt, default_fn):
    if is_some(opt):
        return opt["__value"]
    return default_fn()

# Map a function over the contained value (if any)
proc map(opt, fn):
    if is_some(opt):
        return Some(fn(opt["__value"]))
    return None()

# Flat-map: map then flatten (if fn returns an Option)
proc and_then(opt, fn):
    if is_some(opt):
        return fn(opt["__value"])
    return None()

# Return the Option if it has a value, else return the fallback Option
proc or_else(opt, fallback_fn):
    if is_some(opt):
        return opt
    return fallback_fn()

# Filter: keep the value only if predicate is true
proc filter(opt, pred):
    if is_some(opt):
        if pred(opt["__value"]):
            return opt
    return None()

# Convert Option to string for display
proc option_to_str(opt):
    if is_some(opt):
        return "Some(" + str(opt["__value"]) + ")"
    return "None"

# ============================================================================
# Ownership Markers — semantic annotations for safety analysis
# ============================================================================

@inline
proc own(value):
    return value

@inline
proc ref(value):
    return value

@inline
proc mut_ref(value):
    return value

# ============================================================================
# Thread-Safety Markers
# ============================================================================

@inline
proc mark_send(value):
    if type(value) == "dict":
        value["__send"] = true
    return value

@inline
proc mark_sync(value):
    if type(value) == "dict":
        value["__sync"] = true
    return value

@inline
proc is_send(value):
    if type(value) == "dict":
        if dict_has(value, "__send"):
            return value["__send"]
    # Primitives are always Send
    let t = type(value)
    if t == "number":
        return true
    if t == "string":
        return true
    if t == "bool":
        return true
    return false

@inline
proc is_sync(value):
    if type(value) == "dict":
        if dict_has(value, "__sync"):
            return value["__sync"]
    return false

# ============================================================================
# Copy Trait
# ============================================================================

proc copy(value):
    let t = type(value)
    if t == "number" or t == "string" or t == "bool":
        return value
    if t == "array":
        let result = []
        let i = 0
        while i < len(value):
            push(result, copy(value[i]))
            i = i + 1
        return result
    if t == "dict":
        let result = {}
        let keys = dict_keys(value)
        let i = 0
        while i < len(keys):
            result[keys[i]] = copy(value[keys[i]])
            i = i + 1
        return result
    return value
