# EXPECT: one
# EXPECT: two
# EXPECT: three
# Test elif without trailing else (known elif+else fallthrough issue)
proc test(x):
    if x == 1:
        print("one")
    elif x == 2:
        print("two")
    elif x == 3:
        print("three")
test(1)
test(2)
test(3)
