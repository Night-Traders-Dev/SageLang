# EXPECT: 1
# EXPECT: 2
# EXPECT: 3
proc make_counter():
    var count = 0
    proc inc():
        count = count + 1
        return count
    return inc
let counter = make_counter()
print(counter())
print(counter())
print(counter())
