# EXPECT: red
# EXPECT: blue
class Box:
    proc init(self, color):
        self.color = color
let b = Box("red")
print(b.color)
b.color = "blue"
print(b.color)
