# Test super.method() for calling parent class methods
# EXPECT: Animal speaks
# EXPECT: Dog barks
# EXPECT: Animal speaks
# EXPECT: Puppy yaps
# EXPECT: Dog barks
# EXPECT: Animal speaks

class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        print "Animal speaks"

class Dog(Animal):
    proc init(self, name):
        super.init(self, name)
    proc speak(self):
        print "Dog barks"
        super.speak(self)

class Puppy(Dog):
    proc init(self, name):
        super.init(self, name)
    proc speak(self):
        print "Puppy yaps"
        super.speak(self)

let a = Animal("A")
a.speak()

let d = Dog("D")
d.speak()

let p = Puppy("P")
p.speak()
