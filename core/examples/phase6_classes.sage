# Phase 6: Object-Oriented Programming Examples
# Classes, Constructors, Methods, Inheritance

print "=== Phase 6: Object-Oriented Programming ==="
print ""

# 1. Basic Class with Constructor
print "1. Basic Class:"

class Person:
    proc init(self, name, age):
        self.name = name
        self.age = age
    
    proc greet(self):
        print "Hello, my name is"
        print self.name
        print "I am"
        print self.age
        print "years old"

let alice = Person("Alice", 30)
alice.greet()
print ""

# 2. Property Access
print "2. Property Access:"
print "Name:"
print alice.name
print "Age:"
print alice.age
print ""

# 3. Property Modification
print "3. Property Modification:"
alice.age = 31
print "New age:"
print alice.age
print ""

# 4. Multiple Instances
print "4. Multiple Instances:"
let bob = Person("Bob", 25)
print "Alice's name:"
print alice.name
print "Bob's name:"
print bob.name
print ""

# 5. Method with Return Value
print "5. Methods with Return:"

class Calculator:
    proc init(self):
        self.result = 0
    
    proc add(self, a, b):
        self.result = a + b
        return self.result
    
    proc get_result(self):
        return self.result

let calc = Calculator()
let sum = calc.add(10, 20)
print "Sum:"
print sum
print "Result:"
print calc.get_result()
print ""

# 6. Inheritance
print "6. Inheritance:"

class Animal:
    proc init(self, name):
        self.name = name
    
    proc speak(self):
        print "Some animal sound"

class Dog(Animal):
    proc init(self, name, breed):
        self.name = name
        self.breed = breed
    
    proc speak(self):
        print "Woof! Woof!"
    
    proc info(self):
        print self.name
        print "is a"
        print self.breed

let dog = Dog("Rex", "Golden Retriever")
print "Dog speaks:"
dog.speak()
dog.info()
print ""

# 7. Another Inheritance Example
print "7. More Inheritance:"

class Vehicle:
    proc init(self, brand):
        self.brand = brand
    
    proc show_brand(self):
        print "Brand:"
        print self.brand

class Car(Vehicle):
    proc init(self, brand, model):
        self.brand = brand
        self.model = model
    
    proc show_info(self):
        print "Car:"
        print self.brand
        print self.model

let car = Car("Toyota", "Camry")
car.show_brand()
car.show_info()
print ""

# 8. Class with Multiple Methods
print "8. Complex Class:"

class BankAccount:
    proc init(self, owner, balance):
        self.owner = owner
        self.balance = balance
    
    proc deposit(self, amount):
        self.balance = self.balance + amount
        print "Deposited:"
        print amount
    
    proc withdraw(self, amount):
        if self.balance >= amount:
            self.balance = self.balance - amount
            print "Withdrew:"
            print amount
        else:
            print "Insufficient funds"
    
    proc get_balance(self):
        return self.balance

let account = BankAccount("Alice", 1000)
print "Initial balance:"
print account.get_balance()

account.deposit(500)
print "After deposit:"
print account.get_balance()

account.withdraw(200)
print "After withdrawal:"
print account.get_balance()

print ""
print "=== Phase 6 Complete! ==="