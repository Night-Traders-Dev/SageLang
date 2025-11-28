# Exception Handling Examples
# Demonstrates try/catch/finally and raise statements

print "=== Example 1: Basic Try/Catch ==="
try:
    print "In try block"
    raise "Something went wrong!"
    print "This won't execute"
catch e:
    print "Caught exception: " + e

print "---"

# Example 2: Finally block (always executes)
print "=== Example 2: Finally Block ==="
try:
    print "Trying..."
    raise "Error occurred"
catch e:
    print "Handling: " + e
finally:
    print "Finally block executed"

print "---"

# Example 3: No exception (finally still runs)
print "=== Example 3: No Exception ==="
try:
    print "Success path"
    let x = 42
catch e:
    print "Won't catch anything"
finally:
    print "Finally runs anyway"

print "---"

# Example 4: Exception in function
print "=== Example 4: Function Exceptions ==="
proc divide(a, b):
    if b == 0:
        raise "Division by zero!"
    return a / b

try:
    let result = divide(10, 2)
    print "Result: " + str(result)
    let bad = divide(10, 0)
    print "This won't print"
catch e:
    print "Math error: " + e

print "---"

# Example 5: Nested try/catch
print "=== Example 5: Nested Exceptions ==="
try:
    print "Outer try"
    try:
        print "Inner try"
        raise "Inner error"
    catch e:
        print "Inner catch: " + e
        raise "Re-raised from inner"
    finally:
        print "Inner finally"
catch e:
    print "Outer catch: " + e
finally:
    print "Outer finally"

print "---"

# Example 6: Validation pattern
print "=== Example 6: Validation Pattern ==="
proc validate_age(age):
    if age < 0:
        raise "Age cannot be negative"
    if age > 150:
        raise "Age too high"
    return true

proc check_age(age):
    try:
        validate_age(age)
        print "Age " + str(age) + " is valid"
    catch e:
        print "Invalid age " + str(age) + ": " + e

let ages = [-5, 25, 200, 30]
let i = 0
while i < len(ages):
    check_age(ages[i])
    let i = i + 1

print "---"

# Example 7: Resource cleanup with finally
print "=== Example 7: Resource Cleanup ==="
proc process_file(filename):
    print "Opening: " + filename
    try:
        if filename == "bad.txt":
            raise "File not found"
        print "Processing: " + filename
    finally:
        print "Closing: " + filename

process_file("good.txt")
try:
    process_file("bad.txt")
catch e:
    print "Error: " + e

print "---"
print "All exception examples completed!