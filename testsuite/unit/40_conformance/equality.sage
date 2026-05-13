# Conformance: Equality (Spec §11)
# Value equality for all types.
# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: true
# EXPECT: false
# EXPECT: true
# Nil
print nil == nil
# Bool
print true == true
# Number
print 42 == 42
# String
print "hello" == "hello"
# Array (structural)
print [1, 2, 3] == [1, 2, 3]
print [1, 2] == [1, 3]
# Instance (structural)
class Point:
    proc init(self, x, y):
        self.x = x
        self.y = y
print Point(1, 2) == Point(1, 2)
