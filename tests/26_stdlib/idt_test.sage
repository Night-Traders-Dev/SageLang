gc_disable()
# EXPECT: Divide Error
# EXPECT: Page Fault
# EXPECT: true
# EXPECT: false
# EXPECT: true
# EXPECT: 16
# EXPECT: Interrupt
# EXPECT: 0
# EXPECT: 10

import os.idt

print idt.exception_name(0)
print idt.exception_name(14)
print idt.has_error_code(14)
print idt.has_error_code(0)

# Create an interrupt gate
let gate = idt.interrupt_gate(4096, 8)
print gate["present"]
print len(gate["bytes"])
print gate["type_name"]
print gate["dpl"]

# PIC remap
let pic_seq = idt.pic_remap_sequence(32)
print len(pic_seq)
