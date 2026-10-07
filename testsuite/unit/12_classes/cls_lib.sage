## Library side of the class-reference test.
class Widget:
    proc init(self, v: Int):
        self.v = v
    proc get(self) -> Int:
        return self.v
