# EXPECT: Rex
# EXPECT: Labrador
# EXPECT: Woof!
# Test new-style super calls (self auto-injected)
class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        return "..."

class Dog(Animal):
    proc init(self, name, breed):
        super.init(name)
        self.breed = breed
    proc speak(self):
        return "Woof!"

let d = Dog("Rex", "Labrador")
print d.name
print d.breed
print d.speak()
