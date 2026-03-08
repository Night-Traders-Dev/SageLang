# EXPECT: 0
# EXPECT: 1
# EXPECT: 2
# EXPECT: 3
# EXPECT: 4
proc count_up(n):
    var i = 0
    while i < n:
        yield i
        i = i + 1
let g = count_up(5)
var val = next(g)
while val != nil:
    print(val)
    val = next(g)
