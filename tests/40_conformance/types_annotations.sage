# Conformance: Type Annotations (Spec §6, §13)
# EXPECT: 7
# EXPECT: hello world
# EXPECT: 3
# Typed proc with return type
proc add(a: Int, b: Int) -> Int:
    return a + b
print add(3, 4)

# Typed let with default
proc greet(name: String = "world") -> String:
    return "hello " + name
print greet()

# Typed collections
let items: Array[Int] = [1, 2, 3]
print len(items)
