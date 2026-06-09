# EXPECT: 0.7
# EXPECT: 0.5
# EXPECT: 1
# EXPECT: 0
# Float modulo preserves float semantics
print 3.7 % 1.5
print 2.5 % 1
# Integer modulo still works
print 7 % 3
print 10 % 5
