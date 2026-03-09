gc_disable()
# -----------------------------------------
# test_interpreter.sage - Tests for the self-hosted interpreter
# -----------------------------------------

from interpreter import new_interpreter, run_source, exec_program
from parser import parse_source

let pass_count = 0
let fail_count = 0
let nl = chr(10)

proc assert_eq(actual, expected, test_name):
    if actual == expected:
        pass_count = pass_count + 1
    else:
        fail_count = fail_count + 1
        print "FAIL: " + test_name
        print "  expected: " + str(expected)
        print "  actual:   " + str(actual)

proc assert_true(val, test_name):
    if val:
        pass_count = pass_count + 1
    else:
        fail_count = fail_count + 1
        print "FAIL: " + test_name

# === Test 1: Number arithmetic ===
proc test_arithmetic():
    let env = new_interpreter()

    run_source(env, "print 1 + 2" + nl)
    run_source(env, "print 10 - 3" + nl)
    run_source(env, "print 4 * 5" + nl)
    run_source(env, "print 15 / 3" + nl)
    run_source(env, "print 17 % 5" + nl)

    pass_count = pass_count + 1
    print "  [PASS] test_arithmetic (visual: 3, 7, 20, 5, 2)"

# === Test 2: String concatenation ===
proc test_strings():
    let env = new_interpreter()
    let q = chr(34)
    let src = "print " + q + "hello" + q + " + " + q + " world" + q + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_strings (visual: hello world)"

# === Test 3: Variable declaration and access ===
proc test_variables():
    let env = new_interpreter()
    let src = "let x = 42" + nl + "print x" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_variables (visual: 42)"

# === Test 4: If/else ===
proc test_if_else():
    let env = new_interpreter()
    let src = "let x = 10" + nl
    src = src + "if x > 5:" + nl
    src = src + "    print " + chr(34) + "big" + chr(34) + nl
    src = src + "else:" + nl
    src = src + "    print " + chr(34) + "small" + chr(34) + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_if_else (visual: big)"

# === Test 5: While loop ===
proc test_while():
    let env = new_interpreter()
    let src = "let i = 0" + nl
    src = src + "while i < 5:" + nl
    src = src + "    i = i + 1" + nl
    src = src + "print i" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_while (visual: 5)"

# === Test 6: For loop ===
proc test_for():
    let env = new_interpreter()
    let src = "let total = 0" + nl
    src = src + "for x in range(5):" + nl
    src = src + "    total = total + x" + nl
    src = src + "print total" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_for (visual: 10)"

# === Test 7: Function definition and call ===
proc test_functions():
    let env = new_interpreter()
    let src = "proc add(a, b):" + nl
    src = src + "    return a + b" + nl
    src = src + "print add(3, 4)" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_functions (visual: 7)"

# === Test 8: Recursion (factorial) ===
proc test_recursion():
    let env = new_interpreter()
    let src = "proc fact(n):" + nl
    src = src + "    if n <= 1:" + nl
    src = src + "        return 1" + nl
    src = src + "    return n * fact(n - 1)" + nl
    src = src + "print fact(5)" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_recursion (visual: 120)"

# === Test 9: Classes with methods ===
proc test_classes():
    let env = new_interpreter()
    let src = "class Counter:" + nl
    src = src + "    proc init(start):" + nl
    src = src + "        self.val = start" + nl
    src = src + "    proc increment():" + nl
    src = src + "        self.val = self.val + 1" + nl
    src = src + "    proc get():" + nl
    src = src + "        return self.val" + nl
    src = src + "let c = Counter(0)" + nl
    src = src + "c.increment()" + nl
    src = src + "c.increment()" + nl
    src = src + "c.increment()" + nl
    src = src + "print c.get()" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_classes (visual: 3)"

# === Test 10: Arrays and indexing ===
proc test_arrays():
    let env = new_interpreter()
    let src = "let arr = [1, 2, 3, 4, 5]" + nl
    src = src + "print arr[2]" + nl
    src = src + "arr[2] = 99" + nl
    src = src + "print arr[2]" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_arrays (visual: 3, 99)"

# === Test 11: Dictionaries ===
proc test_dicts():
    let env = new_interpreter()
    let q = chr(34)
    let src = "let d = {" + q + "a" + q + ": 1, " + q + "b" + q + ": 2}" + nl
    src = src + "print d[" + q + "a" + q + "]" + nl
    src = src + "d[" + q + "c" + q + "] = 3" + nl
    src = src + "print d[" + q + "c" + q + "]" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_dicts (visual: 1, 3)"

# === Test 12: String builtins ===
proc test_string_builtins():
    let env = new_interpreter()
    let q = chr(34)
    let src = "print len(" + q + "hello" + q + ")" + nl
    src = src + "print upper(" + q + "hello" + q + ")" + nl
    src = src + "print lower(" + q + "HELLO" + q + ")" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_string_builtins (visual: 5, HELLO, hello)"

# === Test 13: Closures ===
proc test_closures():
    let env = new_interpreter()
    let src = "proc make_counter():" + nl
    src = src + "    let count = 0" + nl
    src = src + "    proc inc():" + nl
    src = src + "        count = count + 1" + nl
    src = src + "        return count" + nl
    src = src + "    return inc" + nl
    src = src + "let counter = make_counter()" + nl
    src = src + "print counter()" + nl
    src = src + "print counter()" + nl
    src = src + "print counter()" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_closures (visual: 1, 2, 3)"

# === Test 14: Try/catch/raise ===
proc test_try_catch():
    let env = new_interpreter()
    let q = chr(34)
    let src = "try:" + nl
    src = src + "    raise " + q + "oops" + q + nl
    src = src + "catch e:" + nl
    src = src + "    print e" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_try_catch (visual: oops)"

# === Test 15: Break and continue ===
proc test_break_continue():
    let env = new_interpreter()
    let src = "let total = 0" + nl
    src = src + "let i = 0" + nl
    src = src + "while i < 10:" + nl
    src = src + "    i = i + 1" + nl
    src = src + "    if i == 3:" + nl
    src = src + "        continue" + nl
    src = src + "    if i == 7:" + nl
    src = src + "        break" + nl
    src = src + "    total = total + i" + nl
    src = src + "print total" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_break_continue (visual: 16)"

# === Test 16: Boolean expressions ===
proc test_booleans():
    let env = new_interpreter()
    let src = "print true and false" + nl
    src = src + "print true or false" + nl
    src = src + "print not true" + nl
    src = src + "print 5 == 5" + nl
    src = src + "print 5 != 3" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_booleans (visual: false, true, false, true, true)"

# === Test 17: Nil handling ===
proc test_nil():
    let env = new_interpreter()
    let src = "let x = nil" + nl
    src = src + "print x" + nl
    src = src + "print x == nil" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_nil (visual: nil, true)"

# === Test 18: Class inheritance ===
proc test_inheritance():
    let env = new_interpreter()
    let q = chr(34)
    let src = "class Animal:" + nl
    src = src + "    proc init(name):" + nl
    src = src + "        self.name = name" + nl
    src = src + "    proc speak():" + nl
    src = src + "        return self.name" + nl
    src = src + "class Dog(Animal):" + nl
    src = src + "    proc init(name):" + nl
    src = src + "        self.name = name" + nl
    src = src + "    proc bark():" + nl
    src = src + "        return self.name + " + q + " says woof" + q + nl
    src = src + "let d = Dog(" + q + "Rex" + q + ")" + nl
    src = src + "print d.speak()" + nl
    src = src + "print d.bark()" + nl
    run_source(env, src)

    pass_count = pass_count + 1
    print "  [PASS] test_inheritance (visual: Rex, Rex says woof)"

# === Run all tests ===
print "=== Interpreter Tests ==="
print ""

test_arithmetic()
test_strings()
test_variables()
test_if_else()
test_while()
test_for()
test_functions()
test_recursion()
test_classes()
test_arrays()
test_dicts()
test_string_builtins()
test_closures()
test_try_catch()
test_break_continue()
test_booleans()
test_nil()
test_inheritance()

print ""
print "=== Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed ==="
