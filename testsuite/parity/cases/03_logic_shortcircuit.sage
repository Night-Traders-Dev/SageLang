let calls = []
proc side(name, val):
    push(calls, name)
    return val
end
if side("a", false) and side("b", true):
    print "then"
else:
    print "else"
end
print calls
if side("c", true) or side("d", false):
    print "or-then"
end
print calls
print not true
print 5 > 3 and 2 < 4
