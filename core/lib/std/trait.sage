gc_disable()
# Trait (interface) system
# Provides behavioral contracts that types can implement

# ============================================================================
# Trait definition
# ============================================================================

# Define a trait with required method names
proc define(name, methods):
    let t = {}
    t["__type"] = "trait"
    t["name"] = name
    t["methods"] = methods
    t["implementations"] = {}
    return t

# Check if an object implements a trait
proc implements(obj, trait_def):
    let methods = trait_def["methods"]
    for i in range(len(methods)):
        let method_name = methods[i]
        if not dict_has(obj, method_name):
            return false
        # Check that the field is callable (function or native)
        # In Sage, we can't easily check callability, so presence is sufficient
    return true

# Register an implementation for a type name
proc implement(trait_def, type_name, impl_dict):
    # Verify all required methods are provided
    let methods = trait_def["methods"]
    for i in range(len(methods)):
        if not dict_has(impl_dict, methods[i]):
            raise "Missing method " + methods[i] + " for trait " + trait_def["name"]
    trait_def["implementations"][type_name] = impl_dict

# Get the implementation for a type
proc get_impl(trait_def, type_name):
    if dict_has(trait_def["implementations"], type_name):
        return trait_def["implementations"][type_name]
    return nil

# Dispatch a trait method call
proc dispatch(trait_def, obj, method_name, args):
    # First check if object has the method directly
    if dict_has(obj, method_name):
        let fn = obj[method_name]
        if len(args) == 0:
            return fn()
        if len(args) == 1:
            return fn(args[0])
        if len(args) == 2:
            return fn(args[0], args[1])
        if len(args) == 3:
            return fn(args[0], args[1], args[2])
        return nil
    # Then check registered implementations
    if dict_has(obj, "__type_name"):
        let impl = get_impl(trait_def, obj["__type_name"])
        if impl != nil and dict_has(impl, method_name):
            let fn = impl[method_name]
            if len(args) == 0:
                return fn(obj)
            if len(args) == 1:
                return fn(obj, args[0])
            if len(args) == 2:
                return fn(obj, args[0], args[1])
            return nil
    return nil

# ============================================================================
# Common built-in traits
# ============================================================================

# Display: anything that can be converted to a string
let Display = define("Display", ["to_string"])

# Eq: equality comparison
let Eq = define("Eq", ["equals"])

# Ord: ordering comparison
let Ord = define("Ord", ["compare"])

# Hash: hash value computation
let Hash = define("Hash", ["hash_code"])

# Clone: deep copy
let Clone = define("Clone", ["clone"])

# Iterator: iteration protocol
let Iterator = define("Iterator", ["has_next", "next_val"])

# Serialize: convert to bytes/string representation
let Serialize = define("Serialize", ["serialize"])

# ============================================================================
# Trait-based utilities
# ============================================================================

# Sort an array using the Ord trait
proc trait_sort(arr, compare_fn):
    # Simple insertion sort using comparison function
    let n = len(arr)
    for i in range(n):
        let j = i
        while j > 0 and compare_fn(arr[j - 1], arr[j]) > 0:
            let temp = arr[j]
            arr[j] = arr[j - 1]
            arr[j - 1] = temp
            j = j - 1
    return arr

# Filter array using predicate
proc trait_filter(arr, predicate):
    let result = []
    for i in range(len(arr)):
        if predicate(arr[i]):
            push(result, arr[i])
    return result

# Map array using transform function
proc trait_map(arr, transform):
    let result = []
    for i in range(len(arr)):
        push(result, transform(arr[i]))
    return result

# Check if all elements satisfy a predicate
proc all(arr, predicate):
    for i in range(len(arr)):
        if not predicate(arr[i]):
            return false
    return true

# Check if any element satisfies a predicate
proc any(arr, predicate):
    for i in range(len(arr)):
        if predicate(arr[i]):
            return true
    return false
