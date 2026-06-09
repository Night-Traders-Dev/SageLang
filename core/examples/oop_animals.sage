# Object-Oriented Programming - Animal Kingdom
print "=== Animal Kingdom OOP Demo ==="
print ""

# Base Animal class
class Animal:
    proc init(self, name, species):
        self.name = name
        self.species = species
        self.energy = 100
    
    proc speak(self):
        print self.name
        print "makes a sound"
    
    proc eat(self):
        self.energy = self.energy + 20
        print self.name
        print "is eating"
    
    proc sleep(self):
        self.energy = 100
        print self.name
        print "is sleeping"
    
    proc get_info(self):
        print "Name:"
        print self.name
        print "Species:"
        print self.species
        print "Energy:"
        print self.energy

# Dog class with inheritance
class Dog(Animal):
    proc init(self, name, breed):
        self.name = name
        self.species = "Canine"
        self.breed = breed
        self.energy = 100
    
    proc speak(self):
        print self.name
        print "says: Woof! Woof!"
    
    proc fetch(self):
        self.energy = self.energy - 10
        print self.name
        print "fetches the ball!"

# Cat class with inheritance
class Cat(Animal):
    proc init(self, name, color):
        self.name = name
        self.species = "Feline"
        self.color = color
        self.energy = 100
    
    proc speak(self):
        print self.name
        print "says: Meow!"
    
    proc purr(self):
        print self.name
        print "purrs contentedly"

# Bird class with inheritance
class Bird(Animal):
    proc init(self, name, can_fly):
        self.name = name
        self.species = "Avian"
        self.can_fly = can_fly
        self.energy = 100
    
    proc speak(self):
        print self.name
        print "says: Tweet tweet!"
    
    proc fly(self):
        if self.can_fly:
            self.energy = self.energy - 15
            print self.name
            print "soars through the sky!"
        else:
            print self.name
            print "cannot fly"

print "1. Creating a dog:"
let buddy = Dog("Buddy", "Golden Retriever")
buddy.get_info()
print ""

print "2. Dog actions:"
buddy.speak()
buddy.fetch()
print "Energy after fetch:"
print buddy.energy
print ""

print "3. Creating a cat:"
let whiskers = Cat("Whiskers", "Orange")
whiskers.speak()
whiskers.purr()
print ""

print "4. Creating a bird:"
let tweety = Bird("Tweety", true)
tweety.speak()
tweety.fly()
print "Energy after flying:"
print tweety.energy
print ""

print "5. All animals eating:"
buddy.eat()
whiskers.eat()
tweety.eat()
print ""

print "Animal kingdom demo complete!"