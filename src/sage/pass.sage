gc_disable()
# SageLang Optimization Pass Infrastructure (self-hosted port)
#
# Provides:
#   - Deep cloning of AST nodes (clone_expr, clone_stmt, clone_stmt_list)
#   - Pass registration and runner (run_passes)
import token
import ast

# Clone a Token
proc clone_token(tok):
    if tok == nil:
        return nil
    return token.Token(tok.type, tok.text, tok.line)

# Deep clone an expression
proc clone_expr(expr):
    if expr == nil:
        return nil
    let t = expr.type
    if t == ast.EXPR_NUMBER:
        return ast.number_expr(expr.value)
    if t == ast.EXPR_STRING:
        return ast.string_expr(expr.value)
    if t == ast.EXPR_BOOL:
        return ast.bool_expr(expr.value)
    if t == ast.EXPR_NIL:
        return ast.nil_expr()
    if t == ast.EXPR_BINARY:
        return ast.binary_expr(clone_expr(expr.left), clone_token(expr.op), clone_expr(expr.right))
    if t == ast.EXPR_VARIABLE:
        return ast.variable_expr(clone_token(expr.name))
    if t == ast.EXPR_CALL:
        let new_args = []
        for i in range(expr.arg_count):
            push(new_args, clone_expr(expr.args[i]))
        return ast.call_expr(clone_expr(expr.callee), new_args)
    if t == ast.EXPR_ARRAY:
        let new_elems = []
        for i in range(expr.count):
            push(new_elems, clone_expr(expr.elements[i]))
        return ast.array_expr(new_elems)
    if t == ast.EXPR_INDEX:
        return ast.index_expr(clone_expr(expr.object), clone_expr(expr.index))
    if t == ast.EXPR_INDEX_SET:
        return ast.index_set_expr(clone_expr(expr.object), clone_expr(expr.index), clone_expr(expr.value))
    if t == ast.EXPR_DICT:
        let new_keys = []
        let new_vals = []
        for i in range(expr.count):
            push(new_keys, expr.keys[i])
            push(new_vals, clone_expr(expr.values[i]))
        return ast.dict_expr(new_keys, new_vals)
    if t == ast.EXPR_TUPLE:
        let new_elems = []
        for i in range(expr.count):
            push(new_elems, clone_expr(expr.elements[i]))
        return ast.tuple_expr(new_elems)
    if t == ast.EXPR_SLICE:
        return ast.slice_expr(clone_expr(expr.object), clone_expr(expr.start), clone_expr(expr.end))
    if t == ast.EXPR_GET:
        return ast.get_expr(clone_expr(expr.object), expr.property)
    if t == ast.EXPR_SET:
        return ast.set_expr(clone_expr(expr.object), expr.property, clone_expr(expr.value))
    if t == ast.EXPR_AWAIT:
        return ast.await_expr(clone_expr(expr.expression))
    # Unknown expression type - return nil
    return nil

# Deep clone a statement
proc clone_stmt(stmt):
    if stmt == nil:
        return nil
    let t = stmt.type
    if t == ast.STMT_PRINT:
        return ast.print_stmt(clone_expr(stmt.expression))
    if t == ast.STMT_EXPRESSION:
        return ast.expr_stmt(clone_expr(stmt.expression))
    if t == ast.STMT_LET:
        return ast.let_stmt(clone_token(stmt.name), clone_expr(stmt.initializer))
    if t == ast.STMT_IF:
        return ast.if_stmt(clone_expr(stmt.condition), clone_stmt_list(stmt.then_branch), clone_stmt_list(stmt.else_branch))
    if t == ast.STMT_BLOCK:
        return ast.block_stmt(clone_stmt_list(stmt.statements))
    if t == ast.STMT_WHILE:
        return ast.while_stmt(clone_expr(stmt.condition), clone_stmt_list(stmt.body))
    if t == ast.STMT_PROC:
        let new_params = []
        for i in range(stmt.param_count):
            push(new_params, clone_token(stmt.params[i]))
        return ast.proc_stmt(clone_token(stmt.name), new_params, clone_stmt_list(stmt.body))
    if t == ast.STMT_FOR:
        return ast.for_stmt(clone_token(stmt.variable), clone_expr(stmt.iterable), clone_stmt_list(stmt.body))
    if t == ast.STMT_RETURN:
        return ast.return_stmt(clone_expr(stmt.value))
    if t == ast.STMT_BREAK:
        return ast.break_stmt()
    if t == ast.STMT_CONTINUE:
        return ast.continue_stmt()
    if t == ast.STMT_CLASS:
        return ast.class_stmt(clone_token(stmt.name), clone_token(stmt.parent), stmt.has_parent, clone_stmt_list(stmt.methods))
    if t == ast.STMT_TRY:
        let new_catches = []
        for i in range(stmt.catch_count):
            let c = stmt.catches[i]
            push(new_catches, ast.CatchClause(c.exception_var, clone_stmt_list(c.body)))
        return ast.try_stmt(clone_stmt_list(stmt.try_block), new_catches, clone_stmt_list(stmt.finally_block))
    if t == ast.STMT_RAISE:
        return ast.raise_stmt(clone_expr(stmt.exception))
    if t == ast.STMT_YIELD:
        return ast.yield_stmt(clone_expr(stmt.value))
    if t == ast.STMT_IMPORT:
        let new_items = []
        let new_aliases = []
        for i in range(stmt.item_count):
            push(new_items, stmt.items[i])
            push(new_aliases, stmt.item_aliases[i])
        return ast.import_stmt(stmt.module_name, new_items, new_aliases, stmt.alias, stmt.import_all)
    if t == ast.STMT_ASYNC_PROC:
        let new_params = []
        for i in range(stmt.param_count):
            push(new_params, clone_token(stmt.params[i]))
        return ast.async_proc_stmt(clone_token(stmt.name), new_params, clone_stmt_list(stmt.body))
    if t == ast.STMT_DEFER:
        return ast.defer_stmt(clone_stmt_list(stmt.statement))
    # Unknown - return nil
    return nil

# Clone a linked list of statements
proc clone_stmt_list(head):
    if head == nil:
        return nil
    let new_head = nil
    let new_tail = nil
    let cur = head
    while cur != nil:
        let cloned = clone_stmt(cur)
        if new_head == nil:
            new_head = cloned
        else:
            new_tail.next = cloned
        new_tail = cloned
        cur = cur.next
    return new_head

# Run optimization passes on a program AST
# ctx is a dict with keys: "opt_level", "verbose", "debug_info"
proc run_passes(program, ctx):
    let opt_level = ctx["opt_level"]
    let verbose = false
    if dict_has(ctx, "verbose"):
        verbose = ctx["verbose"]
    if opt_level <= 0:
        return program
    # Import passes lazily to avoid circular deps
    import constfold
    import dce
    import inline
    # -O1+: constant folding
    if opt_level >= 1:
        if verbose:
            print "[pass] running constfold"
        program = constfold.pass_constfold(program, ctx)
    # -O2+: dead code elimination
    if opt_level >= 2:
        if verbose:
            print "[pass] running dce"
        program = dce.pass_dce(program, ctx)
    # -O3: function inlining
    if opt_level >= 3:
        if verbose:
            print "[pass] running inline"
        program = inline.pass_inline(program, ctx)
    return program
