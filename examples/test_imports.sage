# SageLang Import System Test - FIXED VERSION

print("=== Testing Import System ===")


# Test 1: Basic imports from math module
print("Test 1: Basic imports")
print("from math import sqrt, abs, power")


from math import sqrt
from math import abs
from math import power

var val = 16
var result = sqrt(val)
print("sqrt(16) = ")
print(result)


var neg = abs(0 - 5)
print("abs(-5) = ")
print(neg)


var pow_result = power(2, 3)
print("power(2, 3) = ")
print(pow_result)


# Test 2: Import with pow function
print("Test 2: Import pow function")
print("from math import pow")


from math import pow

var p1 = pow(2, 4)
print("pow(2, 4) = ")
print(p1)


var p2 = pow(3, 3)
print("pow(3, 3) = ")
print(p2)


# Test 3: Import with aliases
print("Test 3: Import with aliases")
print("from math import sqrt as sq, abs as absolute")


from math import sqrt as sq, abs as absolute

var squared = sq(25)
print("sq(25) = ")
print(squared)


var val2 = absolute(-42)
print("absolute(-42) = ")
print(val2)


# Test 4: Multiple aliases
print("Test 4: Multiple aliases")
print("from math import add as plus, multiply as times, power as pow_alias")


from math import add as plus, multiply as times, power as pow_alias

var sum_result = plus(10, 20)
print("plus(10, 20) = ")
print(sum_result)


var mult_result = times(6, 7)
print("times(6, 7) = ")
print(mult_result)


var pow_alias_result = pow_alias(2, 5)
print("pow_alias(2, 5) = ")
print(pow_alias_result)


# Test 5: Mixed imports (some aliased, some not)
print("Test 5: Mixed imports")
print("from math import add, sqrt as root, multiply")


from math import add, sqrt as root, multiply

var m1 = add(7, 3)
print("add(7, 3) = ")
print(m1)


var m2 = root(36)
print("root(36) = ")
print(m2)


var m3 = multiply(4, 9)
print("multiply(4, 9) = ")
print(m3)


print("=== All Import Tests Complete ===")
