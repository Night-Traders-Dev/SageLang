# EXPECT: 3
# EXPECT: 4
# EXPECT: hello
# Test struct as value type with auto-init
struct Point:
    x: Int
    y: Int

let p = Point(3, 4)
print p.x
print p.y

struct Config:
    name: String
    value: Int

let c = Config("hello", 42)
print c.name
