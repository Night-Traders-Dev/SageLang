gc_disable()
# Tests for inline.sage (function inlining pass)
import token
import ast
import inline

let passed = 0
let failed = 0

proc assert_eq(a, b, msg):
    if a == b:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ")"

proc assert_true(v, msg):
    if v:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

# Helper to make a simple proc: proc name(params): return expr
proc make_simple_proc(name, params, ret_expr):
    let param_tokens = []
    for p in params:
        push(param_tokens, token.Token(token.TOKEN_IDENTIFIER, p, 1))
    return ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, name, 1), param_tokens, ast.return_stmt(ret_expr))

# Helper to make a variable expr
proc make_var(name):
    return ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, name, 1))

# Helper to make a call
proc make_call(name, args):
    return ast.call_expr(make_var(name), args)

# --- get_single_return_expr ---
# Simple return
let body1 = ast.return_stmt(ast.number_expr(42))
let ret1 = inline.get_single_return_expr(body1)
assert_true(ret1 != nil, "single return found")
assert_eq(ret1.value, 42, "single return value")

# Multiple statements -> nil
let body2 = ast.print_stmt(ast.number_expr(1))
let body2b = ast.return_stmt(ast.number_expr(2))
body2.next = body2b
let ret2 = inline.get_single_return_expr(body2)
assert_eq(ret2, nil, "multi stmt no single return")

# No return
let body3 = ast.print_stmt(ast.number_expr(1))
let ret3 = inline.get_single_return_expr(body3)
assert_eq(ret3, nil, "no return stmt")

# nil body
let ret4 = inline.get_single_return_expr(nil)
assert_eq(ret4, nil, "nil body")

# --- expr_references_name ---
assert_eq(inline.expr_references_name(make_var("x"), "x"), true, "var refs its name")
assert_eq(inline.expr_references_name(make_var("x"), "y"), false, "var doesn't ref other")
assert_eq(inline.expr_references_name(ast.number_expr(1), "x"), false, "number doesn't ref")
assert_eq(inline.expr_references_name(nil, "x"), false, "nil doesn't ref")

# Binary
let bin1 = ast.binary_expr(make_var("x"), token.Token(token.TOKEN_PLUS, "+", 1), ast.number_expr(1))
assert_eq(inline.expr_references_name(bin1, "x"), true, "binary refs var")
assert_eq(inline.expr_references_name(bin1, "y"), false, "binary no ref other")

# Call
let call1 = ast.call_expr(make_var("f"), [make_var("x")])
assert_eq(inline.expr_references_name(call1, "f"), true, "call refs callee")
assert_eq(inline.expr_references_name(call1, "x"), true, "call refs arg")
assert_eq(inline.expr_references_name(call1, "y"), false, "call no ref other")

# --- collect_candidates ---
# proc double(x): return x + x -> candidate
let proc1 = make_simple_proc("double", ["x"], ast.binary_expr(make_var("x"), token.Token(token.TOKEN_PLUS, "+", 1), make_var("x")))
let prn = ast.print_stmt(ast.number_expr(1))
proc1.next = prn
let candidates = inline.collect_candidates(proc1)
assert_eq(len(candidates), 1, "one candidate")
assert_eq(candidates[0]["name"], "double", "candidate name")
assert_eq(candidates[0]["param_count"], 1, "candidate param_count")

# Recursive proc -> not a candidate
let rec_body = ast.return_stmt(ast.call_expr(make_var("rec"), [ast.number_expr(1)]))
let proc2 = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "rec", 1), [token.Token(token.TOKEN_IDENTIFIER, "n", 1)], rec_body)
let candidates2 = inline.collect_candidates(proc2)
assert_eq(len(candidates2), 0, "recursive not candidate")

# Multi-statement body -> not a candidate
let multi_body = ast.print_stmt(ast.number_expr(1))
multi_body.next = ast.return_stmt(ast.number_expr(2))
let proc3 = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "multi", 1), [], multi_body)
let candidates3 = inline.collect_candidates(proc3)
assert_eq(len(candidates3), 0, "multi-stmt not candidate")

# --- find_candidate ---
let fc = inline.find_candidate(candidates, "double")
assert_true(fc != nil, "find double")
assert_eq(fc["name"], "double", "found correct candidate")
let fc2 = inline.find_candidate(candidates, "nonexistent")
assert_eq(fc2, nil, "find nonexistent = nil")

# --- substitute_expr ---
# Substitute x -> 5 in expression "x + 1"
let params = [token.Token(token.TOKEN_IDENTIFIER, "x", 1)]
let args = [ast.number_expr(5)]
let src_expr = ast.binary_expr(make_var("x"), token.Token(token.TOKEN_PLUS, "+", 1), ast.number_expr(1))
let sub_result = inline.substitute_expr(src_expr, params, 1, args)
assert_eq(sub_result.type, ast.EXPR_BINARY, "substituted is binary")
assert_eq(sub_result.left.type, ast.EXPR_NUMBER, "left substituted to number")
assert_eq(sub_result.left.value, 5, "left = 5")
assert_eq(sub_result.right.value, 1, "right unchanged")

# Substitute in variable that matches
let sub2 = inline.substitute_expr(make_var("x"), params, 1, args)
assert_eq(sub2.type, ast.EXPR_NUMBER, "var substituted to number")
assert_eq(sub2.value, 5, "var = 5")

# Substitute in variable that doesn't match
let sub3 = inline.substitute_expr(make_var("y"), params, 1, args)
assert_eq(sub3.type, ast.EXPR_VARIABLE, "non-matching var stays")
assert_eq(sub3.name.text, "y", "non-matching var name")

# --- Full inlining: proc id(x): return x; print id(42) ---
# Build: proc id(x): return x
let id_proc = make_simple_proc("id", ["x"], make_var("x"))
# print id(42)
let print_call = ast.print_stmt(make_call("id", [ast.number_expr(42)]))
id_proc.next = print_call

let ctx = {}
ctx["opt_level"] = 3
let result = inline.pass_inline(id_proc, ctx)
# The print should now contain the inlined result (42) instead of call
let print_s = result.next
assert_eq(print_s.type, ast.STMT_PRINT, "print still print")
assert_eq(print_s.expression.type, ast.EXPR_NUMBER, "call inlined to number")
assert_eq(print_s.expression.value, 42, "inlined value = 42")

# --- Inlining with wrong arg count -> no inline ---
let add_proc = make_simple_proc("add", ["a", "b"], ast.binary_expr(make_var("a"), token.Token(token.TOKEN_PLUS, "+", 1), make_var("b")))
let wrong_call = ast.print_stmt(make_call("add", [ast.number_expr(1)]))
add_proc.next = wrong_call
let result2 = inline.pass_inline(add_proc, ctx)
let prn2 = result2.next
assert_eq(prn2.expression.type, ast.EXPR_CALL, "wrong argc not inlined")

# --- No candidates -> program unchanged ---
let just_print = ast.print_stmt(ast.number_expr(1))
let result3 = inline.pass_inline(just_print, ctx)
assert_eq(result3.type, ast.STMT_PRINT, "no candidates: unchanged")

print ""
print "Inline tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All inline tests passed!"
