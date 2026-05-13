# EXPECT: Alice
# EXPECT: 30
# EXPECT: Hi, I'm Alice
class Person:
    proc init(self, name, age):
        self.name = name
        self.age = age
    proc greet(self):
        return "Hi, I'm " + self.name
let p = Person("Alice", 30)
print(p.name)
print(p.age)
print(p.greet())
