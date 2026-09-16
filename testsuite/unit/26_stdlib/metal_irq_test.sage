# EXPECT: pic_consts_ok
# EXPECT: exception_consts_ok
# EXPECT: handler_register_ok
# EXPECT: handler_dispatch_ok
# EXPECT: register_handler_safe_duplicate_ok
# EXPECT: unregister_handler_ok
# EXPECT: register_handler_safe_ok
# EXPECT: unregister_handler_nonexistent_ok
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

# Test safe register and unregister
let safe1 = irq.register_handler_safe(32, my_handler)
if safe1 == false:
    print "register_handler_safe_duplicate_ok"

let unreg1 = irq.unregister_handler(32)
if unreg1 == true:
    print "unregister_handler_ok"

let safe2 = irq.register_handler_safe(32, my_handler)
if safe2 == true:
    print "register_handler_safe_ok"

let unreg_nonexistent = irq.unregister_handler(99)
if unreg_nonexistent == false:
    print "unregister_handler_nonexistent_ok"

print "PASS"
