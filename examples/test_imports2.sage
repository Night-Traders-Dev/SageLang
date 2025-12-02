# Phase 8: Import System Test
# Test all three forms of imports

print "=== Testing Import System ==="
print ""

# Test 1: Import entire module
print "Test 1: import math"
from math import sqrt, abs, pow

let val = 16
let result = sqrt(val)
print "sqrt(16) ="
print result

let neg = abs(0 - 5)
print "abs(-5) ="
print neg

let power = pow(2, 3)
print "pow(2, 3) ="
print power

print ""

# Test 2: Import from module
print "Test 2: from utils import is_even, clamp"
from utils import is_even, clamp

let check = is_even(4)
print "is_even(4) ="
print check

let clamped = clamp(15, 0, 10)
print "clamp(15, 0, 10) ="
print clamped

print ""
print "=== All Import Tests Complete ==="
