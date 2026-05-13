# EXPECT: 6
# EXPECT: a-b-c
proc sum3(a, b, c):
    return a + b + c
print(sum3(1, 2, 3))
proc join3(a, b, c):
    return a + "-" + b + "-" + c
print(join3("a", "b", "c"))
