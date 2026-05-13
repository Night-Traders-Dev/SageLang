# EXPECT: Point(3, 4)
# EXPECT: true
# EXPECT: false
# Test __str__ and __eq__ hooks
class Point:
    proc init(self, x, y):
        self.x = x
        self.y = y
    proc __str__(self):
        return "Point(" + str(self.x) + ", " + str(self.y) + ")"
    proc __eq__(self, other):
        return self.x == other.x and self.y == other.y

let p1 = Point(3, 4)
let p2 = Point(3, 4)
let p3 = Point(5, 6)
print p1
print p1 == p2
print p1 == p3
