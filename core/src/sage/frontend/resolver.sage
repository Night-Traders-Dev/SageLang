# ============================================================================
# Frontend Resolver - Semantic analysis
# ============================================================================
# Semantic analysis should additionally compute:
#   local bindings, closure captures, global bindings, module bindings,
#   function IDs, method ownership, parameter maps, control-flow regions,
#   exception/defer regions, capability requirements
# ============================================================================

import ast

# Resolver state
class Resolver {
    let ast: AST_Module
    let errors: List<Diagnostic>
    let scopes: List<Scope>
    let function_map: Dict<String, FunctionId>
    let module_bindings: Dict<String, ModuleId>
    let capability_reqs: List<Capability>
    let current_function: Option<FunctionId>
}

# Scope for binding resolution
class Scope {
    let bindings: Dict<String, Binding>
    let parent: Option<Scope>
    let is_function: Bool
    let is_closure: Bool
    let captured: Dict<String, Bool>  // Variables captured by closures
}

# Binding information
class Binding {
    let name: String
    let kind: BindingKind      // LOCAL, CLOSURE, GLOBAL, MODULE
    let scope_depth: Int       // Lexical depth
    let slot_index: Option<Int> // Assigned slot index (if resolved)
    let is_mutable: Bool       // Whether the binding can be mutated
    let is_initialized: Bool   // Whether the binding has been initialized
}

let BINDING_LOCAL = 0
let BINDING_CLOSURE = 1
let BINDING_GLOBAL = 2
let BINDING_MODULE = 3

# Create a new resolver
proc resolver_new(ast: AST_Module): Resolver = Resolver(
    ast: ast,
    errors: [],
    scopes: [],
    function_map: {} as Dict<String, FunctionId>,
    module_bindings: {} as Dict<String, ModuleId>,
    capability_reqs: [],
    current_function: None
)

# Run semantic analysis
proc resolver_run(resolver: Resolver): ResolvedModule =
    // Enter global scope
    resolver_enter_scope(resolver, is_function: false)
    
    // Resolve all statements
    let i = 0
    while i < len(resolver.ast.statements):
        resolver_resolve_statement(resolver, resolver.ast.statements[i])
        i = i + 1
    
    // Exit global scope
    resolver_exit_scope(resolver)
    
    return ResolvedModule(
        ast: resolver.ast,
        function_map: resolver.function_map,
        module_bindings: resolver.module_bindings,
        capability_reqs: resolver.capability_reqs,
        diagnostics: resolver.errors
    )

# Enter a new scope
proc resolver_enter_scope(resolver: Resolver, is_function: Bool): Unit =
    let parent = if resolver.scopes.is_empty() then None else Some(resolver.scopes.last)
    resolver.scopes = resolver.scopes.push(Scope(
        bindings: {} as Dict<String, Binding>,
        parent: parent,
        is_function: is_function,
        is_closure: false,
        captured: {} as Dict<String, Bool>
    ))

# Exit current scope
proc resolver_exit_scope(resolver: Resolver): Unit =
    if resolver.scopes.len > 0:
        resolver.scopes = resolver.scopes.pop()

# Get current scope
proc resolver_current_scope(resolver: Resolver): Scope =
    if resolver.scopes.is_empty():
        error "No active scope"
    return resolver.scopes.last

# Declare a binding in current scope
proc resolver_declare(resolver: Resolver, name: String, kind: Int, mutable: Bool): Binding =
    let scope = resolver_current_scope(resolver)
    let binding = Binding(
        name: name,
        kind: kind,
        scope_depth: resolver.scopes.len - 1,
        slot_index: None,
        is_mutable: mutable,
        is_initialized: false
    )
    scope.bindings[name] = binding
    return binding

# Resolve a binding reference
proc resolver_resolve(resolver: Resolver, name: String): Option<Binding> =
    let i = resolver.scopes.len - 1
    while i >= 0:
        let scope = resolver.scopes[i]
        if dict_has(scope.bindings, name):
            return Some(scope.bindings[name])
        i = i - 1
    return None

# Mark a binding as captured by a closure
proc resolver_mark_captured(resolver: Resolver, name: String): Unit =
    let i = resolver.scopes.len - 1
    while i >= 0:
        let scope = resolver.scopes[i]
        if dict_has(scope.bindings, name):
            scope.captured[name] = true
            // Change binding kind to CLOSURE
            scope.bindings[name].kind = BINDING_CLOSURE
            return
        i = i - 1

# Assign slot indices to bindings (for IR generation)
proc resolver_assign_slots(resolver: Resolver): Unit =
    // Walk scopes and assign slots
    let i = 0
    while i < resolver.scopes.len:
        let scope = resolver.scopes[i]
        let slot = 0
        for name in scope.bindings.keys:
            let binding = scope.bindings[name]
            binding.slot_index = Some(slot)
            slot = slot + 1
        i = i + 1

# Resolve a statement
proc resolver_resolve_statement(resolver: Resolver, stmt: AST_Stmt): Unit =
    match stmt.kind:
        STMT_LET:
            resolver_resolve_let(resolver, stmt)
        STMT_IF:
            resolver_resolve_if(resolver, stmt)
        STMT_WHILE:
            resolver_resolve_while(resolver, stmt)
        STMT_FOR:
            resolver_resolve_for(resolver, stmt)
        STMT_PROC:
            resolver_resolve_proc(resolver, stmt)
        STMT_CLASS:
            resolver_resolve_class(resolver, stmt)
        STMT_IMPORT:
            resolver_resolve_import(resolver, stmt)
        STMT_RETURN:
            resolver_resolve_return(resolver, stmt)
        STMT_TRY:
            resolver_resolve_try(resolver, stmt)
        STMT_DEFER:
            resolver_resolve_defer(resolver, stmt)
        STMT_MATCH:
            resolver_resolve_match(resolver, stmt)
        _:
            // Expression statement or other
            if stmt.expr != None:
                resolver_resolve_expression(resolver, stmt.expr)

# Resolve an expression
proc resolver_resolve_expression(resolver: Resolver, expr: AST_Expr): Unit =
    match expr.kind:
        EXPR_VARIABLE:
            let binding = resolver_resolve(resolver, expr.name)
            if binding == None:
                resolver_error(resolver, "Undefined variable '" + expr.name + "'")
            else:
                binding.is_initialized = true
                expr.resolved_binding = binding
        EXPR_CALL:
            resolver_resolve_expression(resolver, expr.callee)
            for arg in expr.args:
                resolver_resolve_expression(resolver, arg)
        EXPR_BINARY:
            resolver_resolve_expression(resolver, expr.lhs)
            resolver_resolve_expression(resolver, expr.rhs)
        EXPR_GET:
            resolver_resolve_expression(resolver, expr.object)
        EXPR_INDEX:
            resolver_resolve_expression(resolver, expr.object)
            resolver_resolve_expression(resolver, expr.index)
        _:
            // Other expression types
            pass

# Error reporting
proc resolver_error(resolver: Resolver, msg: String): Unit =
    resolver.errors = resolver.errors.push(Diagnostic(
        level: "error",
        message: msg,
        location: SourceLocation(
            file: "<input>",
            line: 0,  // Would need proper location tracking
            column: 0,
            length: 0
        )
    ))

# Resolved module result
class ResolvedModule {
    let ast: AST_Module
    let function_map: Dict<String, FunctionId>
    let module_bindings: Dict<String, ModuleId>
    let capability_reqs: List<Capability>
    let diagnostics: List<Diagnostic>
}
