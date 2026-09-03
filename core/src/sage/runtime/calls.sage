# ============================================================================
# Runtime Calls - Function call and argument binding management
# ============================================================================
# Keyword argument maps - precompute param lookup:
#   param_lookup = {
#       "foo": 0,
#       "bar": 1,
#       "baz": 2
#   }
# Preserve all argument errors and default behavior.
# ============================================================================

# Keyword argument parameter map
class KwParamMap {
    let param_lookup: Dict<String, Int>  // Parameter name -> index mapping
    let required_count: Int              // Number of required parameters
    let optional_count: Int              // Number of optional parameters
    let variadic: Bool                   // Whether function accepts varargs
}

# Create a keyword argument map
proc make_kw_param_map(
    param_names: Array<String>,
    defaults: Array<Value>,
    variadic: Bool
): KwParamMap =
    let param_lookup = {} as Dict<String, Int>
    let i = 0
    while i < len(param_names):
        param_lookup[param_names[i]] = i
        i = i + 1
    KwParamMap(
        param_lookup: param_lookup,
        required_count: len(param_names) - (if variadic then 0 else len(defaults)),
        optional_count: len(defaults),
        variadic: variadic
    )

# Lookup parameter index by name
proc kw_param_lookup(map: KwParamMap, name: String): Option<Int> =
    if dict_has(map.param_lookup, name):
        return Some(map.param_lookup[name])
    return None

# Bind arguments to parameters
proc bind_arguments(
    map: KwParamMap,
    provided: Array<Value>,
    defaults: Array<Value>
): Array<Value> =
    let bound = Array<Value>(map.required_count + map.optional_count)
    let i = 0
    while i < map.required_count:
        if i < len(provided):
            bound[i] = provided[i]
        else:
            // Use default value
            if i - map.required_count < len(defaults):
                bound[i] = defaults[i - map.required_count]
            else:
                bound[i] = nil  // No default, use nil
        i = i + 1
    
    // Handle optional arguments
    let opt_idx = map.required_count
    while opt_idx < len(bound) and opt_idx < len(provided):
        bound[opt_idx] = provided[opt_idx]
        opt_idx = opt_idx + 1
    
    // Fill remaining with defaults or nil
    while opt_idx < len(bound):
        if opt_idx - map.required_count < len(defaults):
            bound[opt_idx] = defaults[opt_idx - map.required_count]
        else:
            bound[opt_idx] = nil
        opt_idx = opt_idx + 1
    
    return bound

# Call metadata structure (from pipeline.md IR section)
# call metadata
class CallMetadata {
    let function_id: FunctionId         // Identifying the called function
    let arg_count: Int                  // Number of arguments provided
    let named_args: Bool                // Whether named/keyword args were used
    let kw_map: Option<KwParamMap>      // Keyword argument map, if applicable
    let source_location: SourceLocation // Where the call site is
    let profile_id: Option[FunctionId]  // Profile ID for optimization
}

# Build call metadata from a call site
proc build_call_metadata(
    func_id: FunctionId,
    arg_count: Int,
    named_args: Bool,
    kw_map: Option<KwParamMap>,
    source_loc: SourceLocation
): CallMetadata = CallMetadata(
    function_id: func_id,
    arg_count: arg_count,
    named_args: named_args,
    kw_map: kw_map,
    source_location: source_loc
)

# Canonical call operation (from pipeline.md Semantic Authority section)
# All execution tiers must use the same definitions for calls
# runtime_call() defines the language semantics for function calls

# Call dispatch - same conceptual model across all tiers
# Reference VM, Bytecode VM, JIT/AOT all use the same call semantics

# Tail call optimization hint
proc is_tail_call(stmt: Stmt): Bool =
    // Check if the call is in tail position
    // ... implementation depends on AST structure

# Argument validation (called before privileged operations - pipeline.md line 767-769)
proc validate_arguments(
    map: KwParamMap,
    provided: Array<Value>
): Option[String] =
    // Check argument count
    if len(provided) < map.required_count:
        return "Not enough arguments: expected at least " + 
               map.required_count.ToString() + ", got " + len(provided).ToString()
    
    // Check types if profile indicates monomorphic
    // ... type checking logic
    
    return None  // Validation passed

# Function call execution (core runtime operation)
# This is the canonical call semantics that all tiers must respect
proc execute_call(
    callee: Value,
    args: Array<Value>,
    kw_map: Option<KwParamMap>,
    ctx: InterpreterContext
): Value =
    // Dispatch based on callee type
    match callee.tag:
        TAG_FUNCTION:
            return execute_function_call(callee.data.fn_val, args, kw_map, ctx)
        TAG_GENERATOR:
            return execute_generator_call(callee.data.gen_val, args, kw_map, ctx)
        TAG_NATIVE_HANDLE:
            return execute_native_handle_call(callee.data.handle_val, args, kw_map, ctx)
    raise TypeError("Cannot call value of type " + TAG_NAMES[callee.tag])
