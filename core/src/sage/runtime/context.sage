# ============================================================================
# InterpreterContext - Central runtime context
# ============================================================================
# InterpreterContext owns all mutable state for an interpreter instance.
# Enables: multiple interpreters, thread isolation, embedding, sandboxing,
# deterministic execution, independent tests.
# ============================================================================

import runtime.values as values
import runtime.environment as env
import runtime.frames as frames
import runtime.control as control
import runtime.errors as errors
import runtime.objects as objects
import runtime.calls as calls
import runtime.modules as modules
import runtime.capabilities as capabilities
import frontend.resolver as resolver
import frontend.diagnostics as diagnostics

# InterpreterContext structure (from pipeline.md lines 219-229):
# InterpreterContext
#   ├── global_env
#   ├── module_cache
#   ├── module_paths
#   ├── error_context
#   ├── profiler
#   ├── resource_limits
#   ├── host_capabilities
#   ├── runtime_profile
#   ├── runtime_flags
#   └── allocator/state

class InterpreterContext {
    // Environments
    let global_env: Env                      // Global scope environment
    let current_env: Env                     // Current lexical environment
    let module_env: Option<ModuleEnv>        // Current module environment
    
    // Module state
    let module_state: ModuleState            // Module loading state
    let module_paths: List<String>           // Search paths for modules
    
    // Frame stack
    let frame_stack: FrameStack              // Call frame stack
    let current_frame: Option<CallFrame>     // Currently executing frame
    
    // Error handling
    let error_context: ErrorContext          // Rich error context
    let pending_exception: Option<Value>     // Exception being unwound
    
    // Profiling & optimization
    let profiler: ProfilerState              // Profiling data
    let function_profiles: Dict<FunctionId, FunctionProfile>  // Function profiles
    
    // Resource limits
    let resource_limits: ResourceLimits      // Configurable limits
    let steps_used: Int                      // Step counter
    let recursion_depth: Int                 // Current recursion depth
    let memory_used: Int                     // Memory usage tracker
    let output_bytes: Int                    // Output bytes written
    
    // Capabilities
    let host_capabilities: HostCapabilities  // Granted capabilities
    let runtime_profile: String              // Profile name (general/embedded/deterministic)
    
    // Runtime flags
    let runtime_flags: RuntimeFlags          // Feature flags
    let runtime_tier: String                 // Execution tier (reference/bytecode/cpc/jit/aot)
    
    // Builtins and native registry
    let builtin_registry: Dict<String, NativeFunction>  // Registered builtins
    
    // Source tracking
    let source_map: Dict<String, String>     // Module -> source mapping
    let current_source: Option<String>       // Currently executing source
    
    // Initialization state
    let initialized: Bool                    // Whether context is fully initialized
}

# Runtime flags for feature toggles
class RuntimeFlags {
    let enable_profiling: Bool
    let enable_jit: Bool
    let enable_verification: Bool
    let enable_parity_check: Bool
    let enable_debug: Bool
    let strict_mode: Bool
    let trace_execution: Bool
    let dump_ir: Bool
    let dump_bytecode: Bool
    let dump_frames: Bool
}

# Native function registration
class NativeFunction {
    let name: String
    let arity: Int
    let handler: NativeHandler
    let capabilities: List<Capability>
}

# Error context for rich diagnostics
class ErrorContext {
    let source: String
    let filename: String
    let line_map: Dict<Int, Int>  // Byte offset -> line number
}

# Profiler state
class ProfilerState {
    let enabled: Bool
    let call_counts: Dict<FunctionId, Int>
    let type_feedback: Dict<FunctionId, Dict<String, Int>>
    let shape_feedback: Dict<FunctionId, Dict<String, Int>>
    let loop_counts: Dict<Int, Int>
    let branch_behavior: Dict<Int, Dict<String, Int>>
}

# Create a new InterpreterContext with the given profile
proc context_new(profile: String): InterpreterContext =
    let caps = capabilities.make_capabilities(profile)
    let limits = capabilities.make_resource_limits(profile)
    
    let ctx = InterpreterContext(
        global_env: env.new_environment(None),
        current_env: env.new_environment(None),  // Will be set to global
        module_env: None,
        module_state: modules.ModuleState(
            module_cache: {} as Dict<ModuleId, Module>,
            module_paths: [".", "lib", "core/src/sage", "core/lib", 
                          "/usr/local/share/sage/lib", "/usr/local/share/sage/src/sage"],
            loading_stack: [],
            capability_checks: true
        ),
        module_paths: [".", "lib", "core/src/sage", "core/lib", 
                      "/usr/local/share/sage/lib", "/usr/local/share/sage/src/sage"],
        frame_stack: frames.FrameStack(max_depth: limits.max_recursion_depth),
        current_frame: None,
        error_context: ErrorContext(
            source: "",
            filename: "<input>",
            line_map: {} as Dict<Int, Int>
        ),
        pending_exception: None,
        profiler: ProfilerState(
            enabled: false,
            call_counts: {} as Dict<FunctionId, Int>,
            type_feedback: {} as Dict<FunctionId, Dict<String, Int>>,
            shape_feedback: {} as Dict<FunctionId, Dict<String, Int>>,
            loop_counts: {} as Dict<Int, Int>,
            branch_behavior: {} as Dict<Int, Dict<String, Int>>
        ),
        function_profiles: {} as Dict<FunctionId, FunctionProfile>,
        resource_limits: limits,
        steps_used: 0,
        recursion_depth: 0,
        memory_used: 0,
        output_bytes: 0,
        host_capabilities: HostCapabilities(
            allowed: caps,
            profile: profile
        ),
        runtime_profile: profile,
        runtime_flags: RuntimeFlags(
            enable_profiling: true,
            enable_jit: profile == "general",
            enable_verification: true,
            enable_parity_check: false,
            enable_debug: false,
            strict_mode: false,
            trace_execution: false,
            dump_ir: false,
            dump_bytecode: false,
            dump_frames: false
        ),
        runtime_tier: "reference",
        builtin_registry: {} as Dict<String, NativeFunction>,
        source_map: {} as Dict<String, String>,
        current_source: None,
        initialized: false
    )
    
    // Initialize global environment with builtins
    ctx.current_env = ctx.global_env
    calls.init_builtins(ctx)
    ctx.initialized = true
    
    return ctx

# Initialize builtins in the context
proc init_builtins(ctx: InterpreterContext): Unit =
    let env = ctx.global_env
    // Core builtins
    env_define(env, "print", values.value_native("print", 1, native_print))
    env_define(env, "str", values.value_native("str", 1, native_str))
    env_define(env, "len", values.value_native("len", 1, native_len))
    env_define(env, "tonumber", values.value_native("tonumber", 1, native_tonumber))
    env_define(env, "input", values.value_native("input", 0, native_input))
    env_define(env, "clock", values.value_native("clock", 0, native_clock))
    env_define(env, "type", values.value_native("type", 1, native_type))
    // ... more builtins
    
    // Register in context registry
    ctx.builtin_registry["print"] = NativeFunction("print", 1, native_print, [])
    // ...

# Builtin implementations (delegating to host)
proc native_print(args: Array<Value>): Value =
    let s = values.value_to_string(args[0])
    print s
    return values.nil

proc native_str(args: Array<Value>): Value =
    return values.value_string(values.value_to_string(args[0]))

proc native_len(args: Array<Value>): Value =
    let x = args[0]
    // ... len implementation

proc native_tonumber(args: Array<Value>): Value =
    // ... tonumber implementation

proc native_input(args: Array<Value>): Value =
    // ... input implementation

proc native_clock(args: Array<Value>): Value =
    // Check capability
    if not capabilities.capability_check(ctx.host_capabilities, capabilities.CAP_CLOCK):
        raise capabilities.CapabilityError("clock capability required")
    return values.value_number(clock())

proc native_type(args: Array<Value>): Value =
    return values.value_string(values.value_type(args[0]))

# Context accessors
proc context_get_global_env(ctx: InterpreterContext): Env = ctx.global_env
proc context_get_current_env(ctx: InterpreterContext): Env = ctx.current_env
proc context_set_current_env(ctx: InterpreterContext, env: Env): Unit = ctx.current_env = env
proc context_get_frame_stack(ctx: InterpreterContext): FrameStack = ctx.frame_stack
proc context_get_current_frame(ctx: InterpreterContext): Option<CallFrame> = ctx.current_frame
proc context_set_current_frame(ctx: InterpreterContext, frame: CallFrame): Unit = ctx.current_frame = Some(frame)
proc context_get_module_state(ctx: InterpreterContext): ModuleState = ctx.module_state
proc context_get_resource_limits(ctx: InterpreterContext): ResourceLimits = ctx.resource_limits
proc context_get_host_capabilities(ctx: InterpreterContext): HostCapabilities = ctx.host_capabilities
proc context_get_runtime_profile(ctx: InterpreterContext): String = ctx.runtime_profile
proc context_get_runtime_tier(ctx: InterpreterContext): String = ctx.runtime_tier
proc context_set_runtime_tier(ctx: InterpreterContext, tier: String): Unit = ctx.runtime_tier = tier
proc context_get_profiler(ctx: InterpreterContext): ProfilerState = ctx.profiler
proc context_get_function_profiles(ctx: InterpreterContext): Dict<FunctionId, FunctionProfile> = ctx.function_profiles

# Resource tracking
proc context_increment_steps(ctx: InterpreterContext): Bool =
    ctx.steps_used = ctx.steps_used + 1
    if ctx.resource_limits.max_steps != -1 and ctx.steps_used > ctx.resource_limits.max_steps:
        return false  // Limit exceeded
    return true

proc context_increment_recursion(ctx: InterpreterContext): Bool =
    ctx.recursion_depth = ctx.recursion_depth + 1
    if ctx.recursion_depth > ctx.resource_limits.max_recursion_depth:
        return false  // Limit exceeded
    return true

proc context_decrement_recursion(ctx: InterpreterContext): Unit =
    ctx.recursion_depth = ctx.recursion_depth - 1

proc context_check_resource(ctx: InterpreterContext, resource: String): Bool =
    capabilities.resource_check(ctx.resource_limits, resource)

# Capability checking
proc context_check_capability(ctx: InterpreterContext, cap: Capability): Bool =
    capabilities.capability_check(ctx.host_capabilities, cap)

proc context_require_capability(ctx: InterpreterContext, cap: Capability): Unit =
    if not capabilities.capability_check(ctx.host_capabilities, cap):
        raise capabilities.CapabilityError("Required capability not granted: " + cap.name)

# Frame management helpers
proc context_push_frame(ctx: InterpreterContext, frame: CallFrame): Bool =
    let result = frames.push_frame(frame)
    if result:
        ctx.current_frame = Some(frame)
    return result

proc context_pop_frame(ctx: InterpreterContext): Option<CallFrame> =
    let frame = frames.pop_frame()
    if frames.peek() != None:
        ctx.current_frame = frames.peek()
    else:
        ctx.current_frame = None
    return frame

# Error context management
proc context_set_source(ctx: InterpreterContext, source: String, filename: String): Unit =
    ctx.error_context.source = source
    ctx.error_context.filename = filename
    ctx.error_context.line_map = build_line_map(source)
    ctx.current_source = Some(source)

proc context_get_error_context(ctx: InterpreterContext): ErrorContext = ctx.error_context

# Build line map from source
proc build_line_map(source: String): Dict<Int, Int> =
    let map = {} as Dict<Int, Int>
    let line = 1
    let i = 0
    while i < len(source):
        map[i] = line
        if source[i] == '\n':
            line = line + 1
        i = i + 1
    return map

# Get line number from byte offset
proc context_get_line(ctx: InterpreterContext, offset: Int): Int =
    let map = ctx.error_context.line_map
    if dict_has(map, offset):
        return map[offset]
    // Find closest line start
    let keys = map.keys.sort()
    let i = len(keys) - 1
    while i >= 0:
        if keys[i] <= offset:
            return map[keys[i]]
        i = i - 1
    return 1

# Profile management
proc context_get_profile(ctx: InterpreterContext, func_id: FunctionId): Option<FunctionProfile> =
    if dict_has(ctx.function_profiles, func_id):
        return Some(ctx.function_profiles[func_id])
    return None

proc context_update_profile(ctx: InterpreterContext, func_id: FunctionId, profile: FunctionProfile): Unit =
    ctx.function_profiles[func_id] = profile

# Flag management
proc context_get_flag(ctx: InterpreterContext, flag: String): Bool =
    match flag:
        "profiling": return ctx.runtime_flags.enable_profiling
        "jit": return ctx.runtime_flags.enable_jit
        "verification": return ctx.runtime_flags.enable_verification
        "parity": return ctx.runtime_flags.enable_parity_check
        "debug": return ctx.runtime_flags.enable_debug
        "strict": return ctx.runtime_flags.strict_mode
        "trace": return ctx.runtime_flags.trace_execution
        "dump_ir": return ctx.runtime_flags.dump_ir
        "dump_bytecode": return ctx.runtime_flags.dump_bytecode
        "dump_frames": return ctx.runtime_flags.dump_frames
    return false

proc context_set_flag(ctx: InterpreterContext, flag: String, value: Bool): Unit =
    match flag:
        "profiling": ctx.runtime_flags.enable_profiling = value
        "jit": ctx.runtime_flags.enable_jit = value
        "verification": ctx.runtime_flags.enable_verification = value
        "parity": ctx.runtime_flags.enable_parity_check = value
        "debug": ctx.runtime_flags.enable_debug = value
        "strict": ctx.runtime_flags.strict_mode = value
        "trace": ctx.runtime_flags.trace_execution = value
        "dump_ir": ctx.runtime_flags.dump_ir = value
        "dump_bytecode": ctx.runtime_flags.dump_bytecode = value
        "dump_frames": ctx.runtime_flags.dump_frames = value

# Create a child context (for embedding/sandboxing)
proc context_spawn_child(parent: InterpreterContext, profile: String): InterpreterContext =
    let child = context_new(profile)
    // Inherit module cache from parent
    child.module_state.module_cache = parent.module_state.module_cache
    child.module_paths = parent.module_paths
    return child

# Destroy context (cleanup)
proc context_destroy(ctx: InterpreterContext): Unit =
    // Cleanup resources
    // ...
    ctx.initialized = false

# ============================================================================
# Canonical Runtime Operations (from pipeline.md Semantic Authority section)
# All execution tiers must use these definitions
# ============================================================================

# Property access
proc runtime_get_property(ctx: InterpreterContext, obj: Value, name: String): Value =
    // Canonical property get semantics
    match obj.tag:
        values.TAG_DICT:
            if dict_has(obj.data.dict_val, name):
                return obj.data.dict_val[name]
            raise errors.PropertyError("Property '" + name + "' not found")
        values.TAG_INSTANCE:
            return objects.instance_get_field(obj.data.instance_val, name)
        values.TAG_MODULE:
            return modules.module_get_export(obj.data.module_val, name)
        _:
            raise errors.TypeError("Cannot get property on type " + values.TAG_NAMES[obj.tag])

# Property assignment
proc runtime_set_property(ctx: InterpreterContext, obj: Value, name: String, value: Value): Value =
    match obj.tag:
        values.TAG_DICT:
            obj.data.dict_val[name] = value
            return value
        values.TAG_INSTANCE:
            objects.instance_set_field(obj.data.instance_val, name, value)
            return value
        _:
            raise errors.TypeError("Cannot set property on type " + values.TAG_NAMES[obj.tag])

# Index access
proc runtime_index(ctx: InterpreterContext, obj: Value, index: Value): Value =
    match obj.tag:
        values.TAG_ARRAY:
            let idx = index.data.num_val.toInt()
            if idx < 0 or idx >= obj.data.arr_val.len:
                raise errors.IndexError("Index out of bounds")
            return obj.data.arr_val[idx]
        values.TAG_STRING:
            let idx = index.data.num_val.toInt()
            if idx < 0 or idx >= len(obj.data.str_val):
                raise errors.IndexError("Index out of bounds")
            return values.value_string(obj.data.str_val[idx].toString())
        values.TAG_DICT:
            let key = values.value_to_string(index)
            if dict_has(obj.data.dict_val, key):
                return obj.data.dict_val[key]
            raise errors.IndexError("Key not found")
        _:
            raise errors.TypeError("Cannot index type " + values.TAG_NAMES[obj.tag])

# Index assignment
proc runtime_set_index(ctx: InterpreterContext, obj: Value, index: Value, value: Value): Value =
    match obj.tag:
        values.TAG_ARRAY:
            let idx = index.data.num_val.toInt()
            if idx < 0 or idx >= obj.data.arr_val.len:
                raise errors.IndexError("Index out of bounds")
            obj.data.arr_val[idx] = value
            return value
        values.TAG_DICT:
            let key = values.value_to_string(index)
            obj.data.dict_val[key] = value
            return value
        _:
            raise errors.TypeError("Cannot set index on type " + values.TAG_NAMES[obj.tag])

# Slice operation
proc runtime_slice(ctx: InterpreterContext, obj: Value, start: Value, end: Value, step: Value): Value =
    // ... slice implementation
    raise errors.NotImplementedError("slice")

# Truthiness
proc runtime_truthy(ctx: InterpreterContext, val: Value): Bool =
    values.is_truthy(val)

# Binary operations
proc runtime_binary(ctx: InterpreterContext, op: String, lhs: Value, rhs: Value): Value =
    // Canonical binary operation semantics
    // Delegate to values module
    return values.value_binary(op, lhs, rhs)

# Unary operations
proc runtime_unary(ctx: InterpreterContext, op: String, operand: Value): Value =
    // Canonical unary operation semantics
    return values.value_unary(op, operand)

# Function call
proc runtime_call(ctx: InterpreterContext, callee: Value, args: Array<Value>, kw_map: Option<KwParamMap>): Value =
    calls.execute_call(callee, args, kw_map, ctx)

# Argument binding
proc runtime_bind_arguments(ctx: InterpreterContext, map: KwParamMap, provided: Array<Value>, defaults: Array<Value>): Array<Value> =
    calls.bind_arguments(map, provided, defaults)

# Exception raise
proc runtime_raise(ctx: InterpreterContext, exception: Value): Value =
    ctx.pending_exception = Some(exception)
    // Control flow will handle unwinding
    return exception

# Import
proc runtime_import(ctx: InterpreterContext, module_name: String): Module =
    modules.load_module(ctx, module_name)

# Iteration
proc runtime_iterate(ctx: InterpreterContext, iterable: Value): Iterator =
    // Create iterator based on type
    match iterable.tag:
        values.TAG_ARRAY:
            return values.make_array_iterator(iterable)
        values.TAG_STRING:
            return values.make_string_iterator(iterable)
        values.TAG_DICT:
            return values.make_dict_iterator(iterable)
        _:
            raise errors.TypeError("Cannot iterate type " + values.TAG_NAMES[iterable.tag])

# Comparison
proc runtime_compare(ctx: InterpreterContext, op: String, lhs: Value, rhs: Value): Value =
    // Canonical comparison semantics
    return values.value_compare(op, lhs, rhs)