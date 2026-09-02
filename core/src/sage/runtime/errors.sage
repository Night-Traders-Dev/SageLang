// ============================================================================
# Runtime Errors - Error handling and exception model
# ============================================================================
// Use structured errors from pipeline.md:
//   RuntimeError, TypeError, NameError, PropertyError, IndexError,
//   ArgumentError, CapabilityError, ResourceLimitError, HostError
// Avoid using "nil" as a universal error-recovery value
// ============================================================================

// Error codes for categorization
let ERR_RUNTIME  = 0
let ERR_TYPE    = 1
let ERR_NAME    = 2
let ERR_PROPERTY = 3
let ERR_INDEX   = 4
let ERR_ARGUMENT = 5
let ERR_CAPABILITY = 6
let ERR_RESOURCE = 7
let ERR_HOST    = 8

// Create a RuntimeError
proc raise_runtime(msg: String): Value =
    raise RuntimeError(msg)

// Create a TypeError
proc raise_type(msg: String): Value =
    raise TypeError(msg)

// Create a NameError
proc raise_name(msg: String): Value =
    raise NameError(msg)

// Create a PropertyError
proc raise_property(msg: String): Value =
    raise PropertyError(msg)

// Create an IndexError
proc raise_index(msg: String): Value =
    raise IndexError(msg)

// Create an ArgumentError
proc raise_argument(msg: String): Value =
    raise ArgumentError(msg)

// Create a CapabilityError
proc raise_capability(msg: String): Value =
    raise CapabilityError(msg)

// Create a ResourceLimitError
proc raise_resource(msg: String): Value =
    raise ResourceLimitError(msg)

// Create a HostError
proc raise_host(msg: String): Value =
    raise HostError(msg)

// Exception value wrapper
class ExceptionValue {
    let error_type: Int       // ERR_* code
    let message: String       // Human-readable message
    let stack_trace: List<String>  // Captured stack
    let location: SourceLocation   // Where the error occurred
}

// Get the error type from an exception value
proc error_type_from_val(val: Value): Int =
    if val.tag == TAG_FUNCTION and dict_has(val.data.fn_val, "__error_type"):
        return val.data.fn_val["__error_type"] as Int
    return ERR_RUNTIME

// Get the error message from an exception value
proc error_message_from_val(val: Value): String =
    if val.tag == TAG_FUNCTION and dict_has(val.data.fn_val, "__error_message"):
        return val.data.fn_val["__error_message"] as String
    return "Unknown error"

// Format error for diagnostics
proc format_error(val: Value): String =
    let etype = error_type_from_val(val)
    let msg = error_message_from_val(val)
    let loc = get_current_location()
    return "[" + TAG_NAMES[etype] + "] " + msg + " at " + loc.toString()

// Error classification for dispatch
proc is_error_type(val: Value, kind: Int): Bool =
    error_type_from_val(val) == kind

// Common error patterns
// Division by zero
proc error_division_by_zero(): Value = raise_runtime("Division by zero")

// Undefined variable
proc error_undefined_var(name: String): Value = raise_name("Undefined variable '" + name + "'")

// Type mismatch
proc error_type_mismatch(expected: String, got: String): Value =
    raise_type("Type mismatch: expected " + expected + ", got " + got)

// Undefined function
proc error_undefined_fn(name: String): Value = raise_name("Undefined function '" + name + "'")

// Property not found
proc error_property_not_found(obj: String, prop: String): Value =
    raise_property("Property '" + prop + "' not found on " + obj)

// Index out of bounds
proc error_index_out_of_bounds(idx: Int, len: Int): Value =
    raise_index("Index " + idx.ToString() + " out of bounds for length " + len.ToString())

// Argument count mismatch
proc error_arg_count(name: String, expected: Int, got: Int): Value =
    raise_argument("Function '" + name + "' expects " + expected.ToString() + 
                   " arguments, got " + got.ToString())

// Invalid operation on type
proc error_invalid_operation(op: String, val_type: String): Value =
    raise_type("Invalid operation '" + op + "' on type " + val_type)

// Out of gas / resource exhaustion
proc error_out_of_resource(resource: String): Value =
    raise_resource("Resource limit exceeded: " + resource)
