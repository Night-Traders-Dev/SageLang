# EXPECT: Woof!
# EXPECT: Rex
class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        return "..."
class Dog(Animal):
    proc speak(self):
        return "Woof!"
let d = Dog("Rex")
print(d.speak())
print(d.name)
