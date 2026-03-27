# Conformance: Operator Precedence (Spec §4)
# EXPECT: 14
# EXPECT: 20
# EXPECT: true
# EXPECT: true
# EXPECT: 7
# * before +
print 2 + 3 * 4
# Parentheses override
print (2 + 3) * 4
# Comparison and boolean
let x = 5
print x > 3 and x < 10
# Boolean operators
print true or false
# Bitwise operators
print 3 | 4
