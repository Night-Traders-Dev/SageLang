# Comprehensive Data Structures Demo
print "=== SageLang Data Structures ==="
print ""

# ===== ARRAYS =====
print "1. ARRAYS (Dynamic Lists)"
print "-------------------------"

let numbers = [1, 2, 3, 4, 5]
print "Initial array:"
print numbers

print "Access by index:"
print "numbers[0] ="
print numbers[0]
print "numbers[4] ="
print numbers[4]

push(numbers, 6)
print "After push(6):"
print numbers

let last = pop(numbers)
print "Popped value:"
print last
print "Array after pop:"
print numbers

print "Array length:"
print len(numbers)

let subset = slice(numbers, 1, 4)
print "Slice [1:4]:"
print subset

print ""

# ===== DICTIONARIES =====
print "2. DICTIONARIES (Hash Maps)"
print "---------------------------"

let config = {
    "host": "localhost",
    "port": "8080",
    "debug": "true"
}

print "Initial dictionary:"
print "Host:"
print config["host"]
print "Port:"
print config["port"]

config["timeout"] = "30"
print "Added timeout=30"

print "All keys:"
let keys = dict_keys(config)
for key in keys:
    print key

print "All values:"
let values = dict_values(config)
for val in values:
    print val

if dict_has(config, "debug"):
    print "'debug' key exists"

dict_delete(config, "debug")
print "Deleted 'debug' key"

let updated_keys = dict_keys(config)
print "Keys after deletion:"
for k in updated_keys:
    print k

print ""

# ===== TUPLES =====
print "3. TUPLES (Immutable Sequences)"
print "-------------------------------"

let point2d = (10, 20)
let point3d = (10, 20, 30)
let rgb = (255, 128, 0)

print "2D Point:"
print point2d
print "X:"
print point2d[0]
print "Y:"
print point2d[1]

print "3D Point:"
print point3d
print "Z:"
print point3d[2]

print "RGB Color:"
print "Red:"
print rgb[0]
print "Green:"
print rgb[1]
print "Blue:"
print rgb[2]

let tuple_len = len(point3d)
print "Tuple length:"
print tuple_len

print ""

# ===== NESTED STRUCTURES =====
print "4. NESTED STRUCTURES"
print "--------------------"

let matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
]

print "Matrix (nested arrays):"
for row in matrix:
    print row

print "Element at [1][2]:"
print matrix[1][2]

let users = [
    {"name": "Alice", "role": "admin"},
    {"name": "Bob", "role": "user"},
    {"name": "Carol", "role": "user"}
]

print "Users (array of dicts):"
for user in users:
    print user["name"]

print ""

# ===== PRACTICAL EXAMPLE =====
print "5. PRACTICAL EXAMPLE: Shopping Cart"
print "-----------------------------------"

let cart = []
let prices = {"apple": "1", "banana": "2", "orange": "3"}

print "Adding items to cart..."
push(cart, "apple")
push(cart, "banana")
push(cart, "apple")

print "Cart contents:"
for item in cart:
    print item

print "Cart size:"
print len(cart)

print ""
print "=== Data Structures Demo Complete! ==="