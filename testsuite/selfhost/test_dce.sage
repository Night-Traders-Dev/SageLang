gc_disable()
# Tests for dce.sage (dead code elimination pass)
import token
import ast
import dce

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

# --- nameset ---
let ns = dce.nameset_new()
assert_eq(dce.nameset_has(ns, "x"), false, "nameset empty")
dce.nameset_add(ns, "x")
assert_eq(dce.nameset_has(ns, "x"), true, "nameset has x")
assert_eq(dce.nameset_has(ns, "y"), false, "nameset no y")
dce.nameset_add(ns, "y")
assert_eq(dce.nameset_has(ns, "y"), true, "nameset has y")

# --- has_side_effects ---
assert_eq(dce.has_side_effects(nil), false, "nil no side effects")
assert_eq(dce.has_side_effects(ast.number_expr(1)), false, "number no side effects")
assert_eq(dce.has_side_effects(ast.string_expr("hi")), false, "string no side effects")
assert_eq(dce.has_side_effects(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "x", 1))), false, "var no side effects")
let call_e = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "f", 1)), [])
assert_eq(dce.has_side_effects(call_e), true, "call has side effects")

# --- is_terminator ---
let ret_s = ast.return_stmt(nil)
assert_eq(dce.is_terminator(ret_s), true, "return is terminator")
let brk_s = ast.break_stmt()
assert_eq(dce.is_terminator(brk_s), true, "break is terminator")
let cnt_s = ast.continue_stmt()
assert_eq(dce.is_terminator(cnt_s), true, "continue is terminator")
let prn_s = ast.print_stmt(ast.number_expr(1))
assert_eq(dce.is_terminator(prn_s), false, "print not terminator")

# --- remove_unreachable ---
# return followed by print -> only return
let s1 = ast.return_stmt(ast.number_expr(1))
let s2 = ast.print_stmt(ast.number_expr(2))
s1.next = s2
let result = dce.remove_unreachable(s1)
assert_eq(result.type, ast.STMT_RETURN, "unreachable: first is return")
assert_eq(result.next, nil, "unreachable: nothing after return")

# No terminator -> keep all
let s3 = ast.print_stmt(ast.number_expr(1))
let s4 = ast.print_stmt(ast.number_expr(2))
s3.next = s4
let result2 = dce.remove_unreachable(s3)
assert_eq(result2.next.type, ast.STMT_PRINT, "no terminator: keep all")

# nil input
let result3 = dce.remove_unreachable(nil)
assert_eq(result3, nil, "remove_unreachable nil")

# --- collect_used_names ---
let used = dce.nameset_new()
let var_e = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "myvar", 1))
dce.collect_used_names_expr(used, var_e)
assert_eq(dce.nameset_has(used, "myvar"), true, "collect var name")

let used2 = dce.nameset_new()
let bin_e = ast.binary_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "a", 1)), token.Token(token.TOKEN_PLUS, "+", 1), ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "b", 1)))
dce.collect_used_names_expr(used2, bin_e)
assert_eq(dce.nameset_has(used2, "a"), true, "collect binary left name")
assert_eq(dce.nameset_has(used2, "b"), true, "collect binary right name")

# --- DCE: remove unused let ---
# let x = 5; print 42  -> x is unused, remove let
let let_s = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "unused_var", 1), ast.number_expr(5))
let prn = ast.print_stmt(ast.number_expr(42))
let_s.next = prn
let used3 = dce.nameset_new()
dce.collect_used_names_list(used3, let_s)
let dce_result = dce.dce_stmt_list(let_s, used3)
assert_eq(dce_result.type, ast.STMT_PRINT, "unused let removed")
assert_eq(dce_result.next, nil, "only print remains")

# --- DCE: keep used let ---
# let x = 5; print x  -> x is used, keep let
let let_s2 = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "used_var", 1), ast.number_expr(5))
let prn2 = ast.print_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "used_var", 1)))
let_s2.next = prn2
let used4 = dce.nameset_new()
dce.collect_used_names_list(used4, let_s2)
let dce_result2 = dce.dce_stmt_list(let_s2, used4)
assert_eq(dce_result2.type, ast.STMT_LET, "used let kept")
assert_true(dce_result2.next != nil, "print follows let")

# --- DCE: remove unused proc ---
# proc unused(): return 1; print 42 -> proc unused, keep print
let proc_s = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "unused_func", 1), [], ast.return_stmt(ast.number_expr(1)))
let prn3 = ast.print_stmt(ast.number_expr(42))
proc_s.next = prn3
let used5 = dce.nameset_new()
dce.collect_used_names_list(used5, proc_s)
let dce_result3 = dce.dce_stmt_list(proc_s, used5)
assert_eq(dce_result3.type, ast.STMT_PRINT, "unused proc removed")

# --- DCE: keep let with side effects ---
# let x = f(); print 42 -> f() has side effects, keep let
let let_s3 = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "unused_but_side", 1), ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "f", 1)), []))
let prn4 = ast.print_stmt(ast.number_expr(42))
let_s3.next = prn4
let used6 = dce.nameset_new()
dce.collect_used_names_list(used6, let_s3)
let dce_result4 = dce.dce_stmt_list(let_s3, used6)
assert_eq(dce_result4.type, ast.STMT_LET, "let with side effects kept")

# --- Full pass_dce ---
let prog_let = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "dead", 1), ast.number_expr(99))
let prog_prn = ast.print_stmt(ast.number_expr(1))
prog_let.next = prog_prn
let ctx = {}
ctx["opt_level"] = 2
let dce_prog = dce.pass_dce(prog_let, ctx)
assert_eq(dce_prog.type, ast.STMT_PRINT, "pass_dce removes dead let")

print ""
print "DCE tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All DCE tests passed!"
