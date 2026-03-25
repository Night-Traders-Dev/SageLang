gc_disable()
# EXPECT: scancode_a
# EXPECT: scancode_enter
# EXPECT: PASS

import os.kernel.keyboard

# Initialize the keyboard driver (builds scancode tables)
keyboard.init()

# Test scancode 0x1E (30 decimal) = 'a'
let ch_a = keyboard.scancode_to_ascii(30, false)
if ch_a == "a"
    print "scancode_a"
end

# Test scancode 0x1C (28 decimal) = enter (newline)
let ch_enter = keyboard.scancode_to_ascii(28, false)
if ch_enter == chr(10)
    print "scancode_enter"
end

print "PASS"
