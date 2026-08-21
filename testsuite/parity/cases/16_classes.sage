class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        return self.name + " makes a sound"
class Dog(Animal):
    proc speak(self):
        return self.name + " barks"
let d = Dog("Rex")
print d.speak()
let a = Animal("Cat")
print a.speak()
