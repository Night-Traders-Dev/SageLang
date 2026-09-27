# RUN: bytecode-run
# EXPECT: 7
# EXPECT: 7
# EXPECT: a
# EXPECT: b
# EXPECT: c
# EXPECT: 6
# EXPECT: 3
# EXPECT: 3
# EXPECT: 3
# EXPECT: 42
# EXPECT: 42
# EXPECT: inner
# EXPECT: inner
# A `let` in a top-level `for` body used to read the loop's own iterable
# instead of the assigned value.
#
# Locals are addressed as absolute indices into the frame's slot array, which
# is only meaningful in a function body (there frame->slots points at the
# argument block). The top-level chunk points frame->slots at the bottom of the
# VM stack, so any local allocated in a top-level block aliased whatever the
# chunk had already pushed -- and inside a `for` loop that is the iterable.
# So `let r = 7` bound `r` to ["a", "b"], and the 7 was silently dropped.
#
# This silently corrupted any bytecode-mode program with a top-level loop
# containing a `let`, which is why it went unnoticed: the C backend was always
# correct, and the unit suite mostly exercises that one.

# A plain constant: slot 0 is the array being iterated.
for p in ["a", "b"]:
    let r = 7
    print(r)

# The loop variable itself must still be the element, not the array.
for p in ["a", "b", "c"]:
    print(p)

# Accumulating across iterations.
var total: Int = 0
for p in ["a", "b", "c"]:
    let step: Int = 2
    total = total + step
print(total)

# Function bodies are unaffected -- locals are valid there and must stay so.
proc work(items: Array[String]) -> Int:
    var acc: Int = 0
    for it in items:
        let one: Int = 1
        acc = acc + one
    return acc
print(work(["a", "b", "c"]))

# Methods likewise.
class Counter:
    proc init(self):
        self.n = 0

    proc go(self, items: Array[String]) -> Int:
        for it in items:
            let one: Int = 1
            self.n = self.n + one
        return self.n
print(Counter().go(["a", "b", "c"]))

# while loops were never affected, and must stay correct.
var w: Int = 0
var j: Int = 0
while j < 3:
    let inc: Int = 1
    w = w + inc
    j = j + 1
print(w)

# A method call in a loop body must return its own result, not the iterable.
class Tagger:
    proc init(self):
        self.n = 0

    proc tag(self, s: String) -> Int:
        self.n = self.n + 1
        return 42
for p in ["a", "b"]:
    let got = Tagger().tag(p)
    print(got)

# A loop nested inside a top-level block hit the same path, because the block
# is what raised scope_depth in the first place.
if true:
    for p in ["a", "b"]:
        let inner: String = "inner"
        print(inner)
