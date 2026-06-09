# Class and method dispatch — measures OOP overhead
class Counter:
    proc init(self, start):
        self.value = start

    proc increment(self, amount):
        self.value = self.value + amount
        return self.value

let c = Counter(0)
let i = 0
while i < 100000:
    c.increment(1)
    i = i + 1

print c.value
