# Class and method dispatch — measures OOP overhead
class Counter:
    def __init__(self, start):
        self.value = start

    def increment(self, amount):
        self.value = self.value + amount
        return self.value

c = Counter(0)
i = 0
while i < 100000:
    c.increment(1)
    i = i + 1

print(c.value)
