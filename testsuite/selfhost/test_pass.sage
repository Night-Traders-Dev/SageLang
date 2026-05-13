gc_disable()
# Tests for pass.sage (AST cloning infrastructure)
import token
import ast
import pass

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

# --- clone_token ---
let tok = token.Token(token.TOKEN_IDENTIFIER, "hello", 5)
let tok2 = pass.clone_token(tok)
assert_eq(tok2.type, token.TOKEN_IDENTIFIER, "clone_token type")
assert_eq(tok2.text, "hello", "clone_token text")
assert_eq(tok2.line, 5, "clone_token line")

# clone_token nil
let tok3 = pass.clone_token(nil)
assert_eq(tok3, nil, "clone_token nil")

# --- clone_expr: number ---
let e1 = ast.number_expr(42)
let e1c = pass.clone_expr(e1)
assert_eq(e1c.type, ast.EXPR_NUMBER, "clone number type")
assert_eq(e1c.value, 42, "clone number value")

# --- clone_expr: string ---
let e2 = ast.string_expr("test")
let e2c = pass.clone_expr(e2)
assert_eq(e2c.type, ast.EXPR_STRING, "clone string type")
assert_eq(e2c.value, "test", "clone string value")

# --- clone_expr: bool ---
let e3 = ast.bool_expr(true)
let e3c = pass.clone_expr(e3)
assert_eq(e3c.type, ast.EXPR_BOOL, "clone bool type")
assert_eq(e3c.value, true, "clone bool value")

# --- clone_expr: nil ---
let e4 = ast.nil_expr()
let e4c = pass.clone_expr(e4)
assert_eq(e4c.type, ast.EXPR_NIL, "clone nil type")

# --- clone_expr: variable ---
let e5 = ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "x", 1))
let e5c = pass.clone_expr(e5)
assert_eq(e5c.type, ast.EXPR_VARIABLE, "clone variable type")
assert_eq(e5c.name.text, "x", "clone variable name")

# --- clone_expr: binary ---
let e6 = ast.binary_expr(ast.number_expr(1), token.Token(token.TOKEN_PLUS, "+", 1), ast.number_expr(2))
let e6c = pass.clone_expr(e6)
assert_eq(e6c.type, ast.EXPR_BINARY, "clone binary type")
assert_eq(e6c.left.value, 1, "clone binary left")
assert_eq(e6c.op.text, "+", "clone binary op")
assert_eq(e6c.right.value, 2, "clone binary right")

# --- clone_expr: call ---
let e7 = ast.call_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "f", 1)), [ast.number_expr(10)])
let e7c = pass.clone_expr(e7)
assert_eq(e7c.type, ast.EXPR_CALL, "clone call type")
assert_eq(e7c.callee.name.text, "f", "clone call callee")
assert_eq(e7c.arg_count, 1, "clone call arg_count")
assert_eq(e7c.args[0].value, 10, "clone call arg value")

# --- clone_expr: array ---
let e8 = ast.array_expr([ast.number_expr(1), ast.number_expr(2)])
let e8c = pass.clone_expr(e8)
assert_eq(e8c.type, ast.EXPR_ARRAY, "clone array type")
assert_eq(e8c.count, 2, "clone array count")
assert_eq(e8c.elements[0].value, 1, "clone array elem 0")
assert_eq(e8c.elements[1].value, 2, "clone array elem 1")

# --- clone_expr: index ---
let e9 = ast.index_expr(ast.variable_expr(token.Token(token.TOKEN_IDENTIFIER, "a", 1)), ast.number_expr(0))
let e9c = pass.clone_expr(e9)
assert_eq(e9c.type, ast.EXPR_INDEX, "clone index type")
assert_eq(e9c.object.name.text, "a", "clone index object")
assert_eq(e9c.index.value, 0, "clone index idx")

# --- clone_expr: nil input ---
let e10 = pass.clone_expr(nil)
assert_eq(e10, nil, "clone_expr nil")

# --- clone_stmt: print ---
let s1 = ast.print_stmt(ast.number_expr(42))
let s1c = pass.clone_stmt(s1)
assert_eq(s1c.type, ast.STMT_PRINT, "clone print type")
assert_eq(s1c.expression.value, 42, "clone print expr")

# --- clone_stmt: let ---
let s2 = ast.let_stmt(token.Token(token.TOKEN_IDENTIFIER, "x", 1), ast.number_expr(5))
let s2c = pass.clone_stmt(s2)
assert_eq(s2c.type, ast.STMT_LET, "clone let type")
assert_eq(s2c.name.text, "x", "clone let name")
assert_eq(s2c.initializer.value, 5, "clone let init")

# --- clone_stmt: return ---
let s3 = ast.return_stmt(ast.string_expr("done"))
let s3c = pass.clone_stmt(s3)
assert_eq(s3c.type, ast.STMT_RETURN, "clone return type")
assert_eq(s3c.value.value, "done", "clone return value")

# --- clone_stmt: break/continue ---
let s4 = ast.break_stmt()
let s4c = pass.clone_stmt(s4)
assert_eq(s4c.type, ast.STMT_BREAK, "clone break")

let s5 = ast.continue_stmt()
let s5c = pass.clone_stmt(s5)
assert_eq(s5c.type, ast.STMT_CONTINUE, "clone continue")

# --- clone_stmt_list ---
let s6 = ast.print_stmt(ast.number_expr(1))
let s7 = ast.print_stmt(ast.number_expr(2))
s6.next = s7
let list_clone = pass.clone_stmt_list(s6)
assert_eq(list_clone.type, ast.STMT_PRINT, "clone list first type")
assert_eq(list_clone.expression.value, 1, "clone list first val")
assert_true(list_clone.next != nil, "clone list has next")
assert_eq(list_clone.next.expression.value, 2, "clone list second val")
assert_eq(list_clone.next.next, nil, "clone list ends")

# --- clone_stmt_list nil ---
let list2 = pass.clone_stmt_list(nil)
assert_eq(list2, nil, "clone_stmt_list nil")

# --- clone_stmt: proc ---
let p1 = ast.proc_stmt(token.Token(token.TOKEN_IDENTIFIER, "add", 1), [token.Token(token.TOKEN_IDENTIFIER, "a", 1), token.Token(token.TOKEN_IDENTIFIER, "b", 1)], ast.return_stmt(ast.number_expr(0)))
let p1c = pass.clone_stmt(p1)
assert_eq(p1c.type, ast.STMT_PROC, "clone proc type")
assert_eq(p1c.name.text, "add", "clone proc name")
assert_eq(p1c.param_count, 2, "clone proc param_count")
assert_eq(p1c.params[0].text, "a", "clone proc param 0")
assert_eq(p1c.params[1].text, "b", "clone proc param 1")

print ""
print "Pass tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All pass tests passed!"
