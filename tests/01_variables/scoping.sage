# EXPECT: outer
# EXPECT: inner
# EXPECT: outer
var x = "outer"
print(x)
proc test():
    var x = "inner"
    print(x)
test()
print(x)
