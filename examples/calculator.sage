# Interactive Calculator using OOP
print "=== Sage Calculator ==="
print ""

class Calculator:
    proc init(self):
        self.result = 0
        self.history = []
    
    proc add(self, a, b):
        self.result = a + b
        return self.result
    
    proc subtract(self, a, b):
        self.result = a - b
        return self.result
    
    proc multiply(self, a, b):
        self.result = a * b
        return self.result
    
    proc divide(self, a, b):
        if b == 0:
            print "Error: Division by zero!"
            return 0
        self.result = a / b
        return self.result
    
    proc power(self, base, exp):
        self.result = 1
        for i in range(exp):
            self.result = self.result * base
        return self.result
    
    proc is_positive(self, num):
        if num > 0:
            return true
        return false
    
    proc is_even(self, num):
        let half = num / 2
        let doubled = half * 2
        if num == doubled:
            return true
        return false
    
    proc absolute(self, num):
        if num < 0:
            return num * -1
        return num
    
    proc max(self, a, b):
        if a >= b:
            return a
        return b
    
    proc min(self, a, b):
        if a <= b:
            return a
        return b

let calc = Calculator()

print "Addition: 15 + 7 ="
let sum = calc.add(15, 7)
print sum

print ""
print "Subtraction: 20 - 8 ="
let diff = calc.subtract(20, 8)
print diff

print ""
print "Multiplication: 6 * 7 ="
let product = calc.multiply(6, 7)
print product

print ""
print "Division: 100 / 4 ="
let quotient = calc.divide(100, 4)
print quotient

print ""
print "Power: 2^10 ="
let power = calc.power(2, 10)
print power

print ""
print "Is 42 positive?"
if calc.is_positive(42):
    print "Yes!"

print ""
print "Is 10 even?"
if calc.is_even(10):
    print "Yes!"

print ""
print "Absolute value of -15:"
let abs_val = calc.absolute(-15)
print abs_val

print ""
print "Max of 42 and 38:"
let maximum = calc.max(42, 38)
print maximum

print ""
print "Min of 42 and 38:"
let minimum = calc.min(42, 38)
print minimum

print ""
print "Calculator demo complete!"