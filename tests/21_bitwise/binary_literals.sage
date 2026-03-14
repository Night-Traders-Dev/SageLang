# Test binary integer literals with bitwise operators
# EXPECT: 0
# EXPECT: 17
# EXPECT: 57344
# EXPECT: 57461

print 0b000
print (0b000 << 13) | 17
print 0b111 << 13
print (0b111 << 13) | (0b011 << 5) | 0b10101
