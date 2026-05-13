gc_disable()
# Tests for the self-hosted linter
from linter import lint_source, is_snake_case, is_pascal_case
from linter import measure_indent, is_blank_line, extract_ident_after, trim_line

let nl = chr(10)
let pass_count = 0
let fail_count = 0

proc assert_eq(actual, expected, name):
    if actual == expected:
        print "  [PASS] " + name
        pass_count = pass_count + 1
    else:
        print "  [FAIL] " + name
        print "    expected: " + str(expected)
        print "    actual:   " + str(actual)
        fail_count = fail_count + 1

proc has_rule(messages, rule):
    for msg in messages:
        if msg["rule"] == rule:
            return true
    return false

print "Self-hosted Linter Tests"
print "========================"

# Test helpers
print nl + "--- Helper Functions ---"

assert_eq(is_snake_case("hello_world"), true, "snake_case valid")
assert_eq(is_snake_case("helloWorld"), false, "snake_case camelCase")
assert_eq(is_snake_case("HelloWorld"), false, "snake_case PascalCase")
assert_eq(is_snake_case("x"), true, "snake_case single char")

assert_eq(is_pascal_case("Hello"), true, "pascal_case valid")
assert_eq(is_pascal_case("hello"), false, "pascal_case lowercase")

let ind = measure_indent("    hello")
assert_eq(ind["width"], 4, "measure_indent width")
assert_eq(ind["has_space"], true, "measure_indent has_space")
assert_eq(ind["has_tab"], false, "measure_indent no tab")

assert_eq(is_blank_line("   "), true, "blank line spaces")
assert_eq(is_blank_line("  x"), false, "non-blank line")

assert_eq(extract_ident_after("let foo = 1", 4), "foo", "extract ident")
assert_eq(trim_line("  hello  "), "hello", "trim_line")

# Test E001: Bad indentation
print nl + "--- E001: Indentation ---"

let src1 = "   bad_indent" + nl
let msgs1 = lint_source(src1)
assert_eq(has_rule(msgs1, "E001"), true, "E001 detects 3-space indent")

let src1b = "    good_indent" + nl
let msgs1b = lint_source(src1b)
assert_eq(has_rule(msgs1b, "E001"), false, "E001 passes 4-space indent")

# Test E003: Line too long
print nl + "--- E003: Line Length ---"

let long_line = ""
for i in range(125):
    long_line = long_line + "x"
let src3 = long_line + nl
let msgs3 = lint_source(src3)
assert_eq(has_rule(msgs3, "E003"), true, "E003 detects 125-char line")

# Test W003: Unreachable code
print nl + "--- W003: Unreachable Code ---"

let src4 = "proc foo():" + nl + "    return 1" + nl + "    print 2" + nl
let msgs4 = lint_source(src4)
assert_eq(has_rule(msgs4, "W003"), true, "W003 detects unreachable after return")

# Test W004: Empty block
print nl + "--- W004: Empty Block ---"

let src5 = "if true:" + nl + "print done" + nl
let msgs5 = lint_source(src5)
assert_eq(has_rule(msgs5, "W004"), true, "W004 detects empty block")

# Test S001: Proc naming
print nl + "--- S001: Proc Naming ---"

let src6 = "# doc" + nl + "proc badName():" + nl + "    print 1" + nl
let msgs6 = lint_source(src6)
assert_eq(has_rule(msgs6, "S001"), true, "S001 detects non-snake_case proc")

let src6b = "# doc" + nl + "proc good_name():" + nl + "    print 1" + nl
let msgs6b = lint_source(src6b)
assert_eq(has_rule(msgs6b, "S001"), false, "S001 passes snake_case proc")

# Test S002: Class naming
print nl + "--- S002: Class Naming ---"

let src7 = "class myclass:" + nl + "    let x = 1" + nl
let msgs7 = lint_source(src7)
assert_eq(has_rule(msgs7, "S002"), true, "S002 detects non-PascalCase class")

let src7b = "class MyClass:" + nl + "    let x = 1" + nl
let msgs7b = lint_source(src7b)
assert_eq(has_rule(msgs7b, "S002"), false, "S002 passes PascalCase class")

# Test S003: Missing docstring
print nl + "--- S003: Missing Docstring ---"

let src8 = "proc no_doc():" + nl + "    print 1" + nl
let msgs8 = lint_source(src8)
assert_eq(has_rule(msgs8, "S003"), true, "S003 detects missing docstring")

let src8b = "# documented" + nl + "proc has_doc():" + nl + "    print 1" + nl
let msgs8b = lint_source(src8b)
assert_eq(has_rule(msgs8b, "S003"), false, "S003 passes with docstring")

# Test S004: Trailing semicolons
print nl + "--- S004: Trailing Semicolons ---"

let src9 = "let x = 1;" + nl
let msgs9 = lint_source(src9)
assert_eq(has_rule(msgs9, "S004"), true, "S004 detects trailing semicolon")

# Summary
print nl + "=== Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed ==="
if fail_count > 0:
    print "SOME TESTS FAILED"
else:
    print "All linter tests passed!"
