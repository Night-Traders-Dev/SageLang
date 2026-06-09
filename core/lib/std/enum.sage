gc_disable()
# Enum (enumeration) and tagged union types
# Provides enum definition, variant matching, and ADT patterns

# ============================================================================
# Enum definition
# ============================================================================

# Define an enum with named variants
# enum("Color", ["Red", "Green", "Blue"]) -> enum descriptor
proc enum_def(name, variants):
    let e = {}
    e["__type"] = "enum"
    e["name"] = name
    e["variants"] = variants
    e["values"] = {}
    for i in range(len(variants)):
        e["values"][variants[i]] = i
    return e

# Create an enum value
proc variant(enum_type, variant_name):
    let v = {}
    v["__type"] = "enum_value"
    v["enum"] = enum_type["name"]
    v["variant"] = variant_name
    v["value"] = enum_type["values"][variant_name]
    v["data"] = nil
    return v

# Create an enum value with associated data (tagged union / ADT)
proc variant_data(enum_type, variant_name, data):
    let v = variant(enum_type, variant_name)
    v["data"] = data
    return v

# Check if a value is a specific variant
proc is_variant(val, variant_name):
    if type(val) != "dict":
        return false
    if not dict_has(val, "__type"):
        return false
    if val["__type"] != "enum_value":
        return false
    return val["variant"] == variant_name

# Get the variant name
proc variant_name(val):
    if type(val) != "dict" or not dict_has(val, "variant"):
        return nil
    return val["variant"]

# Get the associated data
proc variant_data_get(val):
    if type(val) != "dict" or not dict_has(val, "data"):
        return nil
    return val["data"]

# Match an enum value against a dict of handlers
# handlers: {"Red": proc(data), "Green": proc(data), "_": proc(data)}
proc enum_match(val, handlers):
    let name = val["variant"]
    if dict_has(handlers, name):
        return handlers[name](val["data"])
    if dict_has(handlers, "_"):
        return handlers["_"](val["data"])
    return nil

# ============================================================================
# Result type (Ok/Err)
# ============================================================================

let Result = enum_def("Result", ["Ok", "Err"])

proc ok(value):
    return variant_data(Result, "Ok", value)

proc err(error):
    return variant_data(Result, "Err", error)

proc is_ok(result):
    return is_variant(result, "Ok")

proc is_err(result):
    return is_variant(result, "Err")

proc unwrap(result):
    if is_ok(result):
        return result["data"]
    raise "unwrap called on Err: " + str(result["data"])

proc unwrap_or(result, default_val):
    if is_ok(result):
        return result["data"]
    return default_val

proc unwrap_err(result):
    if is_err(result):
        return result["data"]
    raise "unwrap_err called on Ok"

proc map_result(result, fn):
    if is_ok(result):
        return ok(fn(result["data"]))
    return result

proc map_err(result, fn):
    if is_err(result):
        return err(fn(result["data"]))
    return result

# ============================================================================
# Option type (Some/None)
# ============================================================================

let Option = enum_def("Option", ["Some", "None"])

proc some(value):
    return variant_data(Option, "Some", value)

proc none():
    return variant(Option, "None")

proc is_some(option):
    return is_variant(option, "Some")

proc is_none(option):
    return is_variant(option, "None")

proc unwrap_option(option):
    if is_some(option):
        return option["data"]
    raise "unwrap called on None"

proc unwrap_option_or(option, default_val):
    if is_some(option):
        return option["data"]
    return default_val

proc map_option(option, fn):
    if is_some(option):
        return some(fn(option["data"]))
    return option

proc filter_option(option, predicate):
    if is_some(option) and predicate(option["data"]):
        return option
    return none()

proc flatten_option(option):
    if is_some(option) and is_some(option["data"]):
        return option["data"]
    return option
