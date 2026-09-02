// ============================================================================
# Runtime Objects - Object representation and operations
# ============================================================================
// Compact internal representations for:
//   Function, Class, Instance, Generator, Module, Environment
// Keep user dictionaries fully dynamic.
// ============================================================================

// Function representation (from pipeline.md Function Identity section)
// Use stable internal IDs keyed by "function_id", not source name
//
// Function
//   ├── function_id
//   ├── source_name
//   ├── owner_class
//   ├── params
//   ├── defaults
//   ├── body/IR
//   ├── closure
//   └── profile

class Function {
    let function_id: FunctionId      // Stable internal ID
    let source_name: String          // Source file/function name
    let owner_class: Option<Class>   // Owner class, if method
    let params: Array<String>        // Parameter names
    let defaults: Array<Value>       // Default values
    let body: IR_Instr               // Body in IR form
    let closure: Frame               // Capturing closure frame
    let profile: FunctionProfile     // Profile information
}

// FunctionId structure - key for profiles (from pipeline.md line 668)
// Profiles must be keyed by "function_id", not source name
class FunctionId {
    let hash: Int                    // Stable hash of function identity
    let source_name: String          // Source name (secondary key)
    let owner_class: Option<String>  // Owner class, if method
    let param_hash: Int              // Hash of parameter signature
    let default_hash: Int            // Hash of default values
}

// Create a FunctionId from a function
proc make_function_id(
    source_name: String,
    owner_class: Option<String>,
    params: Array<String>,
    defaults: Array<Value>
): FunctionId = FunctionId(
    hash: hash_combine(source_name, owner_class, params, defaults),
    source_name: source_name,
    owner_class: owner_class,
    param_hash: hash_array(params),
    default_hash: hash_array(defaults)
)

// Function profile (keyed by function_id, not source name - pipeline.md line 668)
class FunctionProfile {
    let function_id: FunctionId      // Keyed by function_id
    let call_count: Int              // Number of calls
    let monomorphic: Bool            // Whether argument types are consistent
    let observed_types: Dict<String, Int>  // Type feedback
    let inline_cache: Option[InlineCache]  // IC state, if optimized
    let deopt_reason: Option[String]   // Last deoptimization reason, if any
}

// Inline cache for property/function calls
class InlineCache {
    let function_id: FunctionId      // Cached function
    let last_args: Array<Value>      // Last argument values
    let result: Value                // Last result
    let valid: Bool                  // Whether cache is valid
}

// Instance representation (from Compact Runtime Objects section)
// Instance
//   ├── class reference
//   ├── fields: Dict<String, Value>  // User properties (dynamic)
//   └── slots: Array<Value>          // Compact field storage (if shaped)

// Class representation
class Class {
    let class_id: ClassId            // Stable class identifier
    let name: String                   // Class name
    let super_class: Option<Class>   // Super class, if any
    let methods: Dict<String, Function>  // Method table
    let fields: Array<String>        // Field names (for shaped instances)
    let field_slots: Dict<String, Int>   // Field name -> slot mapping
}

// Instance structure
class Instance {
    let class_obj: Class          // Reference to class
    let slots: Array<Value>       // Compact slot storage
    let dict: Dict<String, Value> // User-defined properties (dynamic)
}

// Create a new instance
proc new_instance(class_obj: Class, initial_fields: Dict<String, Value>): Instance = Instance(
    class_obj: class_obj,
    slots: Array<Value>(class_obj.field_slots.len),  // Initialize with nils
    dict: initial_fields
)

// Get a field from an instance (tries slot first, then dict)
proc instance_get_field(instance: Instance, field_name: String): Value =
    if dict_has(instance.class_obj.field_slots, field_name):
        let slot_idx = instance.class_obj.field_slots[field_name]
        if slot_idx < instance.slots.len:
            return instance.slots[slot_idx]
    if dict_has(instance.dict, field_name):
        return instance.dict[field_name]
    raise PropertyError("Property '" + field_name + "' not found on instance of class " + 
                       instance.class_obj.name)

// Set a field on an instance
proc instance_set_field(instance: Instance, field_name: String, value: Value): Unit =
    if dict_has(instance.class_obj.field_slots, field_name):
        let slot_idx = instance.class_obj.field_slots[field_name]
        if slot_idx < instance.slots.len:
            instance.slots[slot_idx] = value
            return
    if dict_has(instance.dict, field_name) or instance.dict.len < instance.class_obj.dynamic_threshold:
        instance.dict[field_name] = value
        return
    // If dict is full and field not in shape, add to dict
    instance.dict[field_name] = value

// Method lookup on instance
proc instance_call_method(instance: Instance, method_name: String, args: Array<Value>): Value =
    if dict_has(instance.class_obj.methods, method_name):
        let method = instance.class_obj.methods[method_name]
        // Call the method with the instance as first argument (self)
        return call_function(method, args.prepend(instance))
    raise PropertyError("Method '" + method_name + "' not found on class " + 
                       instance.class_obj.name)

// Module representation (from Compact Runtime Objects section)
// Module
//   ├── module ID
//   ├── canonical path
//   ├── source identity
//   ├── dependencies
//   ├── cache entry
//   ├── capability requirements

class Module {
    let module_id: ModuleId         // Unique module identifier
    let canonical_path: String      // Normalized path
    let source_identity: String     // Source identity for caching
    let dependencies: List<Module>   // Module dependencies
    let cache_entry: ModuleCacheEntry  // Cached compilation info
    let capability_reqs: List<Capability>  // Required capabilities
}

// Module cache entry
class ModuleCacheEntry {
    let ast: AST_InModule              // Parsed AST
    let ir: IR_Module                    // Compiled IR
    let bytecode: Bytecode_Artifact     // Bytecode representation
    let compiled: Bool                  // Whether fully compiled
    let load_count: Int                 // Number of times loaded
    let last_loaded: Timestamp         // When last loaded
}

// Create a new module
proc new_module(
    module_id: ModuleId,
    canonical_path: String,
    source_identity: String,
    capability_reqs: List<Capability>
): Module = Module(
    module_id: module_id,
    canonical_path: canonical_path,
    source_identity: source_identity,
    dependencies: [],
    cache_entry: ModuleCacheEntry(
        ast: nil as AST_InModule,
        ir: nil as IR_Module,
        bytecode: nil as Bytecode_Artifact,
        compiled: false,
        load_count: 0,
        last_loaded: now()
    ),
    capability_reqs: capability_reqs
)

// Environment representation (from Compact Runtime Objects section)
// Environment
//   ├── bindings: Dict<String, Value>  // Variable bindings
//   ├── parent: Option<Environment>    // Parent scope chain
//   ├── slot_map: Dict<String, Int>    // Lexical slot mapping

class Environment {
    let bindings: Dict<String, Value>  // Variable bindings
    let parent: Option<Environment>    // Parent scope
    let slot_map: Dict<String, Int>    // Slot mapping for optimization
    let is_closure: Bool               // Whether this is a closure env
}

// Create a new environment
proc new_environment(parent: Option<Environment>): Environment = Environment(
    bindings: {} as Dict<String, Value>,
    parent: parent,
    slot_map: {} as Dict<String, Int>,
    is_closure: false
)

// Add a binding to environment
proc env_add_binding(env: Environment, name: String, value: Value): Environment =
    env.bindings[name] = value
    // Also update slot map if optimized
    if env.is_closure:
        env.slot_map[name] = get_next_slot(env)
    return env

// Lookup a binding in environment (with parent chain)
proc env_lookup_binding(env: Environment, name: String): Option<Value> =
    if dict_has(env.bindings, name):
        return env.bindings[name]
    if env.parent != None:
        return env_lookup_binding(env.parent, name)
    return None

// Host native handles (from Runtime Values section)
// native handles - platform-specific handles for FFI, file descriptors, etc.
class NativeHandle {
    let handle_type: String     // Type of handle (file, socket, etc.)
    let raw_handle: Int         // Platform-specific handle value
    let owner: Option<Module>   // Owning module, if any
    let closed: Bool            // Whether the handle is closed
}
