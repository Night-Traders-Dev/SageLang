# Test -> arrow operator (alias for .)
# EXPECT: 3
# EXPECT: 7
# EXPECT: 10
# EXPECT: 20
# EXPECT: (1, 2, 3)

class Point:
    proc init(self, x, y):
        self.x = x
        self.y = y

let p = Point(3, 7)

# Arrow for get
print p->x
print p->y

# Arrow for set
p->x = 10
p->y = 20
print p->x
print p->y

# Arrow with method call
class Vec3:
    proc init(self, x, y, z):
        self->x = x
        self->y = y
        self->z = z
    proc to_string(self):
        return "(" + str(self->x) + ", " + str(self->y) + ", " + str(self->z) + ")"

let v = Vec3(1, 2, 3)
print v->to_string()
