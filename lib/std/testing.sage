gc_disable()
# Testing framework with test runner, assertions, and reporting

# ============================================================================
# Test suite
# ============================================================================

proc create_suite(name):
    let suite = {}
    suite["name"] = name
    suite["tests"] = []
    suite["passed"] = 0
    suite["failed"] = 0
    suite["errors"] = []
    suite["current_test"] = ""
    return suite

# Register a test case
proc add_test(suite, name, test_fn):
    let test_case = {}
    test_case["name"] = name
    test_case["fn"] = test_fn
    push(suite["tests"], test_case)

# Run all tests in the suite
proc run(suite):
    let tests = suite["tests"]
    for i in range(len(tests)):
        suite["current_test"] = tests[i]["name"]
        try:
            tests[i]["fn"]()
            suite["passed"] = suite["passed"] + 1
        catch e:
            suite["failed"] = suite["failed"] + 1
            let err = {}
            err["test"] = tests[i]["name"]
            err["message"] = e
            push(suite["errors"], err)
    return suite

# Print test results
proc report(suite):
    let nl = chr(10)
    let total = suite["passed"] + suite["failed"]
    print "=== " + suite["name"] + " ==="
    print str(suite["passed"]) + " passed, " + str(suite["failed"]) + " failed / " + str(total) + " total"
    if suite["failed"] > 0:
        let errors = suite["errors"]
        for i in range(len(errors)):
            print "  FAIL: " + errors[i]["test"] + " - " + errors[i]["message"]
    if suite["failed"] == 0:
        print "All tests passed!"

# ============================================================================
# Assertions
# ============================================================================

proc assert_true(value, message):
    if not value:
        raise "assert_true failed: " + message

proc assert_false(value, message):
    if value:
        raise "assert_false failed: " + message

proc assert_equal(actual, expected, message):
    if actual != expected:
        raise "assert_equal failed: " + message + " (expected " + str(expected) + ", got " + str(actual) + ")"

proc assert_not_equal(actual, not_expected, message):
    if actual == not_expected:
        raise "assert_not_equal failed: " + message

proc assert_nil(value, message):
    if value != nil:
        raise "assert_nil failed: " + message

proc assert_not_nil(value, message):
    if value == nil:
        raise "assert_not_nil failed: " + message

proc assert_greater(a, b, message):
    if a <= b:
        raise "assert_greater failed: " + message + " (" + str(a) + " <= " + str(b) + ")"

proc assert_less(a, b, message):
    if a >= b:
        raise "assert_less failed: " + message + " (" + str(a) + " >= " + str(b) + ")"

proc assert_close(actual, expected, tolerance, message):
    let diff = actual - expected
    if diff < 0:
        diff = 0 - diff
    if diff > tolerance:
        raise "assert_close failed: " + message + " (diff=" + str(diff) + ")"

proc assert_contains(haystack, needle, message):
    let found = false
    if type(haystack) == "string":
        for i in range(len(haystack) - len(needle) + 1):
            if not found:
                let sub_match = true
                for j in range(len(needle)):
                    if haystack[i + j] != needle[j]:
                        sub_match = false
                if sub_match:
                    found = true
    if type(haystack) == "array":
        for i in range(len(haystack)):
            if not found and haystack[i] == needle:
                found = true
    if not found:
        raise "assert_contains failed: " + message

proc assert_raises(fn, message):
    let raised = false
    try:
        fn()
    catch e:
        raised = true
    if not raised:
        raise "assert_raises failed: " + message + " (no exception raised)"

proc assert_array_equal(actual, expected, message):
    if len(actual) != len(expected):
        raise "assert_array_equal failed: " + message + " (length " + str(len(actual)) + " != " + str(len(expected)) + ")"
    for i in range(len(actual)):
        if actual[i] != expected[i]:
            raise "assert_array_equal failed: " + message + " (index " + str(i) + ": " + str(actual[i]) + " != " + str(expected[i]) + ")"

# ============================================================================
# Benchmark helper
# ============================================================================

proc benchmark(name, fn, iterations):
    let start = clock()
    for i in range(iterations):
        fn()
    let elapsed = clock() - start
    let per_iter = elapsed / iterations
    print name + ": " + str(iterations) + " iterations in " + str(elapsed) + "s (" + str(per_iter * 1000) + "ms/iter)"
    let result = {}
    result["name"] = name
    result["iterations"] = iterations
    result["total_seconds"] = elapsed
    result["per_iteration"] = per_iter
    return result
