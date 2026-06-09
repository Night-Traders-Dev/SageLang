# LLVM backend feature test: arrays, dicts, for loops, string ops, conditionals

# Cross-module constant import
from mathlib import PI
print PI

# Arrays
let arr = [10, 20, 30]
push(arr, 40)
print len(arr)

# For loop
let sum = 0
for x in arr:
    sum = sum + x
print sum

# String operations
let greeting = "hello" + " " + "world"
print greeting
print len(greeting)
print str(42)

# Dict
let d = {"name": "sage", "version": "0.14"}
print d["name"]

# Nested if/else
let val = 7
if val > 10:
    print "big"
else:
    if val > 5:
        print "medium"
    else:
        print "small"

# While with break pattern
let i = 0
while i < 100:
    if i == 3:
        break
    i = i + 1
print i

# Recursive function
proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

print factorial(6)

# Boolean logic
print true and false
print true or false
print not false
