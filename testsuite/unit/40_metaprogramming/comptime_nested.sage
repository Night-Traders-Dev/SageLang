# EXPECT: nested comptime sum: 120
# EXPECT: nested factorial: 3628800

comptime:
    let factorials = [1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800]
    let total = 0
    for f in range(1, 16):
        total = total + f
    print "nested comptime sum: " + str(total)
    print "nested factorial: " + str(factorials[9])
