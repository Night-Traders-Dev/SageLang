gc_disable()
# SageLang Constant Folding Pass (self-hosted port)
#
# Evaluates constant expressions at compile time:
# - Number arithmetic: 2 + 3 -> 5
# - String concatenation: "a" + "b" -> "ab"
# - Boolean logic: true and false -> false
# - Constant conditions: if true -> then-branch only
import ast

# Check literal types
proc is_number_literal(e):
    if e == nil:
        return false
    return e.type == ast.EXPR_NUMBER

proc is_string_literal(e):
    if e == nil:
        return false
    return e.type == ast.EXPR_STRING

proc is_bool_literal(e):
    if e == nil:
        return false
    return e.type == ast.EXPR_BOOL

# Fold a binary expression
proc fold_binary(expr):
    expr.left = fold_expr(expr.left)
    expr.right = fold_expr(expr.right)
    let op = expr.op.text
    # Number + Number arithmetic
    if is_number_literal(expr.left) and is_number_literal(expr.right):
        let l = expr.left.value
        let r = expr.right.value
        if op == "+":
            return ast.number_expr(l + r)
        if op == "-":
            return ast.number_expr(l - r)
        if op == "*":
            return ast.number_expr(l * r)
        if op == "/":
            if r == 0:
                return expr
            return ast.number_expr(l / r)
        if op == "%":
            if r == 0:
                return expr
            return ast.number_expr(l % r)
        if op == "<":
            return ast.bool_expr(l < r)
        if op == ">":
            return ast.bool_expr(l > r)
        if op == "==":
            return ast.bool_expr(l == r)
        if op == "!=":
            return ast.bool_expr(l != r)
        if op == "<=":
            return ast.bool_expr(l <= r)
        if op == ">=":
            return ast.bool_expr(l >= r)
        return expr
    # String + String concatenation
    if is_string_literal(expr.left) and is_string_literal(expr.right):
        if op == "+":
            return ast.string_expr(expr.left.value + expr.right.value)
    # Boolean logic
    if is_bool_literal(expr.left) and is_bool_literal(expr.right):
        let l = expr.left.value
        let r = expr.right.value
        if op == "and":
            return ast.bool_expr(l and r)
        if op == "or":
            return ast.bool_expr(l or r)
    return expr

# Fold expressions recursively
proc fold_expr(expr):
    if expr == nil:
        return nil
    let t = expr.type
    if t == ast.EXPR_BINARY:
        return fold_binary(expr)
    if t == ast.EXPR_CALL:
        for i in range(expr.arg_count):
            expr.args[i] = fold_expr(expr.args[i])
        expr.callee = fold_expr(expr.callee)
        return expr
    if t == ast.EXPR_ARRAY:
        for i in range(expr.count):
            expr.elements[i] = fold_expr(expr.elements[i])
        return expr
    if t == ast.EXPR_INDEX:
        expr.object = fold_expr(expr.object)
        expr.index = fold_expr(expr.index)
        return expr
    if t == ast.EXPR_INDEX_SET:
        expr.object = fold_expr(expr.object)
        expr.index = fold_expr(expr.index)
        expr.value = fold_expr(expr.value)
        return expr
    if t == ast.EXPR_DICT:
        for i in range(expr.count):
            expr.values[i] = fold_expr(expr.values[i])
        return expr
    if t == ast.EXPR_TUPLE:
        for i in range(expr.count):
            expr.elements[i] = fold_expr(expr.elements[i])
        return expr
    if t == ast.EXPR_SLICE:
        expr.object = fold_expr(expr.object)
        expr.start = fold_expr(expr.start)
        expr.end = fold_expr(expr.end)
        return expr
    if t == ast.EXPR_GET:
        expr.object = fold_expr(expr.object)
        return expr
    if t == ast.EXPR_SET:
        expr.object = fold_expr(expr.object)
        expr.value = fold_expr(expr.value)
        return expr
    return expr

# Fold statements recursively
proc fold_stmt(stmt):
    if stmt == nil:
        return
    let t = stmt.type
    if t == ast.STMT_PRINT:
        stmt.expression = fold_expr(stmt.expression)
        return
    if t == ast.STMT_EXPRESSION:
        stmt.expression = fold_expr(stmt.expression)
        return
    if t == ast.STMT_LET:
        stmt.initializer = fold_expr(stmt.initializer)
        return
    if t == ast.STMT_IF:
        stmt.condition = fold_expr(stmt.condition)
        fold_stmt_list(stmt.then_branch)
        fold_stmt_list(stmt.else_branch)
        # Constant condition optimization
        let cond = stmt.condition
        if cond != nil and cond.type == ast.EXPR_BOOL:
            if cond.value:
                # Replace if with then-branch
                stmt.type = ast.STMT_BLOCK
                stmt.statements = stmt.then_branch
            else:
                # Replace if with else-branch or nil expr
                if stmt.else_branch != nil:
                    stmt.type = ast.STMT_BLOCK
                    stmt.statements = stmt.else_branch
                else:
                    stmt.type = ast.STMT_EXPRESSION
                    stmt.expression = ast.nil_expr()
        return
    if t == ast.STMT_BLOCK:
        fold_stmt_list(stmt.statements)
        return
    if t == ast.STMT_WHILE:
        stmt.condition = fold_expr(stmt.condition)
        fold_stmt_list(stmt.body)
        # Eliminate while-false loops
        if stmt.condition != nil and stmt.condition.type == ast.EXPR_BOOL:
            if not stmt.condition.value:
                stmt.type = ast.STMT_EXPRESSION
                stmt.expression = ast.nil_expr()
        return
    if t == ast.STMT_PROC:
        fold_stmt_list(stmt.body)
        return
    if t == ast.STMT_FOR:
        stmt.iterable = fold_expr(stmt.iterable)
        fold_stmt_list(stmt.body)
        return
    if t == ast.STMT_RETURN:
        stmt.value = fold_expr(stmt.value)
        return
    if t == ast.STMT_CLASS:
        fold_stmt_list(stmt.methods)
        return
    if t == ast.STMT_TRY:
        fold_stmt_list(stmt.try_block)
        for i in range(stmt.catch_count):
            fold_stmt_list(stmt.catches[i].body)
        fold_stmt_list(stmt.finally_block)
        return
    if t == ast.STMT_RAISE:
        stmt.exception = fold_expr(stmt.exception)
        return
    if t == ast.STMT_YIELD:
        stmt.value = fold_expr(stmt.value)
        return

proc fold_stmt_list(head):
    let s = head
    while s != nil:
        fold_stmt(s)
        s = s.next

# Pass entry point
proc pass_constfold(program, ctx):
    fold_stmt_list(program)
    return program
