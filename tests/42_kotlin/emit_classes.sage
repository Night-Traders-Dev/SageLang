## Test: Kotlin backend — classes, inheritance, methods
## Run: sage --emit-kotlin tests/42_kotlin/emit_classes.sage

class Animal:
    proc init(self, name):
        self.name = name
    proc speak(self):
        return self.name + " makes a sound"
    proc describe(self):
        return "I am " + self.name

class Dog(Animal):
    proc speak(self):
        return self.name + " barks!"

class Cat(Animal):
    proc speak(self):
        return self.name + " meows!"

let dog = Dog("Rex")
let cat = Cat("Whiskers")

print(dog.speak())
print(cat.speak())
print(dog.describe())

## Match statement
let animal = "dog"
match animal:
    case "dog":
        print("It's a dog")
    case "cat":
        print("It's a cat")
    default:
        print("Unknown animal")

## Try/catch
try:
    raise "Something went wrong"
catch e:
    print("Caught: " + e)
finally:
    print("Cleanup done")
