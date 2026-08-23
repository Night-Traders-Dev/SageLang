let calls = []
proc side(name, val):
    push(calls, name)
    return val
if side("a", false) and side("b", true):
    print "then"
else:
    print "else"
print calls
if side("c", true) or side("d", false):
    print "or-then"
print calls
print not true
print 5 > 3 and 2 < 4
