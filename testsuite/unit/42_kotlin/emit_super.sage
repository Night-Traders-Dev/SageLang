## Test: Kotlin backend — super calls with proper dispatch
## Run: sage --emit-kotlin tests/42_kotlin/emit_super.sage

class Shape:
    proc init(self, name):
        self.name = name
    proc describe(self):
        return "Shape: " + self.name
    proc area(self):
        return 0

class Circle(Shape):
    proc init(self, radius):
        super.init("circle")
        self.radius = radius
    proc describe(self):
        return super.describe() + " r=" + str(self.radius)
    proc area(self):
        return 3.14159 * self.radius * self.radius

let c = Circle(5)
print(c.describe())
print(c.area())
