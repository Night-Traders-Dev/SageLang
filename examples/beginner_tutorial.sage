# SageLang Beginner Tutorial
# Learn the basics step by step

print "=== Welcome to SageLang! ==="
print ""

# ===== 1. Variables =====
print "1. VARIABLES"
print "------------"
print "Use 'let' to create variables:"

let my_number = 42
let my_string = "Hello, Sage!"
let my_bool = true

print my_number
print my_string
print my_bool
print ""

# ===== 2. Arithmetic =====
print "2. ARITHMETIC"
print "-------------"
let a = 10
let b = 3

print "10 + 3 ="
print a + b

print "10 - 3 ="
print a - b

print "10 * 3 ="
print a * b

print "10 / 3 ="
print a / b
print ""

# ===== 3. Conditionals =====
print "3. CONDITIONALS"
print "---------------"
print "Use 'if' and 'else' (note the colon!):"

let age = 18

if age >= 18:
    print "You are an adult"
else:
    print "You are a minor"

print ""

# ===== 4. Loops =====
print "4. LOOPS"
print "--------"
print "While loop (count to 3):"

let counter = 0
while counter < 3:
    print counter
    let counter = counter + 1

print ""
print "For loop (iterate array):"
let fruits = ["apple", "banana", "cherry"]
for fruit in fruits:
    print fruit

print ""
print "For loop with range:"
for i in range(5):
    print i

print ""

# ===== 5. Functions =====
print "5. FUNCTIONS"
print "------------"
print "Define functions with 'proc':"

proc greet(name):
    print "Hello,"
    print name
    print "!"

proc add_numbers(x, y):
    return x + y

greet("Alice")

let sum = add_numbers(15, 27)
print "15 + 27 ="
print sum
print ""

# ===== 6. Data Structures =====
print "6. DATA STRUCTURES"
print "------------------"

print "Arrays:"
let numbers = [1, 2, 3, 4, 5]
push(numbers, 6)
print numbers
print "Length:"
print len(numbers)

print ""
print "Dictionaries:"
let person = {"name": "Bob", "age": "30"}
print "Name:"
print person["name"]

print ""
print "Tuples:"
let point = (10, 20, 30)
print "X coordinate:"
print point[0]

print ""

# ===== 7. Classes =====
print "7. CLASSES (Object-Oriented)"
print "----------------------------"

class Rectangle:
    proc init(self, width, height):
        self.width = width
        self.height = height
    
    proc area(self):
        return self.width * self.height
    
    proc perimeter(self):
        return 2 * (self.width + self.height)

let rect = Rectangle(5, 10)
print "Rectangle 5x10"
print "Area:"
print rect.area()
print "Perimeter:"
print rect.perimeter()

print ""
print "=== Tutorial Complete! ==="
print "You now know the basics of SageLang!"
print "Try modifying this file to experiment more."