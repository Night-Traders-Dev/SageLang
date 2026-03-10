gc_disable()
# Tests for the self-hosted formatter
from formatter import format_source, is_toplevel_def, is_block_header
from formatter import normalize_operators, normalize_comment, strip_colon_space
from formatter import count_leading, strip_leading, rstrip

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

print "Self-hosted Formatter Tests"
print "==========================="

# Test helpers
print nl + "--- Helper Functions ---"

assert_eq(is_toplevel_def("proc foo():"), true, "is_toplevel_def proc")
assert_eq(is_toplevel_def("class Foo:"), true, "is_toplevel_def class")
assert_eq(is_toplevel_def("async proc bar():"), true, "is_toplevel_def async proc")
assert_eq(is_toplevel_def("let x = 1"), false, "is_toplevel_def let")

assert_eq(is_block_header("if x > 0:"), true, "is_block_header if")
assert_eq(is_block_header("for i in range(10):"), true, "is_block_header for")
assert_eq(is_block_header("while true:"), true, "is_block_header while")
assert_eq(is_block_header("class Foo:"), true, "is_block_header class")
assert_eq(is_block_header("let x = 1"), false, "is_block_header let")

assert_eq(count_leading("    hello"), 4, "count_leading 4 spaces")
assert_eq(count_leading("hello"), 0, "count_leading none")
assert_eq(count_leading("        x"), 8, "count_leading 8 spaces")

assert_eq(strip_leading("    hello"), "hello", "strip_leading")
assert_eq(strip_leading("hello"), "hello", "strip_leading none")

assert_eq(rstrip("hello   "), "hello", "rstrip spaces")
assert_eq(rstrip("hello"), "hello", "rstrip none")

# Test operator normalization
print nl + "--- Operator Normalization ---"

assert_eq(normalize_operators("x=1"), "x = 1", "normalize = no spaces")
assert_eq(normalize_operators("x==y"), "x == y", "normalize ==")
assert_eq(normalize_operators("x!=y"), "x != y", "normalize !=")
assert_eq(normalize_operators("a+b"), "a + b", "normalize +")
assert_eq(normalize_operators("a-b"), "a - b", "normalize -")
assert_eq(normalize_operators("a*b"), "a * b", "normalize *")
assert_eq(normalize_operators("a,b,c"), "a, b, c", "normalize commas")
assert_eq(normalize_operators("x = -1"), "x = -1", "preserve unary minus")

# Test comment normalization
print nl + "--- Comment Normalization ---"

assert_eq(normalize_comment("#comment"), "# comment", "add space after #")
assert_eq(normalize_comment("# comment"), "# comment", "already has space")
assert_eq(normalize_comment("x = 1 #note"), "x = 1 # note", "inline comment")

# Test strip_colon_space
print nl + "--- Colon Spacing ---"

assert_eq(strip_colon_space("if x  :"), "if x:", "strip space before colon")
assert_eq(strip_colon_space("if x:"), "if x:", "already clean")
assert_eq(strip_colon_space("let x = 1"), "let x = 1", "no colon")

# Test full formatting
print nl + "--- Full Formatting ---"

let src1 = "let   x=1" + nl + "let y =  2" + nl
let fmt1 = format_source(src1)
assert_eq(contains(fmt1, "x = 1"), true, "format normalizes =")

let src2 = "proc foo():" + nl + "    print 42" + nl + nl + nl + nl + nl + "proc bar():" + nl + "    print 99" + nl
let fmt2 = format_source(src2)
# Should have at most 2 blank lines between defs
let parts = split(fmt2, nl + nl + nl + nl)
assert_eq(len(parts), 1, "max blank lines enforced")

let src3 = "let x = 1" + nl + nl + "proc foo():" + nl + "    return x" + nl
let fmt3 = format_source(src3)
assert_eq(endswith(fmt3, nl), true, "ends with newline")

# Summary
print nl + "=== Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed ==="
if fail_count > 0:
    print "SOME TESTS FAILED"
else:
    print "All formatter tests passed!"
