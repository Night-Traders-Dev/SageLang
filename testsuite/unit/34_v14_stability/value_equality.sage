# EXPECT: true
# EXPECT: false
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: true
# Array equality
let a = [1, 2, 3]
let b = [1, 2, 3]
let c = [1, 2, 4]
print a == b
print a == c

# Instance equality
class Point:
    proc init(self, x, y):
        self.x = x
        self.y = y

let p1 = Point(1, 2)
let p2 = Point(1, 2)
let p3 = Point(3, 4)
print p1 == p2
print p1 == p1
print p1 == p3

# append works (unified with push)
let arr = []
append(arr, 42)
print len(arr) == 1
