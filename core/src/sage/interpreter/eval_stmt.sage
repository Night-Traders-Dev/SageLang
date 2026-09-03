# ============================================================================
# Interpreter Statement Evaluation
# ============================================================================
# Part of the Reference VM tier
# Evaluates AST statements using the common runtime
# ============================================================================

import ast
import runtime.values as values
import runtime.environment as env
import runtime.control as control
import runtime.errors as errors

# Evaluate a statement
proc eval_stmt(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    match stmt.kind:
        STMT_EXPRESSION:
            eval_expr(ctx, stmt.expr)
            return control.result_normal(values.nil)
        STMT_LET:
            return eval_let(ctx, stmt)
        STMT_IF:
            return eval_if(ctx, stmt)
        STMT_WHILE:
            return eval_while(ctx, stmt)
        STMT_FOR:
            return eval_for(ctx, stmt)
        STMT_BLOCK:
            return eval_block(ctx, stmt)
        STMT_RETURN:
            return eval_return(ctx, stmt)
        STMT_BREAK:
            return control.result_break()
        STMT_CONTINUE:
            return control.result_continue()
        STMT_TRY:
            return eval_try(ctx, stmt)
        STMT_RAISE:
            return eval_raise(ctx, stmt)
        STMT_YIELD:
            return eval_yield(ctx, stmt)
        STMT_IMPORT:
            return eval_import(ctx, stmt)
        STMT_DEFER:
            return eval_defer(ctx, stmt)
        STMT_MATCH:
            return eval_match(ctx, stmt)
        STMT_CLASS:
            return eval_class(ctx, stmt)
        STMT_STRUCT:
            return eval_struct(ctx, stmt)
        STMT_ENUM:
            return eval_enum(ctx, stmt)
        STMT_TRAIT:
            return eval_trait(ctx, stmt)
        STMT_COMPTIME:
            return eval_comptime_stmt(ctx, stmt)
        STMT_MACRO_DEF:
            return eval_macro_def(ctx, stmt)
        _:
            return control.result_normal(values.nil)

# Evaluate let statement
proc eval_let(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let value = eval_expr(ctx, stmt.init_expr)
    // Bind in current scope
    if stmt.resolved_binding != None:
        let binding = stmt.resolved_binding
        if binding.kind == BINDING_LOCAL:
            slot_store(ctx.current_frame, binding.slot_index, value)
        else if binding.kind == BINDING_CLOSURE:
            env_set_closure(ctx.closure_env, stmt.name, value)
        else if binding.kind == BINDING_GLOBAL:
            env_set(ctx.global_env, stmt.name, value)
        else if binding.kind == BINDING_MODULE:
            module_set_export(ctx.module_state, stmt.name, value)
    else:
        env_define(ctx.current_env, stmt.name, value)
    return control.result_normal(values.nil)

# Evaluate if statement
proc eval_if(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let condition = eval_expr(ctx, stmt.condition)
    if values.is_truthy(condition):
        return eval_block(ctx, stmt.then_block)
    else if stmt.else_block != None:
        return eval_block(ctx, stmt.else_block)
    return control.result_normal(values.nil)

# Evaluate while loop
proc eval_while(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let loop_frame = frames.get_current_frame()
    let iteration = 0
    while true:
        // Check gas/iteration limits
        if iteration > ctx.max_loop_iterations:
            raise errors.error_out_of_resource("loop iterations")
        
        let condition = eval_expr(ctx, stmt.condition)
        if not values.is_truthy(condition):
            break
        
        let result = eval_block(ctx, stmt.body)
        if result.kind == control.CF_BREAK:
            break
        if result.kind == control.CF_CONTINUE:
            continue
        if result.kind == control.CF_RETURN:
            return result
        
        iteration = iteration + 1
    
    return control.result_normal(values.nil)

# Evaluate for loop
proc eval_for(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let iterable = eval_expr(ctx, stmt.iterable)
    let iterator = runtime_iterate(ctx, iterable)
    
    while true:
        let next_result = runtime_call(ctx, iterator.next, [], None)
        if not values.is_truthy(next_result):
            break
        
        // Bind loop variable
        let value = next_result
        if stmt.resolved_binding != None:
            slot_store(ctx.current_frame, stmt.resolved_binding.slot_index, value)
        else:
            env_define(ctx.current_env, stmt.var_name, value)
        
        let result = eval_block(ctx, stmt.body)
        if result.kind == control.CF_BREAK:
            break
        if result.kind == control.CF_CONTINUE:
            continue
        if result.kind == control.CF_RETURN:
            return result
    
    return control.result_normal(values.nil)

# Evaluate block
proc eval_block(ctx: InterpreterContext, block: AST_Stmt): ControlResult =
    // Enter new scope
    let prev_env = ctx.current_env
    ctx.current_env = env.env_create(prev_env)
    let prev_frame = ctx.current_frame
    // Create new frame for block if needed
    
    let i = 0
    while i < len(block.statements):
        let result = eval_stmt(ctx, block.statements[i])
        // Handle control flow
        if result.kind != control.CF_NORMAL:
            // Restore environment
            ctx.current_env = prev_env
            ctx.current_frame = prev_frame
            return result
        i = i + 1
    
    // Restore environment
    ctx.current_env = prev_env
    ctx.current_frame = prev_frame
    return control.result_normal(values.nil)

# Evaluate return
proc eval_return(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let value = if stmt.value != None then eval_expr(ctx, stmt.value) else values.nil
    return ControlResult(
        kind: control.CF_RETURN,
        value: value,
        target: None
    )

# Evaluate try/catch/finally
proc eval_try(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Push try handler
    let try_frame = ctx.current_frame
    let catch_handler = stmt.catch_block
    let finally_handler = stmt.finally_block
    
    // Execute try block
    let result = eval_block(ctx, stmt.try_block)
    
    // Handle exceptions
    if result.kind == control.CF_THROW:
        if catch_handler != None:
            // Bind exception variable and execute catch block
            let prev_env = ctx.current_env
            ctx.current_env = env.env_create(prev_env)
            env_define(ctx.current_env, stmt.catch_var, result.value)
            result = eval_block(ctx, catch_handler)
            ctx.current_env = prev_env
    
    // Execute finally block if present
    if finally_handler != None:
        let finally_result = eval_block(ctx, finally_handler)
        // Finally doesn't override return/throw unless it also returns/throws
        if finally_result.kind != control.CF_NORMAL:
            return finally_result
    
    return result

# Evaluate raise
proc eval_raise(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let exception = eval_expr(ctx, stmt.exception)
    return ControlResult(
        kind: control.CF_THROW,
        value: exception,
        target: None
    )

# Evaluate yield
proc eval_yield(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let value = if stmt.value != None then eval_expr(ctx, stmt.value) else values.nil
    return control.generator_yield(ctx.current_frame, value)

# Evaluate import
proc eval_import(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let module = runtime_import(ctx, stmt.module_name)
    import_bind(stmt, stmt.module_name, module.env, ctx.current_env)
    return control.result_normal(values.nil)

# Evaluate defer
proc eval_defer(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Register defer handler
    let handler_id = "defer_" + ctx.current_frame.ip.ToString()
    frames.push_defer(ctx.current_frame, handler_id, ctx.current_frame.locals)
    return control.result_normal(values.nil)

# Evaluate match
proc eval_match(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    let subject = eval_expr(ctx, stmt.subject)
    for case in stmt.cases:
        if pattern_match(subject, case.pattern):
            // Bind pattern variables and execute body
            return eval_block(ctx, case.body)
    return control.result_normal(values.nil)

# Evaluate class definition
proc eval_class(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Create class object
    let class_obj = objects.Class(
        class_id: make_class_id(stmt.name),
        name: stmt.name,
        super_class: stmt.super_class,
        methods: {},
        fields: [],
        field_slots: {} as Dict<String, Int>
    )
    // Evaluate class body (methods, fields)
    env_define(ctx.current_env, stmt.name, class_obj)
    return control.result_normal(values.nil)

# Evaluate struct definition
proc eval_struct(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Similar to class but no methods
    // ...

# Evaluate enum definition
proc eval_enum(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // ...

# Evaluate trait definition
proc eval_trait(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // ...

# Evaluate comptime block
proc eval_comptime_stmt(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Execute at compile time
    // ...

# Evaluate macro definition
proc eval_macro_def(ctx: InterpreterContext, stmt: AST_Stmt): ControlResult =
    // Register macro
    // ...
