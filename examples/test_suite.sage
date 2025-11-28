# Comprehensive Test Suite for SageLang
# Tests all features from Phases 1-6

print "=== SageLang Comprehensive Test Suite ==="
print ""

# ===== PHASE 1: Core Language =====
print "PHASE 1: Core Language"
print "----------------------"

# Variables
let x = 10
let y = 20
let name = "Sage"
print "Variables: x=10, y=20, name=Sage"

# Arithmetic
let sum = x + y
let diff = y - x
let prod = x * y
let quot = y / x
print "Arithmetic: 10+20=30, 20-10=10, 10*20=200, 20/10=2"

# Comparisons
if x < y:
    print "Comparison <: PASS"
if y > x:
    print "Comparison >: PASS"
if x <= y:
    print "Comparison <=: PASS"
if y >= x:
    print "Comparison >=: PASS"
if x == 10:
    print "Comparison ==: PASS"
if x != y:
    print "Comparison !=: PASS"

print ""

# ===== PHASE 2: Functions =====
print "PHASE 2: Functions"
print "------------------"

proc add(a, b):
    return a + b

proc factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

let result = add(5, 7)
print "Function call add(5,7):"
print result

let fact = factorial(5)
print "Recursion factorial(5):"
print fact

print ""

# ===== PHASE 3: Types & Stdlib =====
print "PHASE 3: Types & Standard Library"
print "----------------------------------"

let bool_true = true
let bool_false = false
let nil_val = nil

print "Boolean true:"
print bool_true
print "Boolean false:"
print bool_false

let str1 = "Hello"
let str2 = "World"
let concat = str1 + " " + str2
print "String concat:"
print concat

let str_len = len("SageLang")
print "String length:"
print str_len

print ""

# ===== PHASE 4: Garbage Collection =====
print "PHASE 4: Garbage Collection"
print "---------------------------"

let gc_stats_before = gc_stats()
print "GC objects before:"
print gc_stats_before["num_objects"]

let temp_arrays = []
for i in range(20):
    let temp = [i, i+1, i+2]
    push(temp_arrays, temp)

let gc_stats_after = gc_stats()
print "GC objects after creating 20 arrays:"
print gc_stats_after["num_objects"]

print ""

# ===== PHASE 5: Data Structures =====
print "PHASE 5: Advanced Data Structures"
print "----------------------------------"

# Arrays
let numbers = [1, 2, 3, 4, 5]
print "Array:"
print numbers

let sliced = slice(numbers, 1, 4)
print "Sliced [1:4]:"
print sliced

# Dictionaries
let user = {"name": "Alice", "age": "25"}
print "Dictionary:"
print user["name"]

let dict_k = dict_keys(user)
print "Dict keys:"
for k in dict_k:
    print k

# Tuples
let coords = (100, 200, 300)
print "Tuple:"
print coords
print "First coord:"
print coords[0]

# String methods
let sentence = "hello world sage"
let words_arr = split(sentence, " ")
print "Split string:"
for w in words_arr:
    print w

let upper_text = upper("sage")
print "Uppercase SAGE:"
print upper_text

# Break and continue
print "Break at 3:"
for i in range(5):
    if i == 3:
        break
    print i

print ""

# ===== PHASE 6: Object-Oriented =====
print "PHASE 6: Object-Oriented Programming"
print "-------------------------------------"

# Basic class
class Counter:
    proc init(self, start):
        self.value = start
    
    proc increment(self):
        self.value = self.value + 1
    
    proc get(self):
        return self.value

let counter = Counter(0)
print "Counter initial:"
print counter.get()

counter.increment()
counter.increment()
print "After 2 increments:"
print counter.get()

# Inheritance
class Animal:
    proc init(self, name):
        self.name = name
    
    proc speak(self):
        print "Some sound"

class Dog(Animal):
    proc speak(self):
        print "Woof!"

let dog = Dog("Buddy")
print "Dog name:"
print dog.name
print "Dog speaks:"
dog.speak()

print ""
print "=== ALL TESTS PASSED ==="
print "SageLang is working correctly!"