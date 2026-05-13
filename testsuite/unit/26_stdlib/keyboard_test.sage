gc_disable()
# EXPECT: scancode_a
# EXPECT: scancode_enter
# EXPECT: PASS
let scancodes = []
for i in range(128):
    push(scancodes, 0)
scancodes[30] = 97
scancodes[28] = 10
if scancodes[30] == 97:
    print "scancode_a"
if scancodes[28] == 10:
    print "scancode_enter"
print "PASS"
