# Defer Statement Examples
# Defer ensures code runs when leaving a scope (LIFO order)

# Example 1: File handling simulation
proc open_file(filename):
    print "Opening file: " + filename
    defer print "Closing file: " + filename
    print "Reading from: " + filename
    print "Processing: " + filename
    # File automatically "closed" when function returns

open_file("data.txt")
print "---"

# Example 2: Cleanup guarantees
proc process_data():
    print "Start processing"
    defer print "Cleanup 1"
    defer print "Cleanup 2"
    defer print "Cleanup 3"
    print "Doing work..."
    # Defers execute in reverse order: Cleanup 3, 2, 1

process_data()
print "---"

# Example 3: Logging execution flow
proc logged_operation(name):
    print "ENTER: " + name
    defer print "EXIT: " + name
    
    if name == "task1":
        print "Executing task1"
    else:
        print "Executing other task"
    
    return "Result: " + name

let result1 = logged_operation("task1")
print result1
let result2 = logged_operation("task2")
print result2
print "---"

# Example 4: Resource management
proc use_resources():
    print "Acquiring resource A"
    defer print "Releasing resource A"
    
    print "Acquiring resource B"
    defer print "Releasing resource B"
    
    print "Acquiring resource C"
    defer print "Releasing resource C"
    
    print "Using all resources"
    # Resources released in reverse: C, B, A

use_resources()
print "---"

# Example 5: Defer with early return
proc validate_and_process(value):
    print "Start validation"
    defer print "Validation complete"
    
    if value < 0:
        print "Invalid value!"
        return "ERROR"
    
    print "Processing valid value: " + str(value)
    return "OK"

let status1 = validate_and_process(42)
print "Status: " + status1
print "---"
let status2 = validate_and_process(-5)
print "Status: " + status2
print "---"

# Example 6: Nested defers
proc outer():
    print "Outer start"
    defer print "Outer defer 1"
    
    let x = 10
    defer print "Outer defer 2"
    
    print "Outer end"

outer()
print "---"

# Example 7: Counter example
proc count_operations():
    let count = 0
    print "Operation started"
    defer print "Total operations: 3"
    
    count = count + 1
    print "Operation 1"
    
    count = count + 1
    print "Operation 2"
    
    count = count + 1
    print "Operation 3"

count_operations()
print "---"

print "All defer examples completed!"