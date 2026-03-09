# Test classes/objects in C backend
class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        return "..."

class Dog(Animal):
    proc speak(self):
        return "Woof"

let a = Animal("Cat")
print a.name
print a.speak()

let d = Dog("Rex")
print d.name
print d.speak()
