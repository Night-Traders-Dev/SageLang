// ============================================================================
# Runtime Environments - Environment management for scope resolution
# ============================================================================
// Supports local bindings, closure captures, global bindings, module bindings
// Allows the production pipeline to avoid repeated string-based environment lookup
// ============================================================================

// Environment node for scope chain
class EnvNode {
    let name: String
    let value: Value
    let parent: Option<EnvNode>
}

// Environment structure
class Env {
    let nodes: Dict<String, EnvNode>
    let parent: Option<Env>
    let is_global: Bool
}

// Global environment (top-level)
let g_global_env: Env = Env({
    nodes: {} as Dict<String, EnvNode>,
    parent: None,
    is_global: true
})

// Create a new child environment
proc env_create(parent: Env): Env = Env({
    nodes: {} as Dict<String, EnvNode>,
    parent: Some(parent),
    is_global: false
})

// Define a binding in the current environment
proc env_define(env: Env, name: String, value: Value): Env =
    env.nodes[name] = EnvNode(name, value, env.parent)

// Lookup a binding (searches parent chain)
proc env_lookup(env: Env, name: String): Option<Value> =
    if dict_has(env.nodes, name):
        return env.nodes[name].value
    if env.parent != None:
        return env_lookup(env.parent, name)
    return None

// Set a binding (mutates existing or creates new)
proc env_set(env: Env, name: String, value: Value): Env =
    if dict_has(env.nodes, name):
        env.nodes[name].value = value
        return env
    if env.parent != None:
        return env_set(env.parent, name, value)
    env_define(env, name, value)

// Check if a binding exists
proc env_has(env: Env, name: String): Bool =
    dict_has(env.nodes, name) or (env.parent != None and env_has(env.parent, name))

// Get all bindings from an environment
proc env_get_all(env: Env): Dict<String, Value> =
    let result = {} as Dict<String, Value>
    let keys = env.nodes.keys
    let k = 0
    while k < len(keys):
        result[keys[k]] = env.nodes[keys[k]].value
        k = k + 1
    if env.parent != None:
        let parent_bindings = env_get_all(env.parent)
        let pi = 0
        while pi < len(parent_bindings):
            if not dict_has(result, pi):
                result[keys[pi]] = parent_bindings[pi]
            pi = pi + 1
    return result

// Environment stack for closures and nested scopes
class EnvStack {
    let frames: List<Env>
    let max_depth: Int
    
    proc init(max_depth: Int): EnvStack = EnvStack(frames: [], max_depth: max_depth)
    
    proc push(env: Env): Bool =
        if frames.len >= max_depth:
            return false
        frames = frames.push(env)
        return true
    
    proc pop(): Option<Env> =
        if frames.is_empty():
            return None
        let env = frames.last
        frames = frames.pop()
        return Some(env)
    
    proc peek(): Option<Env> =
        if frames.is_empty():
            return None
        return Some(frames.last)
}

// Default global environment accessor
proc get_global_env(): Env = g_global_env

// Module environment wrapper
class ModuleEnv {
    let env: Env
    let module_id: ModuleId
    let exports: Dict<String, Value>
    
    proc init(module_id: ModuleId, base_env: Env): ModuleEnv = ModuleEnv(
        env: env_create(base_env),
        module_id: module_id,
        exports: {} as Dict<String, Value>
    )
    
    proc export(name: String, value: Value): ModuleEnv =
        exports[name] = value
        env_define(env, name, value)
        return self
    
    proc get_export(name: String): Option<Value> =
        if dict_has(exports, name):
            return exports[name]
        return env_lookup(env, name)
}
