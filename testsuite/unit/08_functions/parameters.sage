# EXPECT: 7
# EXPECT: hello world
proc add(a, b):
    return a + b
print(add(3, 4))
proc greet(name):
    return "hello " + name
print(greet("world"))
