# Conformance: Coercion (Spec §7)
# Int + Float = Float, Int / Int = Float, % preserves float
# EXPECT: 5.5
# EXPECT: 2.5
# EXPECT: 0.7
# EXPECT: 3
# Mixed arithmetic
print 3 + 2.5
# Division always returns float
print 5 / 2
# Modulo preserves float
print 3.7 % 1.5
# Integer ops return int
print 1 + 2
