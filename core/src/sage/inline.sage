gc_disable()
# SageLang Function Inlining Pass (self-hosted port)
#
# Replaces calls to small, non-recursive procedures with their body.
# Only runs at -O3.
#
# Criteria for inlining:
# - Procedure body is a single return statement
# - Not recursive
# - Called with correct argument count
import ast
import pass

# Check if a proc body is a single return statement, return the return expr or nil
proc get_single_return_expr(body):
    if body == nil:
        return nil
    let first = body
    if first.type == ast.STMT_BLOCK:
        first = first.statements
    if first == nil:
        return nil
    if first.next != nil:
        return nil
    if first.type != ast.STMT_RETURN:
        return nil
    return first.value

# Check if an expression references a name
proc expr_references_name(expr, name):
    if expr == nil:
        return false
    let t = expr.type
    if t == ast.EXPR_VARIABLE:
        return expr.name.text == name
    if t == ast.EXPR_BINARY:
        if expr_references_name(expr.left, name):
            return true
        return expr_references_name(expr.right, name)
    if t == ast.EXPR_CALL:
        if expr_references_name(expr.callee, name):
            return true
        for i in range(expr.arg_count):
            if expr_references_name(expr.args[i], name):
                return true
        return false
    if t == ast.EXPR_ARRAY:
        for i in range(expr.count):
            if expr_references_name(expr.elements[i], name):
                return true
        return false
    if t == ast.EXPR_INDEX:
        if expr_references_name(expr.object, name):
            return true
        return expr_references_name(expr.index, name)
    if t == ast.EXPR_INDEX_SET:
        if expr_references_name(expr.object, name):
            return true
        if expr_references_name(expr.index, name):
            return true
        return expr_references_name(expr.value, name)
    if t == ast.EXPR_DICT:
        for i in range(expr.count):
            if expr_references_name(expr.values[i], name):
                return true
        return false
    if t == ast.EXPR_TUPLE:
        for i in range(expr.count):
            if expr_references_name(expr.elements[i], name):
                return true
        return false
    if t == ast.EXPR_SLICE:
        if expr_references_name(expr.object, name):
            return true
        if expr_references_name(expr.start, name):
            return true
        return expr_references_name(expr.end, name)
    if t == ast.EXPR_GET:
        return expr_references_name(expr.object, name)
    if t == ast.EXPR_SET:
        if expr_references_name(expr.object, name):
            return true
        return expr_references_name(expr.value, name)
    return false

# Collect inline candidates from proc definitions
# Returns a list of dicts: {name, param_count, params, return_expr}
proc collect_candidates(program):
    let candidates = []
    let s = program
    while s != nil:
        if s.type == ast.STMT_PROC:
            let ret_expr = get_single_return_expr(s.body)
            if ret_expr != nil:
                let name = s.name.text
                # Skip recursive procs
                if not expr_references_name(ret_expr, name):
                    let c = {}
                    c["name"] = name
                    c["param_count"] = s.param_count
                    c["params"] = s.params
                    c["return_expr"] = ret_expr
                    push(candidates, c)
        s = s.next
    return candidates

# Find a candidate by name
proc find_candidate(candidates, name):
    for i in range(len(candidates)):
        if candidates[i]["name"] == name:
            return candidates[i]
    return nil

# Substitute parameter references with argument expressions
proc substitute_expr(expr, params, param_count, args):
    if expr == nil:
        return nil
    # Clone the expression first
    let result = pass.clone_expr(expr)
    if result.type == ast.EXPR_VARIABLE:
        let vname = result.name.text
        for i in range(param_count):
            if params[i].text == vname:
                return pass.clone_expr(args[i])
        return result
    if result.type == ast.EXPR_BINARY:
        result.left = substitute_expr(expr.left, params, param_count, args)
        result.right = substitute_expr(expr.right, params, param_count, args)
        return result
    if result.type == ast.EXPR_CALL:
        result.callee = substitute_expr(expr.callee, params, param_count, args)
        for i in range(result.arg_count):
            result.args[i] = substitute_expr(expr.args[i], params, param_count, args)
        return result
    if result.type == ast.EXPR_INDEX:
        result.object = substitute_expr(expr.object, params, param_count, args)
        result.index = substitute_expr(expr.index, params, param_count, args)
        return result
    if result.type == ast.EXPR_INDEX_SET:
        result.object = substitute_expr(expr.object, params, param_count, args)
        result.index = substitute_expr(expr.index, params, param_count, args)
        result.value = substitute_expr(expr.value, params, param_count, args)
        return result
    if result.type == ast.EXPR_ARRAY:
        for i in range(result.count):
            result.elements[i] = substitute_expr(expr.elements[i], params, param_count, args)
        return result
    if result.type == ast.EXPR_DICT:
        for i in range(result.count):
            result.values[i] = substitute_expr(expr.values[i], params, param_count, args)
        return result
    if result.type == ast.EXPR_TUPLE:
        for i in range(result.count):
            result.elements[i] = substitute_expr(expr.elements[i], params, param_count, args)
        return result
    if result.type == ast.EXPR_SLICE:
        result.object = substitute_expr(expr.object, params, param_count, args)
        result.start = substitute_expr(expr.start, params, param_count, args)
        result.end = substitute_expr(expr.end, params, param_count, args)
        return result
    if result.type == ast.EXPR_GET:
        result.object = substitute_expr(expr.object, params, param_count, args)
        return result
    if result.type == ast.EXPR_SET:
        result.object = substitute_expr(expr.object, params, param_count, args)
        result.value = substitute_expr(expr.value, params, param_count, args)
        return result
    return result

# Inline call expressions
proc inline_expr(expr, candidates):
    if expr == nil:
        return nil
    let t = expr.type
    if t == ast.EXPR_CALL:
        # First inline args and callee
        expr.callee = inline_expr(expr.callee, candidates)
        for i in range(expr.arg_count):
            expr.args[i] = inline_expr(expr.args[i], candidates)
        # Check if callee is a variable matching a candidate
        if expr.callee.type == ast.EXPR_VARIABLE:
            let name = expr.callee.name.text
            let c = find_candidate(candidates, name)
            if c != nil and expr.arg_count == c["param_count"]:
                # Perform inlining
                return substitute_expr(c["return_expr"], c["params"], c["param_count"], expr.args)
        return expr
    if t == ast.EXPR_BINARY:
        expr.left = inline_expr(expr.left, candidates)
        expr.right = inline_expr(expr.right, candidates)
        return expr
    if t == ast.EXPR_ARRAY:
        for i in range(expr.count):
            expr.elements[i] = inline_expr(expr.elements[i], candidates)
        return expr
    if t == ast.EXPR_INDEX:
        expr.object = inline_expr(expr.object, candidates)
        expr.index = inline_expr(expr.index, candidates)
        return expr
    if t == ast.EXPR_INDEX_SET:
        expr.object = inline_expr(expr.object, candidates)
        expr.index = inline_expr(expr.index, candidates)
        expr.value = inline_expr(expr.value, candidates)
        return expr
    if t == ast.EXPR_DICT:
        for i in range(expr.count):
            expr.values[i] = inline_expr(expr.values[i], candidates)
        return expr
    if t == ast.EXPR_TUPLE:
        for i in range(expr.count):
            expr.elements[i] = inline_expr(expr.elements[i], candidates)
        return expr
    if t == ast.EXPR_SLICE:
        expr.object = inline_expr(expr.object, candidates)
        expr.start = inline_expr(expr.start, candidates)
        expr.end = inline_expr(expr.end, candidates)
        return expr
    if t == ast.EXPR_GET:
        expr.object = inline_expr(expr.object, candidates)
        return expr
    if t == ast.EXPR_SET:
        expr.object = inline_expr(expr.object, candidates)
        expr.value = inline_expr(expr.value, candidates)
        return expr
    return expr

# Inline statements
proc inline_stmt(stmt, candidates):
    if stmt == nil:
        return
    let t = stmt.type
    if t == ast.STMT_PRINT:
        stmt.expression = inline_expr(stmt.expression, candidates)
        return
    if t == ast.STMT_EXPRESSION:
        stmt.expression = inline_expr(stmt.expression, candidates)
        return
    if t == ast.STMT_LET:
        stmt.initializer = inline_expr(stmt.initializer, candidates)
        return
    if t == ast.STMT_IF:
        stmt.condition = inline_expr(stmt.condition, candidates)
        inline_stmt_list(stmt.then_branch, candidates)
        inline_stmt_list(stmt.else_branch, candidates)
        return
    if t == ast.STMT_BLOCK:
        inline_stmt_list(stmt.statements, candidates)
        return
    if t == ast.STMT_WHILE:
        stmt.condition = inline_expr(stmt.condition, candidates)
        inline_stmt_list(stmt.body, candidates)
        return
    if t == ast.STMT_PROC:
        inline_stmt_list(stmt.body, candidates)
        return
    if t == ast.STMT_FOR:
        stmt.iterable = inline_expr(stmt.iterable, candidates)
        inline_stmt_list(stmt.body, candidates)
        return
    if t == ast.STMT_RETURN:
        stmt.value = inline_expr(stmt.value, candidates)
        return
    if t == ast.STMT_CLASS:
        inline_stmt_list(stmt.methods, candidates)
        return
    if t == ast.STMT_TRY:
        inline_stmt_list(stmt.try_block, candidates)
        for i in range(stmt.catch_count):
            inline_stmt_list(stmt.catches[i].body, candidates)
        inline_stmt_list(stmt.finally_block, candidates)
        return
    if t == ast.STMT_RAISE:
        stmt.exception = inline_expr(stmt.exception, candidates)
        return
    if t == ast.STMT_YIELD:
        stmt.value = inline_expr(stmt.value, candidates)
        return

proc inline_stmt_list(head, candidates):
    let s = head
    while s != nil:
        inline_stmt(s, candidates)
        s = s.next

# Pass entry point
proc pass_inline(program, ctx):
    let candidates = collect_candidates(program)
    if len(candidates) == 0:
        return program
    inline_stmt_list(program, candidates)
    return program
