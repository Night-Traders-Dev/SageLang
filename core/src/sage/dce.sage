gc_disable()
# SageLang Dead Code Elimination Pass (self-hosted port)
#
# Removes:
# 1. Unreachable code after return/break/continue
# 2. Unused let bindings (variable assigned but never read)
# 3. Unused proc definitions (never called)
import ast

# Name set - tracks used variable/proc names (as a dict for O(1) lookup)
proc nameset_new():
    return {}

proc nameset_add(ns, name):
    ns[name] = true

proc nameset_has(ns, name):
    return dict_has(ns, name)

# Collect all referenced names from expressions
proc collect_used_names_expr(used, expr):
    if expr == nil:
        return
    let t = expr.type
    if t == ast.EXPR_VARIABLE:
        nameset_add(used, expr.name.text)
        return
    if t == ast.EXPR_BINARY:
        collect_used_names_expr(used, expr.left)
        collect_used_names_expr(used, expr.right)
        return
    if t == ast.EXPR_CALL:
        collect_used_names_expr(used, expr.callee)
        for i in range(expr.arg_count):
            collect_used_names_expr(used, expr.args[i])
        return
    if t == ast.EXPR_ARRAY:
        for i in range(expr.count):
            collect_used_names_expr(used, expr.elements[i])
        return
    if t == ast.EXPR_INDEX:
        collect_used_names_expr(used, expr.object)
        collect_used_names_expr(used, expr.index)
        return
    if t == ast.EXPR_INDEX_SET:
        collect_used_names_expr(used, expr.object)
        collect_used_names_expr(used, expr.index)
        collect_used_names_expr(used, expr.value)
        return
    if t == ast.EXPR_DICT:
        for i in range(expr.count):
            collect_used_names_expr(used, expr.values[i])
        return
    if t == ast.EXPR_TUPLE:
        for i in range(expr.count):
            collect_used_names_expr(used, expr.elements[i])
        return
    if t == ast.EXPR_SLICE:
        collect_used_names_expr(used, expr.object)
        collect_used_names_expr(used, expr.start)
        collect_used_names_expr(used, expr.end)
        return
    if t == ast.EXPR_GET:
        collect_used_names_expr(used, expr.object)
        return
    if t == ast.EXPR_SET:
        collect_used_names_expr(used, expr.object)
        collect_used_names_expr(used, expr.value)
        return

# Collect used names from statements
proc collect_used_names_stmt(used, stmt):
    if stmt == nil:
        return
    let t = stmt.type
    if t == ast.STMT_PRINT:
        collect_used_names_expr(used, stmt.expression)
        return
    if t == ast.STMT_EXPRESSION:
        collect_used_names_expr(used, stmt.expression)
        return
    if t == ast.STMT_LET:
        collect_used_names_expr(used, stmt.initializer)
        return
    if t == ast.STMT_IF:
        collect_used_names_expr(used, stmt.condition)
        collect_used_names_list(used, stmt.then_branch)
        collect_used_names_list(used, stmt.else_branch)
        return
    if t == ast.STMT_BLOCK:
        collect_used_names_list(used, stmt.statements)
        return
    if t == ast.STMT_WHILE:
        collect_used_names_expr(used, stmt.condition)
        collect_used_names_list(used, stmt.body)
        return
    if t == ast.STMT_PROC:
        collect_used_names_list(used, stmt.body)
        return
    if t == ast.STMT_FOR:
        collect_used_names_expr(used, stmt.iterable)
        collect_used_names_list(used, stmt.body)
        return
    if t == ast.STMT_RETURN:
        collect_used_names_expr(used, stmt.value)
        return
    if t == ast.STMT_CLASS:
        collect_used_names_list(used, stmt.methods)
        return
    if t == ast.STMT_TRY:
        collect_used_names_list(used, stmt.try_block)
        for i in range(stmt.catch_count):
            collect_used_names_list(used, stmt.catches[i].body)
        collect_used_names_list(used, stmt.finally_block)
        return
    if t == ast.STMT_RAISE:
        collect_used_names_expr(used, stmt.exception)
        return
    if t == ast.STMT_YIELD:
        collect_used_names_expr(used, stmt.value)
        return
    if t == ast.STMT_DEFER:
        collect_used_names_stmt(used, stmt.statement)
        return

proc collect_used_names_list(used, head):
    let s = head
    while s != nil:
        collect_used_names_stmt(used, s)
        s = s.next

# Check if an expression has side effects
proc has_side_effects(expr):
    if expr == nil:
        return false
    let t = expr.type
    if t == ast.EXPR_CALL:
        return true
    if t == ast.EXPR_SET:
        return true
    if t == ast.EXPR_AWAIT:
        return true
    if t == ast.EXPR_INDEX_SET:
        return true
    if t == ast.EXPR_BINARY:
        return has_side_effects(expr.left) or has_side_effects(expr.right)
    if t == ast.EXPR_INDEX:
        return has_side_effects(expr.object) or has_side_effects(expr.index)
    if t == ast.EXPR_ARRAY:
        for i in range(expr.count):
            if has_side_effects(expr.elements[i]):
                return true
        return false
    return false

# Check if a statement is a terminator (return/break/continue)
proc is_terminator(s):
    if s.type == ast.STMT_RETURN:
        return true
    if s.type == ast.STMT_BREAK:
        return true
    if s.type == ast.STMT_CONTINUE:
        return true
    return false

# Remove unreachable code after return/break/continue
proc remove_unreachable(head):
    if head == nil:
        return nil
    let s = head
    while s != nil:
        if is_terminator(s) and s.next != nil:
            s.next = nil
            break
        s = s.next
    return head

# Recursively apply DCE to sub-bodies of a statement
proc dce_stmt_body(stmt, used):
    if stmt == nil:
        return
    let t = stmt.type
    if t == ast.STMT_IF:
        stmt.then_branch = dce_stmt_list(stmt.then_branch, used)
        stmt.else_branch = dce_stmt_list(stmt.else_branch, used)
        return
    if t == ast.STMT_BLOCK:
        stmt.statements = dce_stmt_list(stmt.statements, used)
        return
    if t == ast.STMT_WHILE:
        stmt.body = dce_stmt_list(stmt.body, used)
        return
    if t == ast.STMT_PROC:
        stmt.body = dce_stmt_list(stmt.body, used)
        return
    if t == ast.STMT_FOR:
        stmt.body = dce_stmt_list(stmt.body, used)
        return
    if t == ast.STMT_CLASS:
        stmt.methods = dce_stmt_list(stmt.methods, used)
        return
    if t == ast.STMT_TRY:
        stmt.try_block = dce_stmt_list(stmt.try_block, used)
        for i in range(stmt.catch_count):
            stmt.catches[i].body = dce_stmt_list(stmt.catches[i].body, used)
        stmt.finally_block = dce_stmt_list(stmt.finally_block, used)
        return

# Remove unused lets and procs from a statement list
proc dce_stmt_list(head, used):
    head = remove_unreachable(head)
    let new_head = nil
    let new_tail = nil
    let cur = head
    while cur != nil:
        let next = cur.next
        let keep = true
        # Check if unused let binding
        if cur.type == ast.STMT_LET:
            let name = cur.name.text
            if not nameset_has(used, name) and not has_side_effects(cur.initializer):
                keep = false
        # Check if unused proc
        if cur.type == ast.STMT_PROC:
            let name = cur.name.text
            if not nameset_has(used, name):
                keep = false
        if keep:
            dce_stmt_body(cur, used)
            cur.next = nil
            if new_head == nil:
                new_head = cur
            else:
                new_tail.next = cur
            new_tail = cur
        cur = next
    return new_head

# Pass entry point
proc pass_dce(program, ctx):
    # Collect all used names
    let used = nameset_new()
    collect_used_names_list(used, program)
    # Remove dead code
    program = dce_stmt_list(program, used)
    return program
