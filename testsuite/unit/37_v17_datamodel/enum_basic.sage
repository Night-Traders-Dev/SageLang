# EXPECT: 0
# EXPECT: 1
# EXPECT: 2
# EXPECT: Direction
# Test enum declaration
enum Color:
    Red
    Green
    Blue

print Color["Red"]
print Color["Green"]
print Color["Blue"]

enum Direction:
    North
    South
    East
    West

print Direction["__name__"]
