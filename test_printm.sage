import math

print "--- Testing pure Sage backend ---"
math.printm("123 + 456", "sage")
math.printm("12 * 13", "sage")

print "\n--- Testing C backend ---"
math.printm("123 + 456", "c")
math.printm("12 * 13", "c")

print "\n--- Testing Assembly backend ---"
math.printm("123 + 456", "asm")
math.printm("12 * 13", "asm")

print "\n--- Testing Assembly backend with exec flag ---"
math.printm("10 + 20", "asm", ["grade", "exec"])

print "\n--- Testing complex expression (12 * 13 + 5) ---"
let res = math.printm("12 * 13 + 5", "sage")
print "Final Result: " + str(res)
