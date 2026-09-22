# EXPECT: pic_consts_ok
# EXPECT: exception_consts_ok
# EXPECT: handler_register_ok
# EXPECT: handler_dispatch_ok
# EXPECT: handler_safe_ok
# EXPECT: unregister_ok
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

# Safe registration tests
let re_reg = irq.register_handler_safe(32, my_handler)
let new_reg = irq.register_handler_safe(33, my_handler)
if re_reg == false and new_reg == true:
    print "handler_safe_ok"

# Unregister tests
let unreg_33 = irq.unregister_handler(33)
let unreg_99 = irq.unregister_handler(99)
if unreg_33 == true and unreg_99 == false:
    print "unregister_ok"

print "PASS"
