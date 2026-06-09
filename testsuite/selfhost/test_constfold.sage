gc_disable()
# Tests for constfold.sage (constant folding pass)
import token
import ast
import constfold

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

# Helper to make a binary expr
proc make_bin(left, op_text, right):
    return ast.binary_expr(left, token.Token(token.TOKEN_PLUS, op_text, 1), right)

# --- Number arithmetic ---
let e1 = make_bin(ast.number_expr(2), "+", ast.number_expr(3))
let r1 = constfold.fold_expr(e1)
assert_eq(r1.type, ast.EXPR_NUMBER, "2+3 is number")
assert_eq(r1.value, 5, "2+3 = 5")

let e2 = make_bin(ast.number_expr(10), "-", ast.number_expr(4))
let r2 = constfold.fold_expr(e2)
assert_eq(r2.value, 6, "10-4 = 6")

let e3 = make_bin(ast.number_expr(3), "*", ast.number_expr(7))
let r3 = constfold.fold_expr(e3)
assert_eq(r3.value, 21, "3*7 = 21")

let e4 = make_bin(ast.number_expr(15), "/", ast.number_expr(3))
let r4 = constfold.fold_expr(e4)
assert_eq(r4.value, 5, "15/3 = 5")

let e5 = make_bin(ast.number_expr(7), "%", ast.number_expr(3))
let r5 = constfold.fold_expr(e5)
assert_eq(r5.value, 1, "7%3 = 1")

# Division by zero not folded
let e6 = make_bin(ast.number_expr(5), "/", ast.number_expr(0))
let r6 = constfold.fold_expr(e6)
assert_eq(r6.type, ast.EXPR_BINARY, "div by zero unchanged")

# --- Number comparisons ---
let e7 = make_bin(ast.number_expr(3), "<", ast.number_expr(5))
let r7 = constfold.fold_expr(e7)
assert_eq(r7.type, ast.EXPR_BOOL, "3<5 is bool")
assert_eq(r7.value, true, "3<5 = true")

let e8 = make_bin(ast.number_expr(5), ">", ast.number_expr(3))
let r8 = constfold.fold_expr(e8)
assert_eq(r8.value, true, "5>3 = true")

let e9 = make_bin(ast.number_expr(3), "==", ast.number_expr(3))
let r9 = constfold.fold_expr(e9)
assert_eq(r9.value, true, "3==3 = true")

let e10 = make_bin(ast.number_expr(3), "!=", ast.number_expr(5))
let r10 = constfold.fold_expr(e10)
assert_eq(r10.value, true, "3!=5 = true")

let e11 = make_bin(ast.number_expr(3), "<=", ast.number_expr(3))
let r11 = constfold.fold_expr(e11)
assert_eq(r11.value, true, "3<=3 = true")

let e12 = make_bin(ast.number_expr(5), ">=", ast.number_expr(3))
let r12 = constfold.fold_expr(e12)
assert_eq(r12.value, true, "5>=3 = true")

# --- String concatenation ---
let e13 = make_bin(ast.string_expr("hello"), "+", ast.string_expr(" world"))
let r13 = constfold.fold_expr(e13)
assert_eq(r13.type, ast.EXPR_STRING, "str concat is string")
assert_eq(r13.value, "hello world", "str concat value")

# --- Boolean logic ---
let e14 = make_bin(ast.bool_expr(true), "and", ast.bool_expr(false))
let r14 = constfold.fold_expr(e14)
assert_eq(r14.type, ast.EXPR_BOOL, "bool and is bool")
assert_eq(r14.value, false, "true and false = false")

let e15 = make_bin(ast.bool_expr(false), "or", ast.bool_expr(true))
let r15 = constfold.fold_expr(e15)
assert_eq(r15.value, true, "false or true = true")

let e16 = make_bin(ast.bool_expr(true), "and", ast.bool_expr(true))
let r16 = constfold.fold_expr(e16)
assert_eq(r16.value, true, "true and true = true")

# --- Non-constant expressions unchanged ---
let e17 = make_bin(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "x", 1)), "+", ast.number_expr(1))
let r17 = constfold.fold_expr(e17)
assert_eq(r17.type, ast.EXPR_BINARY, "var+1 unchanged")

# --- Nested folding ---
# (2 + 3) + 4 -> 5 + 4 -> 9
let e18 = make_bin(make_bin(ast.number_expr(2), "+", ast.number_expr(3)), "+", ast.number_expr(4))
let r18 = constfold.fold_expr(e18)
assert_eq(r18.type, ast.EXPR_NUMBER, "nested fold is number")
assert_eq(r18.value, 9, "(2+3)+4 = 9")

# --- Statement-level: constant if true ---
let s1 = ast.if_stmt(ast.bool_expr(true), ast.print_stmt(ast.number_expr(1)), ast.print_stmt(ast.number_expr(2)))
constfold.fold_stmt(s1)
assert_eq(s1.type, ast.STMT_BLOCK, "if true -> block")

# --- Statement-level: constant if false with else ---
let s2 = ast.if_stmt(ast.bool_expr(false), ast.print_stmt(ast.number_expr(1)), ast.print_stmt(ast.number_expr(2)))
constfold.fold_stmt(s2)
assert_eq(s2.type, ast.STMT_BLOCK, "if false -> else block")

# --- Statement-level: constant if false without else ---
let s3 = ast.if_stmt(ast.bool_expr(false), ast.print_stmt(ast.number_expr(1)), nil)
constfold.fold_stmt(s3)
assert_eq(s3.type, ast.STMT_EXPRESSION, "if false no else -> nil expr")

# --- Statement-level: while false eliminated ---
let s4 = ast.while_stmt(ast.bool_expr(false), ast.print_stmt(ast.number_expr(1)))
constfold.fold_stmt(s4)
assert_eq(s4.type, ast.STMT_EXPRESSION, "while false -> nil expr")

# --- fold_expr nil ---
let r19 = constfold.fold_expr(nil)
assert_eq(r19, nil, "fold_expr nil")

# --- fold in let initializer ---
let s5 = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), make_bin(ast.number_expr(10), "+", ast.number_expr(20)))
constfold.fold_stmt(s5)
assert_eq(s5.initializer.type, ast.EXPR_NUMBER, "let init folded")
assert_eq(s5.initializer.value, 30, "let init = 30")

print ""
print "Constfold tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All constfold tests passed!"
