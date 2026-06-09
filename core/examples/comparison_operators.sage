# Comprehensive test of all comparison operators
print "=== Comparison Operators Test ==="
print ""

# Greater than (>)
print "Greater than (>):"
let a = 10
let b = 5
if a > b:
    print "10 > 5 is true"

# Less than (<)
print ""
print "Less than (<):"
if b < a:
    print "5 < 10 is true"

# Greater than or equal (>=)
print ""
print "Greater than or equal (>=):"
let c = 10
if a >= c:
    print "10 >= 10 is true"

if a >= b:
    print "10 >= 5 is true"

# Less than or equal (<=)
print ""
print "Less than or equal (<=):"
if c <= a:
    print "10 <= 10 is true"

if b <= a:
    print "5 <= 10 is true"

# Equal (==)
print ""
print "Equal (==):"
if a == c:
    print "10 == 10 is true"

# Not equal (!=)
print ""
print "Not equal (!=):"
if a != b:
    print "10 != 5 is true"

# Complex comparisons
print ""
print "Complex comparisons:"
let balance = 100
let price = 75

if balance >= price:
    print "You have enough money!"

if price <= balance:
    print "Price is within budget!"

print ""
print "All comparison operators work!"