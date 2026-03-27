# EXPECT: Adds two numbers.
# EXPECT: 7
# EXPECT: true
## Adds two numbers.
proc add(a, b):
    return a + b

print doc(add)
print add(3, 4)

# Undocumented function returns nil doc
proc mul(a, b):
    return a * b

print doc(mul) == nil
