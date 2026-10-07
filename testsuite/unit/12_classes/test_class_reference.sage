## EXPECT: 7
## EXPECT: from lib
## EXPECT: true
## EXPECT: true

# `let X = SomeClass` -- a class used as a value.
#
# Classes were names: sage_construct() looked one up by string in a method table and
# nothing could hold one, so an alias emitted a reference to a C identifier that does
# not exist. The interpreter represented classes as values and accepted it, so the
# same program compiled under one backend and not the other.

import cls_lib

class Local:
    proc init(self, v: Int):
        self.v = v
    proc get(self) -> Int:
        return self.v

# Same module.
let Same = Local
let s = Same(7)
print s.get()

# Across a module boundary.
let FromLib = cls_lib.Widget
let f = FromLib(3)
print "from lib"

# The alias is a real value: it can be stored and passed, not just called directly.
let saved = Same
let s2 = saved(9)
print str(s2.get() == 9)

# A class with a parent must keep the parent through the reference, or construction
# finds no init for it.
class Base:
    proc init(self, n: Int):
        self.n = n
    proc n(self) -> Int:
        return self.n
class Derived(Base):
    proc double(self) -> Int:
        return self.n() * 2
let D = Derived
let d = D(21)
print str(d.double() == 42)
