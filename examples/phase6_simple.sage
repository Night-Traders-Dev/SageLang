# Simple Phase 6 Test - Classes without method calls yet

print "Testing Phase 6 - Classes"

class Person:
    proc init(self, name, age):
        self.name = name
        self.age = age

let alice = Person("Alice", 30)

print "Name:"
print alice.name
print "Age:"
print alice.age

print "Done!"