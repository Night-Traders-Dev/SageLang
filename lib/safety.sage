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
end

# Create a None value (represents absence)
@inline
proc None():
    let opt = {}
    opt["__type"] = _OPTION_TYPE
    opt["__has_value"] = false
    opt["__value"] = nil
    return opt
end

# Check if an Option contains a value
@inline
proc is_some(opt):
    if type(opt) == "dict":
        if dict_has(opt, "__type"):
            return opt["__has_value"]
        end
    end
    return false
end

# Check if an Option is None
@inline
proc is_none(opt):
    return not is_some(opt)
end

# Unwrap an Option — panics if None
@inline
proc unwrap(opt):
    if is_some(opt):
        return opt["__value"]
    end
    print "PANIC: called unwrap() on a None value"
    return nil
end

# Unwrap with a default value if None
@inline
proc unwrap_or(opt, default_val):
    if is_some(opt):
        return opt["__value"]
    end
    return default_val
end

# Unwrap with a function to compute default if None
@inline
proc unwrap_or_else(opt, default_fn):
    if is_some(opt):
        return opt["__value"]
    end
    return default_fn()
end

# Map a function over the contained value (if any)
proc map(opt, fn):
    if is_some(opt):
        return Some(fn(opt["__value"]))
    end
    return None()
end

# Flat-map: map then flatten (if fn returns an Option)
proc and_then(opt, fn):
    if is_some(opt):
        return fn(opt["__value"])
    end
    return None()
end

# Return the Option if it has a value, else return the fallback Option
proc or_else(opt, fallback_fn):
    if is_some(opt):
        return opt
    end
    return fallback_fn()
end

# Filter: keep the value only if predicate is true
proc filter(opt, pred):
    if is_some(opt):
        if pred(opt["__value"]):
            return opt
        end
    end
    return None()
end

# Convert Option to string for display
proc option_to_str(opt):
    if is_some(opt):
        return "Some(" + str(opt["__value"]) + ")"
    end
    return "None"
end

# ============================================================================
# Ownership Markers — semantic annotations for safety analysis
# ============================================================================

@inline
proc own(value):
    return value
end

@inline
proc ref(value):
    return value
end

@inline
proc mut_ref(value):
    return value
end

# ============================================================================
# Thread-Safety Markers
# ============================================================================

@inline
proc mark_send(value):
    if type(value) == "dict":
        value["__send"] = true
    end
    return value
end

@inline
proc mark_sync(value):
    if type(value) == "dict":
        value["__sync"] = true
    end
    return value
end

@inline
proc is_send(value):
    if type(value) == "dict":
        if dict_has(value, "__send"):
            return value["__send"]
        end
    end
    # Primitives are always Send
    let t = type(value)
    if t == "number":
        return true
    end
    if t == "string":
        return true
    end
    if t == "bool":
        return true
    end
    return false
end

@inline
proc is_sync(value):
    if type(value) == "dict":
        if dict_has(value, "__sync"):
            return value["__sync"]
        end
    end
    return false
end

# ============================================================================
# Copy Trait
# ============================================================================

proc copy(value):
    let t = type(value)
    if t == "number" or t == "string" or t == "bool":
        return value
    end
    if t == "array":
        let result = []
        let i = 0
        while i < len(value):
            push(result, copy(value[i]))
            i = i + 1
        end
        return result
    end
    if t == "dict":
        let result = {}
        let keys = dict_keys(value)
        let i = 0
        while i < len(keys):
            result[keys[i]] = copy(value[keys[i]])
            i = i + 1
        end
        return result
    end
    return value
end
