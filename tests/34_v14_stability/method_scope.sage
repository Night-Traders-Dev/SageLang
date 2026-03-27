# EXPECT: 1.4.0
# EXPECT: 100
# EXPECT: 1.4.0
# Test class methods can see module-level let bindings
let VERSION = "1.4.0"
let MAX_SIZE = 100

class Config:
    proc init(self):
        self.ver = VERSION
        self.max = MAX_SIZE

    proc show_version(self):
        print VERSION

    proc show_max(self):
        print self.max

let c = Config()
c.show_version()
c.show_max()
print c.ver
