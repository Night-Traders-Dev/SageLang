# EXPECT: pic_consts_ok
# EXPECT: exception_consts_ok
# EXPECT: handler_register_ok
# EXPECT: handler_dispatch_ok
# EXPECT: safe_register_ok
# EXPECT: safe_register_duplicate_ok
# EXPECT: unregister_ok
# EXPECT: unregister_nonexistent_ok
# EXPECT: PASS
import metal.irq as irq

# PIC constants
if irq.PIC1_CMD == 32 and irq.PIC2_CMD == 160:
    if irq.ICW1_INIT == 17 and irq.ICW4_8086 == 1:
        print "pic_consts_ok"

# Exception vector constants
if irq.EXCEPTION_PAGE_FAULT == 14 and irq.EXCEPTION_DOUBLE_FAULT == 8:
    if irq.IRQ_TIMER == 0 and irq.IRQ_KEYBOARD == 1:
        print "exception_consts_ok"

# Register and dispatch a handler
let fired = false
proc my_handler(vec):
    fired = true
irq.register_handler(32, my_handler)
print "handler_register_ok"

irq.dispatch(32)
if fired == true:
    print "handler_dispatch_ok"

# Safe register test
if irq.register_handler_safe(33, my_handler) == true:
    print "safe_register_ok"

if irq.register_handler_safe(33, my_handler) == false:
    print "safe_register_duplicate_ok"

# Unregister test
if irq.unregister_handler(33) == true:
    print "unregister_ok"

if irq.unregister_handler(33) == false:
    print "unregister_nonexistent_ok"

print "PASS"
