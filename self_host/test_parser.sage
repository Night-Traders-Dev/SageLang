gc_disable()
# -----------------------------------------
# test_parser.sage - Tests for the self-hosted parser
# -----------------------------------------

from parser import parse_source
from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC
from ast import expr_type_name, stmt_type_name

let pass_count = 0
let fail_count = 0

proc assert_eq(actual, expected, test_name):
    if actual == expected:
        pass_count = pass_count + 1
    else:
        fail_count = fail_count + 1
        print("FAIL: " + test_name)
        print("  expected: " + str(expected))
        print("  actual:   " + str(actual))

proc assert_true(val, test_name):
    if val:
        pass_count = pass_count + 1
    else:
        fail_count = fail_count + 1
        print("FAIL: " + test_name)

# --- Test 1: Number expression ---
proc test_number():
    let nl = chr(10)
    let stmts = parse_source("42" + nl)
    assert_eq(len(stmts), 1, "number: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_EXPRESSION, "number: stmt type")
    let e = s.expression
    assert_eq(e.type, EXPR_NUMBER, "number: expr type")
    assert_eq(e.value, 42, "number: value")

# --- Test 2: Binary operations ---
proc test_binary():
    let nl = chr(10)
    let stmts = parse_source("1 + 2" + nl)
    assert_eq(len(stmts), 1, "binary: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_EXPRESSION, "binary: stmt type")
    let e = s.expression
    assert_eq(e.type, EXPR_BINARY, "binary: expr type")
    assert_eq(e.left.type, EXPR_NUMBER, "binary: left type")
    assert_eq(e.left.value, 1, "binary: left value")
    assert_eq(e.op.text, "+", "binary: op")
    assert_eq(e.right.type, EXPR_NUMBER, "binary: right type")
    assert_eq(e.right.value, 2, "binary: right value")

# --- Test 3: Precedence ---
proc test_precedence():
    let nl = chr(10)
    # 1 + 2 * 3 should parse as 1 + (2 * 3)
    let stmts = parse_source("1 + 2 * 3" + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_BINARY, "prec: top is binary")
    assert_eq(e.op.text, "+", "prec: top op is +")
    assert_eq(e.left.value, 1, "prec: left is 1")
    assert_eq(e.right.type, EXPR_BINARY, "prec: right is binary")
    assert_eq(e.right.op.text, "*", "prec: right op is *")
    assert_eq(e.right.left.value, 2, "prec: right.left is 2")
    assert_eq(e.right.right.value, 3, "prec: right.right is 3")

# --- Test 4: Let declaration ---
proc test_let():
    let nl = chr(10)
    let stmts = parse_source("let x = 10" + nl)
    assert_eq(len(stmts), 1, "let: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_LET, "let: stmt type")
    assert_eq(s.name.text, "x", "let: name")
    assert_eq(s.initializer.type, EXPR_NUMBER, "let: init type")
    assert_eq(s.initializer.value, 10, "let: init value")

# --- Test 5: Var declaration ---
proc test_var():
    let nl = chr(10)
    let stmts = parse_source("var y = 20" + nl)
    assert_eq(len(stmts), 1, "var: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_LET, "var: stmt type (same as let)")
    assert_eq(s.name.text, "y", "var: name")

# --- Test 6: If statement ---
proc test_if():
    let nl = chr(10)
    let src = "if x > 0:" + nl + "    print(1)" + nl
    let stmts = parse_source(src)
    assert_eq(len(stmts), 1, "if: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_IF, "if: stmt type")
    assert_eq(s.condition.type, EXPR_BINARY, "if: condition type")
    assert_eq(s.condition.op.text, ">", "if: condition op")
    assert_eq(s.then_branch.type, STMT_BLOCK, "if: then is block")
    assert_true(s.else_branch == nil, "if: no else")

# --- Test 7: If/else ---
proc test_if_else():
    let nl = chr(10)
    let src = "if x:" + nl + "    print(1)" + nl + "else:" + nl + "    print(2)" + nl
    let stmts = parse_source(src)
    let s = stmts[0]
    assert_eq(s.type, STMT_IF, "if-else: stmt type")
    assert_true(s.then_branch != nil, "if-else: has then")
    assert_true(s.else_branch != nil, "if-else: has else")

# --- Test 8: While loop ---
proc test_while():
    let nl = chr(10)
    let src = "while x > 0:" + nl + "    x = x - 1" + nl
    let stmts = parse_source(src)
    assert_eq(len(stmts), 1, "while: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_WHILE, "while: stmt type")
    assert_eq(s.condition.type, EXPR_BINARY, "while: condition type")
    assert_eq(s.body.type, STMT_BLOCK, "while: body is block")

# --- Test 9: For loop ---
proc test_for():
    let nl = chr(10)
    let src = "for i in range(10):" + nl + "    print(i)" + nl
    let stmts = parse_source(src)
    assert_eq(len(stmts), 1, "for: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_FOR, "for: stmt type")
    assert_eq(s.variable.text, "i", "for: variable")
    assert_eq(s.iterable.type, EXPR_CALL, "for: iterable is call")

# --- Test 10: Proc definition ---
proc test_proc():
    let nl = chr(10)
    let src = "proc add(a, b):" + nl + "    return a + b" + nl
    let stmts = parse_source(src)
    assert_eq(len(stmts), 1, "proc: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_PROC, "proc: stmt type")
    assert_eq(s.name.text, "add", "proc: name")
    assert_eq(s.param_count, 2, "proc: param count")
    assert_eq(s.params[0].text, "a", "proc: param 0")
    assert_eq(s.params[1].text, "b", "proc: param 1")

# --- Test 11: Class definition ---
proc test_class():
    let nl = chr(10)
    let src = "class Dog:" + nl + "    proc init(name):" + nl + "        self.name = name" + nl + "    proc bark():" + nl + "        print(self.name)" + nl
    let stmts = parse_source(src)
    assert_eq(len(stmts), 1, "class: stmt count")
    let s = stmts[0]
    assert_eq(s.type, STMT_CLASS, "class: stmt type")
    assert_eq(s.name.text, "Dog", "class: name")
    assert_eq(s.has_parent, 0, "class: no parent")
    assert_true(s.methods != nil, "class: has methods")
    assert_eq(s.methods.type, STMT_PROC, "class: first method is proc")
    assert_eq(s.methods.name.text, "init", "class: init method")
    assert_true(s.methods.next != nil, "class: has second method")
    assert_eq(s.methods.next.name.text, "bark", "class: bark method")

# --- Test 12: Class with parent ---
proc test_class_inherit():
    let nl = chr(10)
    let src = "class Puppy(Dog):" + nl + "    proc init():" + nl + "        print(1)" + nl
    let stmts = parse_source(src)
    let s = stmts[0]
    assert_eq(s.type, STMT_CLASS, "inherit: stmt type")
    assert_eq(s.name.text, "Puppy", "inherit: name")
    assert_eq(s.has_parent, 1, "inherit: has parent")
    assert_eq(s.parent.text, "Dog", "inherit: parent name")

# --- Test 13: Return statement ---
proc test_return():
    let nl = chr(10)
    let src = "proc f():" + nl + "    return 42" + nl
    let stmts = parse_source(src)
    let s = stmts[0]
    assert_eq(s.type, STMT_PROC, "return: proc type")
    # The body is a block; walk into the first statement
    let body = s.body
    assert_eq(body.type, STMT_BLOCK, "return: body is block")
    let ret = body.statements
    assert_eq(ret.type, STMT_RETURN, "return: stmt type")
    assert_eq(ret.value.type, EXPR_NUMBER, "return: value type")
    assert_eq(ret.value.value, 42, "return: value")

# --- Test 14: Array literal ---
proc test_array():
    let nl = chr(10)
    let stmts = parse_source("[1, 2, 3]" + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_ARRAY, "array: expr type")
    assert_eq(e.count, 3, "array: count")
    assert_eq(e.elements[0].value, 1, "array: elem 0")
    assert_eq(e.elements[1].value, 2, "array: elem 1")
    assert_eq(e.elements[2].value, 3, "array: elem 2")

# --- Test 15: Dict literal ---
proc test_dict():
    let nl = chr(10)
    let dq = chr(34)
    let src = "{" + dq + "a" + dq + ": 1, " + dq + "b" + dq + ": 2}" + nl
    let stmts = parse_source(src)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_DICT, "dict: expr type")
    assert_eq(e.count, 2, "dict: count")
    assert_eq(e.keys[0], "a", "dict: key 0")
    assert_eq(e.keys[1], "b", "dict: key 1")
    assert_eq(e.values[0].value, 1, "dict: val 0")
    assert_eq(e.values[1].value, 2, "dict: val 1")

# --- Test 16: Property access and call ---
proc test_property_call():
    let nl = chr(10)
    let stmts = parse_source("obj.method(1)" + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_CALL, "prop-call: is call")
    assert_eq(e.callee.type, EXPR_GET, "prop-call: callee is get")
    assert_eq(e.callee.property.text, "method", "prop-call: property")
    assert_eq(e.arg_count, 1, "prop-call: arg count")

# --- Test 17: Index access ---
proc test_index():
    let nl = chr(10)
    let stmts = parse_source("arr[0]" + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_INDEX, "index: expr type")
    assert_eq(e.index.value, 0, "index: value")

# --- Test 18: String expression ---
proc test_string():
    let nl = chr(10)
    let dq = chr(34)
    let stmts = parse_source(dq + "hello" + dq + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_STRING, "string: expr type")
    assert_eq(e.value, "hello", "string: value")

# --- Test 19: Boolean/nil expressions ---
proc test_bool_nil():
    let nl = chr(10)
    let stmts = parse_source("true" + nl)
    assert_eq(stmts[0].expression.type, EXPR_BOOL, "bool: true type")
    assert_eq(stmts[0].expression.value, true, "bool: true value")
    let stmts2 = parse_source("false" + nl)
    assert_eq(stmts2[0].expression.type, EXPR_BOOL, "bool: false type")
    assert_eq(stmts2[0].expression.value, false, "bool: false value")
    let stmts3 = parse_source("nil" + nl)
    assert_eq(stmts3[0].expression.type, EXPR_NIL, "nil: type")

# --- Test 20: Break and continue ---
proc test_break_continue():
    let nl = chr(10)
    let src = "while true:" + nl + "    break" + nl
    let stmts = parse_source(src)
    let s = stmts[0]
    assert_eq(s.type, STMT_WHILE, "break: while type")
    let body_stmt = s.body.statements
    assert_eq(body_stmt.type, STMT_BREAK, "break: stmt type")

# --- Test 21: Print statement ---
proc test_print():
    let nl = chr(10)
    let stmts = parse_source("print(42)" + nl)
    let s = stmts[0]
    assert_eq(s.type, STMT_PRINT, "print: stmt type")
    assert_eq(s.expression.type, EXPR_NUMBER, "print: expr type")

# --- Test 22: Try/catch/finally ---
proc test_try():
    let nl = chr(10)
    let src = "try:" + nl + "    print(1)" + nl + "catch e:" + nl + "    print(2)" + nl + "finally:" + nl + "    print(3)" + nl
    let stmts = parse_source(src)
    let s = stmts[0]
    assert_eq(s.type, STMT_TRY, "try: stmt type")
    assert_true(s.try_block != nil, "try: has try block")
    assert_eq(s.catch_count, 1, "try: catch count")
    assert_eq(s.catches[0].exception_var.text, "e", "try: catch var")
    assert_true(s.finally_block != nil, "try: has finally block")

# --- Test 23: Raise statement ---
proc test_raise():
    let nl = chr(10)
    let dq = chr(34)
    let src = "raise " + dq + "error" + dq + nl
    let stmts = parse_source(src)
    let s = stmts[0]
    assert_eq(s.type, STMT_RAISE, "raise: stmt type")
    assert_eq(s.exception.type, EXPR_STRING, "raise: exception type")

# --- Test 24: Import statements ---
proc test_import():
    let nl = chr(10)
    let stmts = parse_source("import mymod" + nl)
    let s = stmts[0]
    assert_eq(s.type, STMT_IMPORT, "import: stmt type")
    assert_eq(s.module_name, "mymod", "import: module name")
    assert_eq(s.import_all, 1, "import: import_all")

# --- Test 25: From import ---
proc test_from_import():
    let nl = chr(10)
    let stmts = parse_source("from mymod import foo, bar" + nl)
    let s = stmts[0]
    assert_eq(s.type, STMT_IMPORT, "from-import: stmt type")
    assert_eq(s.module_name, "mymod", "from-import: module name")
    assert_eq(s.import_all, 0, "from-import: not import_all")
    assert_eq(s.item_count, 2, "from-import: item count")
    assert_eq(s.items[0], "foo", "from-import: item 0")
    assert_eq(s.items[1], "bar", "from-import: item 1")

# --- Test 26: Variable assignment ---
proc test_assignment():
    let nl = chr(10)
    let stmts = parse_source("x = 5" + nl)
    let s = stmts[0]
    assert_eq(s.type, STMT_EXPRESSION, "assign: stmt type")
    let e = s.expression
    assert_eq(e.type, EXPR_SET, "assign: expr type is SET")

# --- Test 27: Multiple statements ---
proc test_multiple():
    let nl = chr(10)
    let src = "let a = 1" + nl + "let b = 2" + nl + "print(a + b)" + nl
    let stmts = parse_source(src)
    assert_eq(len(stmts), 3, "multi: stmt count")
    assert_eq(stmts[0].type, STMT_LET, "multi: first is let")
    assert_eq(stmts[1].type, STMT_LET, "multi: second is let")
    assert_eq(stmts[2].type, STMT_PRINT, "multi: third is print")

# --- Test 28: Nested calls ---
proc test_nested_calls():
    let nl = chr(10)
    let stmts = parse_source("f(g(1), 2)" + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_CALL, "nested: outer call")
    assert_eq(e.arg_count, 2, "nested: outer arg count")
    assert_eq(e.args[0].type, EXPR_CALL, "nested: inner call")
    assert_eq(e.args[0].arg_count, 1, "nested: inner arg count")

# --- Test 29: Unary minus ---
proc test_unary_minus():
    let nl = chr(10)
    let stmts = parse_source("-5" + nl)
    let e = stmts[0].expression
    # -5 is represented as (0 - 5)
    assert_eq(e.type, EXPR_BINARY, "unary-minus: binary type")
    assert_eq(e.left.value, 0, "unary-minus: left is 0")
    assert_eq(e.op.text, "-", "unary-minus: op is -")
    assert_eq(e.right.value, 5, "unary-minus: right is 5")

# --- Test 30: Comparison chain ---
proc test_comparison():
    let nl = chr(10)
    let stmts = parse_source("a == b" + nl)
    let e = stmts[0].expression
    assert_eq(e.type, EXPR_BINARY, "cmp: binary type")
    assert_eq(e.op.text, "==", "cmp: op is ==")
    assert_eq(e.left.type, EXPR_VARIABLE, "cmp: left is var")
    assert_eq(e.right.type, EXPR_VARIABLE, "cmp: right is var")

# --- Run all tests ---
print("Running parser tests...")
test_number()
test_binary()
test_precedence()
test_let()
test_var()
test_if()
test_if_else()
test_while()
test_for()
test_proc()
test_class()
test_class_inherit()
test_return()
test_array()
test_dict()
test_property_call()
test_index()
test_string()
test_bool_nil()
test_break_continue()
test_print()
test_try()
test_raise()
test_import()
test_from_import()
test_assignment()
test_multiple()
test_nested_calls()
test_unary_minus()
test_comparison()

print("")
print("Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed")
if fail_count == 0:
    print("All tests passed!")
else:
    print("Some tests FAILED.")
