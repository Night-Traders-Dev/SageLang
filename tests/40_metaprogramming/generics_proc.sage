# EXPECT: 10
# EXPECT: hello
# EXPECT: [1, 2, 3]
# Test generic type parameters on procs (type params parsed, semantics are dynamic)

proc identity[T](x):
    return x

print identity(10)
print identity("hello")
print identity([1, 2, 3])
