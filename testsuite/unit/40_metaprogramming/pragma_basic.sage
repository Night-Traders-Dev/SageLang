# EXPECT: 30
# EXPECT: packed struct done
# EXPECT: section test done
# Test @pragma decorators on procs and structs

# @inline pragma on a proc
@inline
proc fast_multiply(x, y):
    return x * y

print fast_multiply(5, 6)

# @packed pragma on a struct
@packed
struct PackedPoint:
    x: Int
    y: Int

print "packed struct done"

# @section pragma with argument
@section(".text")
proc entry_point():
    return 42

entry_point()
print "section test done"
