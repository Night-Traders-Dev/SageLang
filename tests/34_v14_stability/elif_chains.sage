# EXPECT: seven
# EXPECT: other
# EXPECT: one
# Test long elif chain (8 branches - previously broken at 5+)
let x = 7
if x == 1:
    print "one"
elif x == 2:
    print "two"
elif x == 3:
    print "three"
elif x == 4:
    print "four"
elif x == 5:
    print "five"
elif x == 6:
    print "six"
elif x == 7:
    print "seven"
elif x == 8:
    print "eight"
else:
    print "other"

# Test fallthrough to else
let y = 99
if y == 1:
    print "one"
elif y == 2:
    print "two"
elif y == 3:
    print "three"
elif y == 4:
    print "four"
elif y == 5:
    print "five"
else:
    print "other"

# Test first branch
let z = 1
if z == 1:
    print "one"
elif z == 2:
    print "two"
elif z == 3:
    print "three"
