gc_disable()
# Tests for the self-hosted value module
from value import is_truthy, is_falsy, is_nil, is_number, is_bool, is_string
from value import is_array, is_dict, to_number, to_string, to_bool
from value import deep_equal, deep_clone, inspect
from value import TYPE_NIL, TYPE_NUMBER, TYPE_BOOL, TYPE_STRING

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

print "Self-hosted Value Tests"
print "======================="

# Truthiness (Sage: 0 is truthy!)
print ""
print "--- Truthiness ---"
assert_eq(is_truthy(true), true, "true is truthy")
assert_eq(is_truthy(false), false, "false is not truthy")
assert_eq(is_truthy(nil), false, "nil is not truthy")
assert_eq(is_truthy(0), true, "0 is truthy in Sage")
assert_eq(is_truthy(1), true, "1 is truthy")
assert_eq(is_truthy(""), true, "empty string is truthy")
assert_eq(is_truthy([]), true, "empty array is truthy")

assert_eq(is_falsy(false), true, "false is falsy")
assert_eq(is_falsy(nil), true, "nil is falsy")
assert_eq(is_falsy(42), false, "42 is not falsy")

# Type checking
print ""
print "--- Type Checking ---"
assert_eq(is_nil(nil), true, "is_nil nil")
assert_eq(is_nil(0), false, "is_nil 0")
assert_eq(is_number(42), true, "is_number 42")
assert_eq(is_number("42"), false, "is_number string")
assert_eq(is_bool(true), true, "is_bool true")
assert_eq(is_bool(1), false, "is_bool 1")
assert_eq(is_string("hello"), true, "is_string hello")
assert_eq(is_array([1, 2]), true, "is_array")
assert_eq(is_dict({}), true, "is_dict")

# Type constants
assert_eq(TYPE_NIL, "nil", "TYPE_NIL")
assert_eq(TYPE_NUMBER, "number", "TYPE_NUMBER")

# Coercion
print ""
print "--- Coercion ---"
assert_eq(to_number(42), 42, "to_number number")
assert_eq(to_number("123"), 123, "to_number string")
assert_eq(to_string(42), "42", "to_string number")
assert_eq(to_string(true), "true", "to_string bool")
assert_eq(to_bool(42), true, "to_bool truthy")
assert_eq(to_bool(nil), false, "to_bool nil")

# Deep equality
print ""
print "--- Deep Equality ---"
assert_eq(deep_equal(1, 1), true, "deep_equal numbers")
assert_eq(deep_equal(1, 2), false, "deep_equal diff numbers")
assert_eq(deep_equal("a", "a"), true, "deep_equal strings")
assert_eq(deep_equal([1, 2, 3], [1, 2, 3]), true, "deep_equal arrays")
assert_eq(deep_equal([1, 2], [1, 3]), false, "deep_equal diff arrays")
assert_eq(deep_equal([1, [2, 3]], [1, [2, 3]]), true, "deep_equal nested arrays")
assert_eq(deep_equal(nil, nil), true, "deep_equal nil")

# Deep clone
print ""
print "--- Deep Clone ---"
let orig = [1, [2, 3], "hello"]
let cloned = deep_clone(orig)
assert_eq(deep_equal(orig, cloned), true, "clone equals original")
push(cloned[1], 4)
assert_eq(len(orig[1]), 2, "clone is independent")

# Inspect
print ""
print "--- Inspect ---"
assert_eq(inspect(nil), "<nil>", "inspect nil")
assert_eq(inspect(42), "<number: 42>", "inspect number")
assert_eq(inspect(true), "<bool: true>", "inspect true")
assert_eq(inspect(false), "<bool: false>", "inspect false")

# Summary
print ""
print "=== Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed ==="
if fail_count > 0:
    print "SOME TESTS FAILED"
else:
    print "All value tests passed!"
