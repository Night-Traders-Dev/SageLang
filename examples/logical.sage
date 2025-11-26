# Test logical operators

let x = 5
let y = 10

# AND operator
if x > 0 and y > 0
    print "Both positive!"

# OR operator
if x > 10 or y > 8
    print "At least one condition met!"

# Short-circuit evaluation
if false and print("This won't print")
    print "Never"
else
    print "Short-circuit works!"

# Complex condition
if (x > 0 and y < 20) or x == 5
    print "Complex logic works!"
