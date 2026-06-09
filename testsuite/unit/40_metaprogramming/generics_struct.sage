# EXPECT: 10
# EXPECT: hello
# Test generic type parameters on structs (parsed, dynamic semantics)

struct Wrapper[T]:
    value: T

let w1 = Wrapper(10)
print w1.value

let w2 = Wrapper("hello")
print w2.value
