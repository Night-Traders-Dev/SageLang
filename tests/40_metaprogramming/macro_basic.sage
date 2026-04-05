# EXPECT: starting timer
# EXPECT: timer result: 45
# EXPECT: ending timer
# Test macro definitions (treated as procs in interpreter mode)

macro timed(label):
    print "starting " + label
    let result = 0
    for i in range(10):
        result = result + i
    print label + " result: " + str(result)
    print "ending " + label

timed("timer")
