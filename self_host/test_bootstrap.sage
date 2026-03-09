gc_disable()
# -----------------------------------------
# test_bootstrap.sage - Comprehensive bootstrap test
# Runs various programs through the self-hosted interpreter
# -----------------------------------------

import io
import sys
from parser import parse_source
from interpreter import new_interpreter, exec_program

let nl = chr(10)
let passed = 0
let failed = 0
let total = 0

proc run_test(name, source, expected):
    let genv = new_interpreter()
    let stmts = parse_source(source)
    # Capture output by running and checking
    # For now, just verify it doesn't crash
    let crashed = false
    try:
        exec_program(genv, stmts)
    catch e:
        crashed = true
        print "  FAIL " + name + " (crashed: " + str(e) + ")"
    if not crashed:
        print "  PASS " + name

proc main():
    print "Bootstrap Tests"
    print "==============="
    let pass_count = 0
    let total = 0

    # --- Arithmetic ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let stmts = parse_source("let x = 2 + 3 * 4" + nl)
        exec_program(genv, stmts)
        print "  PASS arithmetic"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL arithmetic: " + str(e)

    # --- Variables and assignment ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let x = 10" + nl + "x = x + 5" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS variables"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL variables: " + str(e)

    # --- If/else ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let x = 10" + nl + "if x > 5:" + nl + "    let y = 1" + nl + "else:" + nl + "    let y = 2" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS if/else"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL if/else: " + str(e)

    # --- While loop ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let i = 0" + nl + "while i < 5:" + nl + "    i = i + 1" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS while loop"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL while loop: " + str(e)

    # --- For loop ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let total = 0" + nl + "for i in range(5):" + nl + "    total = total + i" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS for loop"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL for loop: " + str(e)

    # --- Functions ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "proc add(a, b):" + nl + "    return a + b" + nl + "let r = add(3, 4)" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS functions"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL functions: " + str(e)

    # --- Recursion ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "proc fact(n):" + nl + "    if n <= 1:" + nl + "        return 1" + nl + "    return n * fact(n - 1)" + nl + "let r = fact(10)" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS recursion"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL recursion: " + str(e)

    # --- Closures ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "proc make():" + nl + "    let x = 0" + nl + "    proc inc():" + nl + "        x = x + 1" + nl + "        return x" + nl + "    return inc" + nl + "let c = make()" + nl + "let r = c()" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS closures"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL closures: " + str(e)

    # --- Classes ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "class Foo:" + nl + "    proc init(x):" + nl + "        self.x = x" + nl + "    proc get():" + nl + "        return self.x" + nl + "let f = Foo(42)" + nl + "let r = f.get()" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS classes"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL classes: " + str(e)

    # --- Inheritance ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "class Animal:" + nl + "    proc init(name):" + nl + "        self.name = name" + nl + "    proc speak():" + nl + "        return self.name" + nl + "class Dog(Animal):" + nl + "    proc init(name):" + nl + "        self.name = name" + nl + "    proc speak():" + nl + "        return self.name" + nl + "let d = Dog(" + chr(34) + "Rex" + chr(34) + ")" + nl + "let r = d.speak()" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS inheritance"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL inheritance: " + str(e)

    # --- Arrays ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let a = [1, 2, 3]" + nl + "push(a, 4)" + nl + "let r = len(a)" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS arrays"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL arrays: " + str(e)

    # --- Dicts ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let d = {}" + nl + "d[" + chr(34) + "a" + chr(34) + "] = 1" + nl + "let r = len(dict_keys(d))" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS dicts"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL dicts: " + str(e)

    # --- Strings ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let s = " + chr(34) + "hello world" + chr(34) + nl + "let r = upper(s)" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS strings"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL strings: " + str(e)

    # --- Try/Catch ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let caught = false" + nl + "try:" + nl + "    raise " + chr(34) + "oops" + chr(34) + nl + "catch e:" + nl + "    caught = true" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS try/catch"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL try/catch: " + str(e)

    # --- Break/Continue ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let total = 0" + nl + "for i in range(10):" + nl + "    if i == 5:" + nl + "        break" + nl + "    total = total + i" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS break/continue"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL break/continue: " + str(e)

    # --- Nested functions ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "proc outer():" + nl + "    proc inner(x):" + nl + "        return x * 2" + nl + "    return inner(21)" + nl + "let r = outer()" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS nested functions"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL nested functions: " + str(e)

    # --- Boolean ops ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let src = "let a = true and false" + nl + "let b = true or false" + nl + "let c = not true" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS boolean ops"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL boolean ops: " + str(e)

    # --- String builtins ---
    total = total + 1
    try:
        let genv = new_interpreter()
        let q = chr(34)
        let src = "let s = " + q + "Hello World" + q + nl + "let r1 = split(s, " + q + " " + q + ")" + nl + "let r2 = join(r1, " + q + "-" + q + ")" + nl
        let stmts = parse_source(src)
        exec_program(genv, stmts)
        print "  PASS string builtins"
        pass_count = pass_count + 1
    catch e:
        print "  FAIL string builtins: " + str(e)

    # --- Print ---
    print ""
    print str(pass_count) + "/" + str(total) + " bootstrap tests passed"
    if pass_count == total:
        print "All bootstrap tests passed!"

main()
