# EXPECT: Toyota
# EXPECT: Camry
# EXPECT: 2023
class Vehicle:
    proc init(self, brand):
        self.brand = brand
class Car(Vehicle):
    proc init(self, brand, model, year):
        self.brand = brand
        self.model = model
        self.year = year
let c = Car("Toyota", "Camry", 2023)
print(c.brand)
print(c.model)
print(c.year)
