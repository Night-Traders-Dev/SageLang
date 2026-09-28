# RUN: bytecode-run
# EXPECT: 200
# EXPECT: 103
# EXPECT: 6
# EXPECT: 12
# EXPECT: x/5/t
# EXPECT: x/9/t
# EXPECT: x/9/z
# EXPECT: 7
# A top-level function called with fewer arguments than it declares used to be
# rejected outright: "Arity mismatch", which halted the program.
#
# The VM's entry point used to parse and execute one statement at a time, so the
# compiler only ever saw the statement it was compiling and never a procedure
# declared further down the file -- and it cannot learn a callee's signature
# after the fact, because BytecodeFunction carries only parameter *names* and is
# serialised into the .svm artifact. run() in main.c now parses the whole program
# first and registers every signature, so the compiler can substitute defaults at
# the call site exactly as the C backend does.
#
# Constructors are padded too, and needed an off-by-one guard: a constructor's
# parameter 0 is `self`, supplied implicitly, so the call's arguments occupy
# parameters 1..N. Padding from 0 put a stray NIL in the first real parameter and
# shifted every value, which surfaced as "string + number".

proc two(a: Int, b: Int = 99, c: Int = 100) -> Int:
    return a + b + c

print(str(two(1)))
print(str(two(1, 2)))
print(str(two(1, 2, 3)))

# All parameters defaulted, called with none.
proc none_defaulted(a: Int = 4, b: Int = 3) -> Int:
    return a * b

print(str(none_defaulted()))

class Sized:
    proc init(self, name: String, size: Int = 5, tag: String = "t"):
        self.n = name
        self.s = size
        self.t = tag

    proc show(self) -> String:
        return self.n + "/" + str(self.s) + "/" + self.t

print(Sized("x").show())
print(Sized("x", 9).show())
print(Sized("x", 9, "z").show())

# Omitting a *required* parameter must still be an error, not a silent nil.
proc needs_two(a: Int, b: Int) -> Int:
    return a + b

print(str(needs_two(1, 6)))
