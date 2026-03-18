gc_disable()
# Tests for the self-hosted diagnostic module
import diagnostic
import token

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
        print "FAIL: " + msg + " (should contain: " + str(needle) + ")"

proc assert_not_nil(val, msg):
    if val != nil:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (was nil)"

print "Self-hosted Diagnostic Tests"
print "============================="

# ============================================================================
# token_display_name
# ============================================================================
print nl + "--- token_display_name ---"

assert_eq(diagnostic.token_display_name(token.TOKEN_IDENTIFIER), "identifier", "display IDENTIFIER")
assert_eq(diagnostic.token_display_name(token.TOKEN_NUMBER), "number", "display NUMBER")
assert_eq(diagnostic.token_display_name(token.TOKEN_STRING), "string", "display STRING")
assert_eq(diagnostic.token_display_name(token.TOKEN_NEWLINE), "end of line", "display NEWLINE")
assert_eq(diagnostic.token_display_name(token.TOKEN_EOF), "end of file", "display EOF")
assert_eq(diagnostic.token_display_name(token.TOKEN_INDENT), "indentation", "display INDENT")
assert_eq(diagnostic.token_display_name(token.TOKEN_DEDENT), "dedent", "display DEDENT")

# Operator display names
assert_contains(diagnostic.token_display_name(token.TOKEN_PLUS), "+", "display PLUS contains +")
assert_contains(diagnostic.token_display_name(token.TOKEN_MINUS), "-", "display MINUS contains -")
assert_contains(diagnostic.token_display_name(token.TOKEN_STAR), "*", "display STAR contains *")
assert_contains(diagnostic.token_display_name(token.TOKEN_EQ), "==", "display EQ contains ==")
assert_contains(diagnostic.token_display_name(token.TOKEN_NEQ), "!=", "display NEQ contains !=")
assert_contains(diagnostic.token_display_name(token.TOKEN_LTE), "<=", "display LTE contains <=")
assert_contains(diagnostic.token_display_name(token.TOKEN_GTE), ">=", "display GTE contains >=")
assert_contains(diagnostic.token_display_name(token.TOKEN_LSHIFT), "<<", "display LSHIFT contains <<")
assert_contains(diagnostic.token_display_name(token.TOKEN_RSHIFT), ">>", "display RSHIFT contains >>")

# Keyword display names (lowercase)
let let_name = diagnostic.token_display_name(token.TOKEN_LET)
assert_eq(let_name, "let", "display LET is lowercase")
let proc_name = diagnostic.token_display_name(token.TOKEN_PROC)
assert_eq(proc_name, "proc", "display PROC is lowercase")
let if_name = diagnostic.token_display_name(token.TOKEN_IF)
assert_eq(if_name, "if", "display IF is lowercase")
let while_name = diagnostic.token_display_name(token.TOKEN_WHILE)
assert_eq(while_name, "while", "display WHILE is lowercase")
let class_name = diagnostic.token_display_name(token.TOKEN_CLASS)
assert_eq(class_name, "class", "display CLASS is lowercase")
let return_name = diagnostic.token_display_name(token.TOKEN_RETURN)
assert_eq(return_name, "return", "display RETURN is lowercase")

# ============================================================================
# repeat_char
# ============================================================================
print nl + "--- repeat_char ---"

assert_eq(diagnostic.repeat_char("x", 0), "", "repeat 0")
assert_eq(diagnostic.repeat_char("x", 1), "x", "repeat 1")
assert_eq(diagnostic.repeat_char("-", 5), "-----", "repeat 5 dashes")
assert_eq(diagnostic.repeat_char(" ", 3), "   ", "repeat 3 spaces")

# ============================================================================
# digit_count
# ============================================================================
print nl + "--- digit_count ---"

assert_eq(diagnostic.digit_count(0), 1, "digits of 0")
assert_eq(diagnostic.digit_count(5), 1, "digits of 5")
assert_eq(diagnostic.digit_count(10), 2, "digits of 10")
assert_eq(diagnostic.digit_count(99), 2, "digits of 99")
assert_eq(diagnostic.digit_count(100), 3, "digits of 100")
assert_eq(diagnostic.digit_count(999), 3, "digits of 999")
assert_eq(diagnostic.digit_count(1000), 4, "digits of 1000")

# ============================================================================
# pad_left
# ============================================================================
print nl + "--- pad_left ---"

assert_eq(diagnostic.pad_left("5", 3), "  5", "pad 5 to width 3")
assert_eq(diagnostic.pad_left("42", 4), "  42", "pad 42 to width 4")
assert_eq(diagnostic.pad_left("hello", 3), "hello", "pad no-op when wider")
assert_eq(diagnostic.pad_left("x", 1), "x", "pad exact width")

# ============================================================================
# format_diagnostic
# ============================================================================
print nl + "--- format_diagnostic ---"

let d1 = diagnostic.format_diagnostic("error", "test.sage", 5, 3, 1, "unexpected token", "let x = ;", nil)
assert_contains(d1, "error: unexpected token", "diag has severity+message")
assert_contains(d1, "test.sage:5:4", "diag has location")
assert_contains(d1, "let x = ;", "diag has source line")
assert_contains(d1, "^", "diag has caret pointer")

# With span > 1
let d2 = diagnostic.format_diagnostic("warning", "foo.sage", 10, 0, 5, "unused variable", "let hello = 42", nil)
assert_contains(d2, "warning: unused variable", "span diag has warning")
assert_contains(d2, "~~~~~", "span diag has tilde range")

# With help text
let d3 = diagnostic.format_diagnostic("error", "bar.sage", 1, 0, 1, "missing colon", "proc foo()", "add ':' after '()'")
assert_contains(d3, "= help:", "diag with help has help line")
assert_contains(d3, "add", "diag help content")

# No source line
let d4 = diagnostic.format_diagnostic("note", "info.sage", 0, -1, 1, "file imported here", nil, nil)
assert_contains(d4, "note: file imported here", "no-source diag has message")
assert_contains(d4, "info.sage", "no-source diag has filename")

# ============================================================================
# format_error / format_warning / format_note convenience
# ============================================================================
print nl + "--- convenience functions ---"

let e1 = diagnostic.format_error("a.sage", 3, 2, 1, "bad token", "abc", nil)
assert_contains(e1, "error:", "format_error uses error severity")

let w1 = diagnostic.format_warning("b.sage", 7, 0, 3, "deprecated", "old_fn()", nil)
assert_contains(w1, "warning:", "format_warning uses warning severity")

let n1 = diagnostic.format_note("c.sage", 1, 0, 1, "defined here", "let x = 1", nil)
assert_contains(n1, "note:", "format_note uses note severity")

# ============================================================================
# format_token_diagnostic with dict token
# ============================================================================
print nl + "--- format_token_diagnostic ---"

let tok = {}
tok["filename"] = "my.sage"
tok["line"] = 12
tok["column"] = 5
tok["line_text"] = "print hello"

let td1 = diagnostic.format_token_diagnostic("error", tok, "fallback.sage", 1, "undefined name", nil)
assert_contains(td1, "my.sage:12:6", "token diag uses token filename+line")
assert_contains(td1, "print hello", "token diag uses line_text")

# With nil token, uses fallback
let td2 = diagnostic.format_token_diagnostic("error", nil, "fallback.sage", 1, "parse error", nil)
assert_contains(td2, "fallback.sage", "nil token uses fallback filename")

# ============================================================================
# Summary
# ============================================================================
print nl + "============================="
print str(passed) + " passed, " + str(failed) + " failed"

if failed > 0:
    print "SOME TESTS FAILED"
else:
    print "All diagnostic tests passed!"
