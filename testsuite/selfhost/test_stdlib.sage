gc_disable()
# Tests for stdlib.sage (standard library pure Sage implementations)
import stdlib

let passed = 0
let failed = 0

proc assert_eq(a, b, msg):
    if a == b:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ")"

proc assert_near(a, b, tol, msg):
    let diff = a - b
    if diff < 0:
        diff = -diff
    if diff < tol:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg + " (got " + str(a) + ", expected " + str(b) + ", diff=" + str(diff) + ")"

proc assert_true(v, msg):
    if v:
        passed = passed + 1
    else:
        failed = failed + 1
        print "FAIL: " + msg

# ============================================================================
# Math Module
# ============================================================================

let m = stdlib.create_math_module()
assert_near(m["pi"], 3.14159265, 0.0001, "math.pi")
assert_near(m["e"], 2.71828182, 0.0001, "math.e")
assert_near(m["tau"], 6.28318530, 0.0001, "math.tau")

# --- math_abs ---
assert_eq(stdlib.math_abs(5), 5, "abs(5)")
assert_eq(stdlib.math_abs(-5), 5, "abs(-5)")
assert_eq(stdlib.math_abs(0), 0, "abs(0)")

# --- math_min / math_max ---
assert_eq(stdlib.math_min(3, 7), 3, "min(3,7)")
assert_eq(stdlib.math_min(7, 3), 3, "min(7,3)")
assert_eq(stdlib.math_max(3, 7), 7, "max(3,7)")
assert_eq(stdlib.math_max(7, 3), 7, "max(7,3)")

# --- math_clamp ---
assert_eq(stdlib.math_clamp(5, 1, 10), 5, "clamp in range")
assert_eq(stdlib.math_clamp(-1, 0, 10), 0, "clamp below")
assert_eq(stdlib.math_clamp(15, 0, 10), 10, "clamp above")

# --- math_floor / math_ceil / math_round ---
assert_eq(stdlib.math_floor(3.7), 3, "floor(3.7)")
assert_eq(stdlib.math_floor(3.0), 3, "floor(3.0)")
assert_eq(stdlib.math_floor(-1.5), -2, "floor(-1.5)")
assert_eq(stdlib.math_ceil(3.2), 4, "ceil(3.2)")
assert_eq(stdlib.math_ceil(3.0), 3, "ceil(3.0)")
assert_eq(stdlib.math_ceil(-1.5), -1, "ceil(-1.5)")
assert_eq(stdlib.math_round(3.5), 4, "round(3.5)")
assert_eq(stdlib.math_round(3.4), 3, "round(3.4)")
assert_eq(stdlib.math_round(-0.6), -1, "round(-0.6)")

# --- math_fmod ---
assert_eq(stdlib.math_fmod(7, 3), 1, "fmod(7,3)")
assert_eq(stdlib.math_fmod(10, 5), 0, "fmod(10,5)")
assert_eq(stdlib.math_fmod(0, 3), 0, "fmod(0,3)")

# --- math_pow ---
assert_eq(stdlib.math_pow(2, 10), 1024, "pow(2,10)")
assert_eq(stdlib.math_pow(3, 0), 1, "pow(3,0)")
assert_eq(stdlib.math_pow(5, 1), 5, "pow(5,1)")
assert_near(stdlib.math_pow(2, -1), 0.5, 0.0001, "pow(2,-1)")

# --- math_sqrt ---
assert_near(stdlib.math_sqrt(4), 2.0, 0.0001, "sqrt(4)")
assert_near(stdlib.math_sqrt(9), 3.0, 0.0001, "sqrt(9)")
assert_near(stdlib.math_sqrt(2), 1.41421356, 0.0001, "sqrt(2)")
assert_eq(stdlib.math_sqrt(0), 0, "sqrt(0)")

# --- math_log ---
assert_near(stdlib.math_log(1), 0.0, 0.001, "log(1)")
assert_near(stdlib.math_log(m["e"]), 1.0, 0.01, "log(e)")

# --- math_log10 ---
assert_near(stdlib.math_log10(10), 1.0, 0.01, "log10(10)")
assert_near(stdlib.math_log10(100), 2.0, 0.01, "log10(100)")

# --- math_exp ---
assert_near(stdlib.math_exp(0), 1.0, 0.0001, "exp(0)")
assert_near(stdlib.math_exp(1), 2.71828, 0.001, "exp(1)")

# --- math_sin / math_cos ---
assert_near(stdlib.math_sin(0), 0.0, 0.0001, "sin(0)")
assert_near(stdlib.math_sin(m["pi"] / 2), 1.0, 0.0001, "sin(pi/2)")
assert_near(stdlib.math_cos(0), 1.0, 0.0001, "cos(0)")
assert_near(stdlib.math_cos(m["pi"]), -1.0, 0.001, "cos(pi)")

# --- math_tan ---
assert_near(stdlib.math_tan(0), 0.0, 0.0001, "tan(0)")

# ============================================================================
# String Module
# ============================================================================

# --- string_find ---
assert_eq(stdlib.string_find("hello world", "world"), 6, "find world")
assert_eq(stdlib.string_find("hello world", "xyz"), -1, "find missing")
assert_eq(stdlib.string_find("hello", ""), 0, "find empty")
assert_eq(stdlib.string_find("abc", "abcd"), -1, "find longer needle")

# --- string_rfind ---
assert_eq(stdlib.string_rfind("abcabc", "abc"), 3, "rfind last")
assert_eq(stdlib.string_rfind("abcabc", "xyz"), -1, "rfind missing")

# --- string_startswith / string_endswith ---
assert_eq(stdlib.string_startswith("hello", "hel"), true, "startswith true")
assert_eq(stdlib.string_startswith("hello", "xyz"), false, "startswith false")
assert_eq(stdlib.string_endswith("hello", "llo"), true, "endswith true")
assert_eq(stdlib.string_endswith("hello", "xyz"), false, "endswith false")

# --- string_contains ---
assert_eq(stdlib.string_contains("hello world", "world"), true, "contains true")
assert_eq(stdlib.string_contains("hello world", "xyz"), false, "contains false")

# --- string_char_at ---
assert_eq(stdlib.string_char_at("hello", 0), "h", "char_at 0")
assert_eq(stdlib.string_char_at("hello", 4), "o", "char_at 4")
assert_eq(stdlib.string_char_at("hello", 5), nil, "char_at out of range")
assert_eq(stdlib.string_char_at("hello", -1), nil, "char_at negative")

# --- string_repeat ---
assert_eq(stdlib.string_repeat("ab", 3), "ababab", "repeat 3")
assert_eq(stdlib.string_repeat("x", 0), "", "repeat 0")
assert_eq(stdlib.string_repeat("x", 1), "x", "repeat 1")

# --- string_count ---
assert_eq(stdlib.string_count("banana", "an"), 2, "count an")
assert_eq(stdlib.string_count("aaaa", "aa"), 2, "count overlapping")
assert_eq(stdlib.string_count("hello", "xyz"), 0, "count missing")

# --- string_substr ---
assert_eq(stdlib.string_substr("hello world", 6, 5), "world", "substr")
assert_eq(stdlib.string_substr("hello", 0, 3), "hel", "substr from 0")
assert_eq(stdlib.string_substr("hello", 10, 3), "", "substr past end")

# --- string_reverse ---
assert_eq(stdlib.string_reverse("hello"), "olleh", "reverse")
assert_eq(stdlib.string_reverse("a"), "a", "reverse single")
assert_eq(stdlib.string_reverse(""), "", "reverse empty")

# ============================================================================
# IO Module
# ============================================================================

# Test io_exists and io_read/io_write
let test_path = "/tmp/sage_test_stdlib_io.txt"
stdlib.io_write(test_path, "test content")
assert_eq(stdlib.io_exists(test_path), true, "io exists after write")
let content = stdlib.io_read(test_path)
assert_eq(content, "test content", "io read back")

# Test io_append
stdlib.io_append(test_path, " appended")
let content2 = stdlib.io_read(test_path)
assert_eq(content2, "test content appended", "io append")

# Nonexistent file
assert_eq(stdlib.io_exists("/tmp/sage_test_nonexistent_file_xyz.txt"), false, "io not exists")

# ============================================================================
# Sys Module
# ============================================================================

let sys = stdlib.create_sys_module()
assert_eq(sys["version"], "2.2.0", "sys.version")
assert_eq(sys["platform"], "sage", "sys.platform")

# ============================================================================
# Module Registry
# ============================================================================

stdlib.init_stdlib()
assert_eq(stdlib.is_stdlib_module("math"), true, "registry has math")
assert_eq(stdlib.is_stdlib_module("io"), true, "registry has io")
assert_eq(stdlib.is_stdlib_module("string"), true, "registry has string")
assert_eq(stdlib.is_stdlib_module("sys"), true, "registry has sys")
assert_eq(stdlib.is_stdlib_module("nonexistent"), false, "registry no nonexistent")

let math_mod = stdlib.get_stdlib_module("math")
assert_true(math_mod != nil, "get math module")
assert_near(math_mod["pi"], 3.14159, 0.001, "registry math.pi")

assert_eq(stdlib.get_stdlib_module("nonexistent"), nil, "get nonexistent = nil")

print ""
print "Stdlib tests: " + str(passed) + " passed, " + str(failed) + " failed"
if failed == 0:
    print "All stdlib tests passed!"
