# EXPECT: base
# EXPECT: child
class Base:
    proc who(self):
        return "base"
class Child(Base):
    proc who(self):
        return "child"
let b = Base()
let c = Child()
print(b.who())
print(c.who())
