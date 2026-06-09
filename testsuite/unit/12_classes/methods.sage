# EXPECT: 0
# EXPECT: 5
# EXPECT: 3
# EXPECT: 2
class Counter:
    proc init(self):
        self.count = 0
    proc increment(self):
        self.count = self.count + 1
    proc add(self, n):
        self.count = self.count + n
    proc get(self):
        return self.count
let c = Counter()
print(c.get())
c.add(5)
print(c.get())
c.increment()
c.increment()
c.increment()
print(c.count - 5)
let c2 = Counter()
c2.add(2)
print(c2.get())
