# Conformance: Classes, Inheritance, Super (Spec §12)
# EXPECT: Rex
# EXPECT: Woof!
# EXPECT: Animal moves
# EXPECT: Dog(Rex, Lab)
class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        return "..."
    proc move(self):
        print "Animal moves"

class Dog(Animal):
    proc init(self, name, breed):
        super.init(name)
        self.breed = breed
    proc speak(self):
        return "Woof!"
    proc __str__(self):
        return "Dog(" + self.name + ", " + self.breed + ")"

let d = Dog("Rex", "Lab")
print d.name
print d.speak()
d.move()
print d
