# EXPECT: aligned struct created
# EXPECT: 100
# Test pragma with arguments

@align("16")
struct AlignedData:
    value: Int

let d = AlignedData(100)
print "aligned struct created"
print d.value
