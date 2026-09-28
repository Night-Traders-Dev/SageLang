# EXPECT: int_add: 30
# EXPECT: float_add: 7.5
# EXPECT: str_concat: hello world
# EXPECT: arr_len: 3

proc add_typed(a, b):
    return a + b

print "int_add: " + str(add_typed(10, 20))
print "float_add: " + str(add_typed(2.5, 5.0))
print "str_concat: " + add_typed("hello ", "world")

let arr = [1, 2, 3]
print "arr_len: " + str(len(arr))
