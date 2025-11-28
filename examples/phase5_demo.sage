# Phase 5 Feature Demonstration
# Dictionaries, Tuples, Slicing, String Methods, Break/Continue

print "=== Phase 5: Advanced Data Structures ==="
print ""

# 1. Dictionary (Hash Map)
print "1. Dictionaries:"
let person = {"name": "Alice", "age": "30", "city": "NYC"}
print person
print ""

# 2. Tuples
print "2. Tuples:"
let point = (10, 20)
let triple = (1, 2, 3)
print "Point:"
print point
print "Triple:"
print triple
print ""

# 3. Array Slicing
print "3. Array Slicing:"
let nums = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
print "Original array:"
print nums

let first_five = slice(nums, 0, 5)
print "First five (0:5):"
print first_five

let middle = slice(nums, 3, 7)
print "Middle (3:7):"
print middle

let last_three = slice(nums, 7, 10)
print "Last three (7:10):"
print last_three
print ""

# 4. String Methods
print "4. String Methods:"

let text = "hello world"
print "Original:"
print text

let words = split(text, " ")
print "Split by space:"
print words

let joined = join(words, "-")
print "Joined with dash:"
print joined

let uppercase = upper(text)
print "Uppercase:"
print uppercase

let replaced = replace(text, "world", "Sage")
print "Replaced 'world' with 'Sage':"
print replaced

let padded = "  spaces  "
let trimmed = strip(padded)
print "Trimmed spaces:"
print trimmed
print ""

# 5. Break and Continue
print "5. Break and Continue:"

print "Using break (stop at 5):"
for i in range(10):
    if i == 5:
        break
    print i

print ""
print "Using continue (skip 3 and 7):"
for i in range(10):
    if i == 3:
        continue
    if i == 7:
        continue
    print i

print ""
print "=== Phase 5 Complete! ==="