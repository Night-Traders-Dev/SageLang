# RUN: bytecode-run
# EXPECT: x/5/t
# EXPECT: x/9/t
# EXPECT: x/9/z
# EXPECT: 42
# EXPECT: 200
# Default arguments were never applied when calling a method or constructing a
# class under the bytecode VM.
#
# call_any_method() bound only the parameters the caller actually supplied, so
# the rest were left undefined in the method environment. Reading one raised
# "Undefined variable" -- and, where a second filesystem object was constructed
# over a live one, walking an undefined binding could segfault. A class with
# defaulted parameters could not be constructed at all.
#
# VFS.init in SageFS has 18 defaulted parameters, which is where the per-
# construction error spew came from: one error per omitted parameter, every time.
#
# A *top-level function* is a separate case and still fails. The VM's entry point
# parses and executes one statement at a time, so the compiler never sees a
# declaration that has not been parsed yet and cannot substitute a default at the
# call site. That one is not fixed; it is asserted below so the gap stays visible
# rather than being forgotten.

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

# A default that is not nil, so a missing binding cannot masquerade as correct.
class Sized2:
    proc init(self, base: Int, addend: Int = 37):
        self.total = base + addend

    proc total(self) -> Int:
        return self.total

print(str(Sized2(5).total()))

# A class whose constructor takes many defaults, as VFS.init does.
class Wide:
    proc init(self, first: String,
              a: Any = nil, b: Any = nil, c: Any = nil, d: Any = nil,
              e: Any = nil, f: Any = nil, g: Any = nil, h: Any = nil):
        self.first = first
        self.n = 0
        if a != nil: self.n = self.n + 1
        if b != nil: self.n = self.n + 1
        if c != nil: self.n = self.n + 1
        if d != nil: self.n = self.n + 1
        if e != nil: self.n = self.n + 1
        if f != nil: self.n = self.n + 1
        if g != nil: self.n = self.n + 1
        if h != nil: self.n = self.n + 1

    proc count(self) -> Int:
        return self.n

let w = Wide("x")
## Every omitted default is nil, so count() is 0 and this prints 200. If the
## defaults were not applied the count would be wrong -- or reading them would
## have raised "Undefined variable" before reaching here.
print(str(200 - w.count()))
