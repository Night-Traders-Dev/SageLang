# EXPECT: 42
# EXPECT: hello
# EXPECT: [1, 2, 3]
# EXPECT: 7
# EXPECT: hi World
# Type annotations on let statements
let x: Int = 42
let name: String = "hello"
let items: Array[Int] = [1, 2, 3]
print x
print name
print items

# Type annotations on proc params and return type
proc add(a: Int, b: Int) -> Int:
    return a + b

print add(3, 4)

# Mixed typed and untyped params with defaults
proc greet(greeting: String, name: String = "World") -> String:
    return greeting + " " + name

print greet("hi")
