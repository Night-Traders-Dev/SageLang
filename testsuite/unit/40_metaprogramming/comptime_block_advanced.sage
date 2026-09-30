# EXPECT: factorial 5 = 120
# EXPECT: fibonacci 10 = 55
# EXPECT: comptime array sum = 150

comptime:
    let fact = 1
    for i in range(1, 6):
        fact = fact * i
    print "factorial 5 = " + str(fact)

comptime:
    let a = 0
    let b = 1
    for i in range(10):
        let temp = a + b
        a = b
        b = temp
    print "fibonacci 10 = " + str(a)

comptime:
    let arr = [10, 20, 30, 40, 50]
    let total = 0
    for x in arr:
        total = total + x
    print "comptime array sum = " + str(total)
