gc_disable()
# Tests for typecheck.sage (type inference pass)
import token
import ast
import typecheck

let passed = 0
let failed = 0

proc assert_eq(a, b, msg):
    if a == b:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ")"

# --- Type kind names ---
assert_eq(typecheck.type_kind_name(typecheck.TYPE_NUMBER), "number", "kind name number")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_STRING), "string", "kind name string")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_BOOL), "bool", "kind name bool")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_NIL), "nil", "kind name nil")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_ARRAY), "array", "kind name array")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_DICT), "dict", "kind name dict")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_TUPLE), "tuple", "kind name tuple")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_FUNCTION), "function", "kind name function")
assert_eq(typecheck.type_kind_name(typecheck.TYPE_UNKNOWN), "unknown", "kind name unknown")
assert_eq(typecheck.type_kind_name(99), "unknown", "kind name invalid")

# --- TypeMap ---
let tmap = typecheck.TypeMap()
assert_eq(tmap.get_var("x"), typecheck.TYPE_UNKNOWN, "tmap unknown var")
tmap.set_var("x", typecheck.TYPE_NUMBER)
assert_eq(tmap.get_var("x"), typecheck.TYPE_NUMBER, "tmap set/get x")
tmap.set_var("y", typecheck.TYPE_STRING)
assert_eq(tmap.get_var("y"), typecheck.TYPE_STRING, "tmap set/get y")
# Overwrite
tmap.set_var("x", typecheck.TYPE_BOOL)
assert_eq(tmap.get_var("x"), typecheck.TYPE_BOOL, "tmap overwrite x")

# --- infer_expr: literals ---
let tmap2 = typecheck.TypeMap()
assert_eq(typecheck.infer_expr(tmap2, ast.number_expr(42)), typecheck.TYPE_NUMBER, "infer number")
assert_eq(typecheck.infer_expr(tmap2, ast.string_expr("hi")), typecheck.TYPE_STRING, "infer string")
assert_eq(typecheck.infer_expr(tmap2, ast.bool_expr(true)), typecheck.TYPE_BOOL, "infer bool")
assert_eq(typecheck.infer_expr(tmap2, ast.nil_expr()), typecheck.TYPE_NIL, "infer nil")
assert_eq(typecheck.infer_expr(tmap2, nil), typecheck.TYPE_UNKNOWN, "infer nil expr")

# --- infer_expr: array/dict/tuple ---
assert_eq(typecheck.infer_expr(tmap2, ast.array_expr([ast.number_expr(1)])), typecheck.TYPE_ARRAY, "infer array")
assert_eq(typecheck.infer_expr(tmap2, ast.dict_expr(["a"], [ast.number_expr(1)])), typecheck.TYPE_DICT, "infer dict")
assert_eq(typecheck.infer_expr(tmap2, ast.tuple_expr([ast.number_expr(1)])), typecheck.TYPE_TUPLE, "infer tuple")

# --- infer_expr: variable ---
tmap2.set_var("mynum", typecheck.TYPE_NUMBER)
let var_e = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "mynum", 1))
assert_eq(typecheck.infer_expr(tmap2, var_e), typecheck.TYPE_NUMBER, "infer var")
let var_e2 = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "unknown_var", 1))
assert_eq(typecheck.infer_expr(tmap2, var_e2), typecheck.TYPE_UNKNOWN, "infer unknown var")

# --- infer_expr: binary number arithmetic ---
let bin_add = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_PLUS, "+", 1), ast.number_expr(2))
assert_eq(typecheck.infer_expr(tmap2, bin_add), typecheck.TYPE_NUMBER, "infer num + num = num")

let bin_sub = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_MINUS, "-", 1), ast.number_expr(2))
assert_eq(typecheck.infer_expr(tmap2, bin_sub), typecheck.TYPE_NUMBER, "infer num - num = num")

let bin_mul = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_STAR, "*", 1), ast.number_expr(2))
assert_eq(typecheck.infer_expr(tmap2, bin_mul), typecheck.TYPE_NUMBER, "infer num * num = num")

# --- infer_expr: binary number comparison ---
let bin_lt = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_LT, "<", 1), ast.number_expr(2))
assert_eq(typecheck.infer_expr(tmap2, bin_lt), typecheck.TYPE_BOOL, "infer num < num = bool")

let bin_eq = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_EQ, "==", 1), ast.number_expr(2))
assert_eq(typecheck.infer_expr(tmap2, bin_eq), typecheck.TYPE_BOOL, "infer num == num = bool")

# --- infer_expr: string concatenation ---
let bin_str = ast.binary_expr(ast.string_expr("a"), token.Token(token.TOKEN_PLUS, "+", 1), ast.string_expr("b"))
assert_eq(typecheck.infer_expr(tmap2, bin_str), typecheck.TYPE_STRING, "infer str + str = str")

# --- infer_expr: string comparison ---
let bin_str_eq = ast.binary_expr(ast.string_expr("a"), token.Token(token.TOKEN_EQ, "==", 1), ast.string_expr("b"))
assert_eq(typecheck.infer_expr(tmap2, bin_str_eq), typecheck.TYPE_BOOL, "infer str == str = bool")

# --- infer_expr: call returns unknown ---
let call_e = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "f", 1)), [])
assert_eq(typecheck.infer_expr(tmap2, call_e), typecheck.TYPE_UNKNOWN, "infer call = unknown")

# --- infer_stmt: let binds type ---
let tmap3 = typecheck.TypeMap()
let let_s = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(10))
typecheck.infer_stmt(tmap3, let_s)
assert_eq(tmap3.get_var("x"), typecheck.TYPE_NUMBER, "infer let x = 10 -> number")

let let_s2 = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "s", 1), ast.string_expr("hi"))
typecheck.infer_stmt(tmap3, let_s2)
assert_eq(tmap3.get_var("s"), typecheck.TYPE_STRING, "infer let s = str -> string")

# --- infer_stmt: proc registers as function ---
let tmap4 = typecheck.TypeMap()
let proc_s = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "myfunc", 1), [], ast.return_stmt(ast.number_expr(1)))
typecheck.infer_stmt(tmap4, proc_s)
assert_eq(tmap4.get_var("myfunc"), typecheck.TYPE_FUNCTION, "infer proc -> function")

# --- pass_typecheck: runs without error ---
let prog = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "a", 1), ast.number_expr(42))
let prog2 = ast.print_stmt(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "a", 1)))
prog.next = prog2
let ctx = {}
ctx["opt_level"] = 1
let result = typecheck.pass_typecheck(prog, ctx)
assert_eq(result.type, ast.STMT_LET, "pass_typecheck returns program")

print ""
print "Typecheck tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All typecheck tests passed!"
