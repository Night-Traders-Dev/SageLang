gc_disable()
# Tests for the self-hosted error reporting module
import errors

let nl = chr(10)
let passed = 0
let failed = 0

proc assert_eq(actual, expected, msg):
    if actual == expected:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_contains(haystack, needle, msg):
    if contains(haystack, needle):
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (should contain: " + needle + ")"

proc assert_not_contains(haystack, needle, msg):
    if contains(haystack, needle):
        failed = failed + 1
        print "FAIL: " + msg + " (should not contain: " + needle + ")"
    else:
        passed = passed + 1

print "Self-hosted Error Reporting Tests"
print "=================================="

# ============================================================================
# split_lines
# ============================================================================

print nl + "--- split_lines ---"

let lines1 = errors.split_lines("hello" + nl + "world")
assert_eq(len(lines1), 2, "split_lines 2 lines count")
assert_eq(lines1[0], "hello", "split_lines first line")
assert_eq(lines1[1], "world", "split_lines second line")

let lines2 = errors.split_lines("single")
assert_eq(len(lines2), 1, "split_lines single line")
assert_eq(lines2[0], "single", "split_lines single content")

let lines3 = errors.split_lines("")
assert_eq(len(lines3), 1, "split_lines empty string")
assert_eq(lines3[0], "", "split_lines empty content")

let lines4 = errors.split_lines("a" + nl + "b" + nl + "c" + nl + "d")
assert_eq(len(lines4), 4, "split_lines 4 lines")
assert_eq(lines4[2], "c", "split_lines third line")

let lines5 = errors.split_lines("trailing" + nl)
assert_eq(len(lines5), 2, "split_lines trailing newline count")
assert_eq(lines5[0], "trailing", "split_lines trailing first")
assert_eq(lines5[1], "", "split_lines trailing empty last")

# ============================================================================
# make_error_context
# ============================================================================

print nl + "--- make_error_context ---"

let src = "let x = 42" + nl + "print x" + nl + "let y = 10"
let ctx = errors.make_error_context(src, "test.sage")
assert_eq(ctx["filename"], "test.sage", "ctx filename")
assert_eq(ctx["source"], src, "ctx source")
assert_eq(len(ctx["lines"]), 3, "ctx lines count")

# ============================================================================
# get_line_text
# ============================================================================

print nl + "--- get_line_text ---"

assert_eq(errors.get_line_text(ctx, 1), "let x = 42", "get_line_text line 1")
assert_eq(errors.get_line_text(ctx, 2), "print x", "get_line_text line 2")
assert_eq(errors.get_line_text(ctx, 3), "let y = 10", "get_line_text line 3")
assert_eq(errors.get_line_text(ctx, 0), "", "get_line_text line 0 oob")
assert_eq(errors.get_line_text(ctx, 99), "", "get_line_text line 99 oob")

# ============================================================================
# repeat_char
# ============================================================================

print nl + "--- repeat_char ---"

assert_eq(errors.repeat_char(" ", 0), "", "repeat_char 0")
assert_eq(errors.repeat_char(" ", 3), "   ", "repeat_char 3 spaces")
assert_eq(errors.repeat_char("~", 5), "~~~~~", "repeat_char 5 tildes")
assert_eq(errors.repeat_char("x", 1), "x", "repeat_char 1")

# ============================================================================
# make_pointer
# ============================================================================

print nl + "--- make_pointer ---"

assert_eq(errors.make_pointer(0, 1), "^", "pointer at col 0")
assert_eq(errors.make_pointer(4, 1), "    ^", "pointer at col 4")
assert_eq(errors.make_pointer(2, 5), "  ~~~~~", "pointer range col 2 len 5")
assert_eq(errors.make_pointer(0, 3), "~~~", "pointer range col 0 len 3")

# ============================================================================
# digit_count
# ============================================================================

print nl + "--- digit_count ---"

assert_eq(errors.digit_count(1), 1, "digit_count 1")
assert_eq(errors.digit_count(9), 1, "digit_count 9")
assert_eq(errors.digit_count(10), 2, "digit_count 10")
assert_eq(errors.digit_count(99), 2, "digit_count 99")
assert_eq(errors.digit_count(100), 3, "digit_count 100")
assert_eq(errors.digit_count(999), 3, "digit_count 999")
assert_eq(errors.digit_count(1000), 4, "digit_count 1000")

# ============================================================================
# pad_left
# ============================================================================

print nl + "--- pad_left ---"

assert_eq(errors.pad_left("5", 3), "  5", "pad_left 5 to 3")
assert_eq(errors.pad_left("42", 3), " 42", "pad_left 42 to 3")
assert_eq(errors.pad_left("100", 3), "100", "pad_left 100 to 3 (exact)")
assert_eq(errors.pad_left("1000", 3), "1000", "pad_left 1000 to 3 (overflow)")

# ============================================================================
# format_error - basic error output
# ============================================================================

print nl + "--- format_error ---"

let src2 = "let x = + 42" + nl + "print x"
let ctx2 = errors.make_error_context(src2, "test.sage")

let err1 = errors.format_error(ctx2, 1, 8, "Error", "Unexpected token", nil)
assert_contains(err1, "Error: Unexpected token", "error header")
assert_contains(err1, "--> test.sage:1:9", "error location")
assert_contains(err1, "let x = + 42", "error source line")
assert_contains(err1, "^", "error pointer")

# With hint
let err2 = errors.format_error(ctx2, 1, 8, "Error", "Unexpected token", "expressions cannot start with an operator")
assert_contains(err2, "hint: expressions cannot start with an operator", "error hint")

# Warning kind
let err3 = errors.format_error(ctx2, 2, 0, "Warning", "unused variable", nil)
assert_contains(err3, "Warning: unused variable", "warning header")
assert_contains(err3, "print x", "warning source line")

# Unknown column
let err4 = errors.format_error(ctx2, 1, -1, "Error", "Something wrong", nil)
assert_contains(err4, "--> test.sage:1", "error no column")
assert_not_contains(err4, "^", "error no pointer when col=-1")

# ============================================================================
# format_error_range
# ============================================================================

print nl + "--- format_error_range ---"

let err5 = errors.format_error_range(ctx2, 1, 4, 3, "Error", "Invalid name", nil)
assert_contains(err5, "~~~", "range pointer tildes")
assert_contains(err5, "let x = + 42", "range source line")

let err6 = errors.format_error_range(ctx2, 1, 0, 3, "Error", "Bad keyword", "did you mean 'var'?")
assert_contains(err6, "~~~", "range pointer at start")
assert_contains(err6, "hint: did you mean", "range hint")

# ============================================================================
# format_type_error
# ============================================================================

print nl + "--- format_type_error ---"

let err7 = errors.format_type_error(ctx2, 1, "number", "string", nil)
assert_contains(err7, "Type mismatch: expected number, got string", "type error msg")
assert_contains(err7, "--> test.sage:1", "type error location")

let err8 = errors.format_type_error(ctx2, 1, "array", "number", "use [value] to wrap in array")
assert_contains(err8, "hint: use [value] to wrap in array", "type error hint")

# ============================================================================
# format_undefined_error
# ============================================================================

print nl + "--- format_undefined_error ---"

let err9 = errors.format_undefined_error(ctx2, 1, "prnt", ["print"])
assert_contains(err9, "Undefined name", "undef error msg")
assert_contains(err9, "prnt", "undef error name")
assert_contains(err9, "Did you mean", "undef suggestion")
assert_contains(err9, "print", "undef suggestion name")

let err10 = errors.format_undefined_error(ctx2, 1, "xyz", [])
assert_contains(err10, "Undefined name", "undef no suggestion msg")
assert_not_contains(err10, "Did you mean", "undef no suggestion hint")

# Multiple suggestions
let err11 = errors.format_undefined_error(ctx2, 1, "prnt", ["print", "println"])
assert_contains(err11, "Did you mean", "undef multi suggestion")
assert_contains(err11, "print", "undef multi first")
assert_contains(err11, "println", "undef multi second")

# ============================================================================
# Edge cases
# ============================================================================

print nl + "--- Edge Cases ---"

# Empty source
let ctx3 = errors.make_error_context("", "empty.sage")
let err12 = errors.format_error(ctx3, 1, 0, "Error", "Empty file", nil)
assert_contains(err12, "Error: Empty file", "empty file error header")
assert_contains(err12, "--> empty.sage:1:1", "empty file location")

# Large line number (multi-digit gutter)
let big_src = ""
let bi = 0
while bi < 120:
    big_src = big_src + "line " + str(bi) + nl
    bi = bi + 1
let ctx4 = errors.make_error_context(big_src, "big.sage")
let err13 = errors.format_error(ctx4, 100, 0, "Error", "Late error", nil)
assert_contains(err13, "100", "big line number in output")
assert_contains(err13, "line 99", "big line source text")

# Single character source
let ctx5 = errors.make_error_context("x", "tiny.sage")
let err14 = errors.format_error(ctx5, 1, 0, "Error", "Unexpected char", nil)
assert_contains(err14, "x", "tiny source in output")
assert_contains(err14, "^", "tiny pointer")

# ============================================================================
# Summary
# ============================================================================

print nl + "Error Reporting Tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All error reporting tests passed!"
else:
    print "SOME TESTS FAILED"
