# Test for loops with range
print "Counting 0 to 4:"
for i in range(5):
    print i

print ""
print "Array iteration:"
let arr = [10, 20, 30, 40, 50]
for val in arr:
    print val

print ""
print "Sum array:"
let total = 0
for num in arr:
    let total = total + num
print "Total:"
print total

print ""
print "Nested loops:"
for i in range(3):
    for j in range(3):
        print i