// ============================================================================
# Interpreter Expression Evaluation
# ============================================================================
// Part of the Reference VM tier
// Evaluates AST expressions using the common runtime
// ============================================================================

import ast
import runtime.values as values
import runtime.environment as env
import runtime.calls as calls
import runtime.objects as objects
import runtime.control as control
import runtime.errors as errors

// Evaluate an expression
proc eval_expr(ctx: InterpreterContext, expr: AST_Expr): Value =
    match expr.kind:
        EXPR_NUMBER:
            return values.value_number(expr.value)
        EXPR_STRING:
            return values.value_string(expr.value)
        EXPR_BOOL:
            return if expr.value then values.true_val else values.false_val
        EXPR_NIL:
            return values.nil
        EXPR_VARIABLE:
            return eval_variable(ctx, expr)
        EXPR_BINARY:
            return eval_binary(ctx, expr)
        EXPR_UNARY:
            return eval_unary(ctx, expr)
        EXPR_CALL:
            return eval_call(ctx, expr)
        EXPR_GET:
            return eval_get(ctx, expr)
        EXPR_SET:
            return eval_set(ctx, expr)
        EXPR_INDEX:
            return eval_index(ctx, expr)
        EXPR_INDEX_SET:
            return eval_index_set(ctx, expr)
        EXPR_ARRAY:
            return eval_array(ctx, expr)
        EXPR_DICT:
            return eval_dict(ctx, expr)
        EXPR_TUPLE:
            return eval_tuple(ctx, expr)
        EXPR_SLICE:
            return eval_slice(ctx, expr)
        EXPR_AWAIT:
            return eval_await(ctx, expr)
        EXPR_PROC:
            return eval_proc(ctx, expr)
        EXPR_SUPER:
            return eval_super(ctx, expr)
        EXPR_COMPTIME:
            return eval_comptime(ctx, expr)
        _:
            raise errors.error_invalid_operation("eval", "unknown expression type")

// Evaluate variable reference
proc eval_variable(ctx: InterpreterContext, expr: AST_Expr): Value =
    if expr.resolved_binding != None:
        let binding = expr.resolved_binding
        if binding.kind == BINDING_LOCAL:
            return slot_load(ctx.current_frame, binding.slot_index)
        else if binding.kind == BINDING_CLOSURE:
            return env_lookup_closure(ctx.closure_env, expr.name)
        else if binding.kind == BINDING_GLOBAL:
            return env_lookup(ctx.global_env, expr.name)
        else if binding.kind == BINDING_MODULE:
            return module_get_export(ctx.module_state, expr.name)
    // Fallback: lookup in environment chain
    return env_lookup(ctx.current_env, expr.name)

// Evaluate binary operation
proc eval_binary(ctx: InterpreterContext, expr: AST_Expr): Value =
    let lhs = eval_expr(ctx, expr.lhs)
    let rhs = eval_expr(ctx, expr.rhs)
    
    // Use canonical runtime operation
    return runtime_binary(ctx, expr.op, lhs, rhs)

// Evaluate unary operation
proc eval_unary(ctx: InterpreterContext, expr: AST_Expr): Value =
    let operand = eval_expr(ctx, expr.operand)
    return runtime_unary(ctx, expr.op, operand)

// Evaluate function call
proc eval_call(ctx: InterpreterContext, expr: AST_Expr): Value =
    let callee = eval_expr(ctx, expr.callee)
    let args = []
    for arg in expr.args:
        args = args.push(eval_expr(ctx, arg))
    
    // Build keyword argument map if needed
    let kw_map = None
    if expr.kwargs.len > 0:
        // Build KwParamMap from function signature
        // ...
    
    // Use canonical call operation
    return runtime_call(ctx, callee, args, kw_map)

// Evaluate property access
proc eval_get(ctx: InterpreterContext, expr: AST_Expr): Value =
    let obj = eval_expr(ctx, expr.object)
    return runtime_get_property(ctx, obj, expr.property_name)

// Evaluate property assignment
proc eval_set(ctx: InterpreterContext, expr: AST_Expr): Value =
    let obj = eval_expr(ctx, expr.object)
    let value = eval_expr(ctx, expr.value)
    return runtime_set_property(ctx, obj, expr.property_name, value)

// Evaluate index access
proc eval_index(ctx: InterpreterContext, expr: AST_Expr): Value =
    let obj = eval_expr(ctx, expr.object)
    let index = eval_expr(ctx, expr.index)
    return runtime_index(ctx, obj, index)

// Evaluate index assignment
proc eval_index_set(ctx: InterpreterContext, expr: AST_Expr): Value =
    let obj = eval_expr(ctx, expr.object)
    let index = eval_expr(ctx, expr.index)
    let value = eval_expr(ctx, expr.value)
    return runtime_set_index(ctx, obj, index, value)

// Evaluate array literal
proc eval_array(ctx: InterpreterContext, expr: AST_Expr): Value =
    let elements = []
    for elem in expr.elements:
        elements = elements.push(eval_expr(ctx, elem))
    return values.value_array(elements)

// Evaluate dictionary literal
proc eval_dict(ctx: InterpreterContext, expr: AST_Expr): Value =
    let entries = {} as Dict<String, Value>
    for pair in expr.entries:
        let key = eval_expr(ctx, pair.key)
        let value = eval_expr(ctx, pair.value)
        entries[key] = value
    return values.value_dict(entries)

// Evaluate tuple literal
proc eval_tuple(ctx: InterpreterContext, expr: AST_Expr): Value =
    let elements = []
    for elem in expr.elements:
        elements = elements.push(eval_expr(ctx, elem))
    return values.value_tuple(elements)

// Evaluate slice
proc eval_slice(ctx: InterpreterContext, expr: AST_Expr): Value =
    let obj = eval_expr(ctx, expr.object)
    let start = eval_expr(ctx, expr.start)
    let end = eval_expr(ctx, expr.end)
    let step = eval_expr(ctx, expr.step)
    return runtime_slice(ctx, obj, start, end, step)

// Evaluate await
proc eval_await(ctx: InterpreterContext, expr: AST_Expr): Value =
    let awaitable = eval_expr(ctx, expr.operand)
    // Handle await semantics
    return awaitable  // Simplified

// Evaluate proc literal
proc eval_proc(ctx: InterpreterContext, expr: AST_Expr): Value =
    // Create function value with closure
    let fn_id = make_function_id(
        expr.source_name,
        None,
        expr.params,
        expr.defaults
    )
    let closure = ctx.current_env
    return values.value_function(fn_id, expr.body, expr.params, 
                                expr.defaults, closure, 
                                FunctionProfile(fn_id))

// Evaluate super
proc eval_super(ctx: InterpreterContext, expr: AST_Expr): Value =
    // Look up super class method
    // ...

// Evaluate comptime
proc eval_comptime(ctx: InterpreterContext, expr: AST_Expr): Value =
    // Evaluate at compile time
    // ...
