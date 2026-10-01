# EXPECT: Testing IRQ depth...
# EXPECT: Initial depth: 0
# EXPECT: Depth after enter: 1
# EXPECT: Depth after second enter: 2
# EXPECT: Depth after exit: 1
# EXPECT: Final depth: 0
# EXPECT: Testing handler registration...
# EXPECT: Handler called for vector 42
# EXPECT: Testing safe handler registration and unregistration...
# EXPECT: Safe reg success: true
# EXPECT: Safe reg duplicate: false
# EXPECT: Unregister success: true
# EXPECT: Unregister non-existent: false
# EXPECT: Testing mask/unmask (stubs)...
# EXPECT: Testing double registration guard (should panic)...
# EXPECT: PANIC: IRQ handler already registered for vector 42
import metal.irq
import metal.core

proc dummy_handler(vector):
    print "Handler called for vector " + str(vector)

print "Testing IRQ depth..."
print "Initial depth: " + str(irq.irq_depth())
irq.irq_enter()
print "Depth after enter: " + str(irq.irq_depth())
irq.irq_enter()
print "Depth after second enter: " + str(irq.irq_depth())
irq.irq_exit()
print "Depth after exit: " + str(irq.irq_depth())
irq.irq_exit()
print "Final depth: " + str(irq.irq_depth())

print "Testing handler registration..."
irq.register_handler(42, dummy_handler)
irq.dispatch(42)

print "Testing safe handler registration and unregistration..."
let ok1 = irq.register_handler_safe(100, dummy_handler)
print "Safe reg success: " + str(ok1)
let ok2 = irq.register_handler_safe(100, dummy_handler)
print "Safe reg duplicate: " + str(ok2)

let un1 = irq.unregister_handler(100)
print "Unregister success: " + str(un1)
let un2 = irq.unregister_handler(100)
print "Unregister non-existent: " + str(un2)

print "Testing mask/unmask (stubs)..."
irq.mask_irq(0)
irq.unmask_irq(0)

print "Testing double registration guard (should panic)..."
irq.register_handler(42, dummy_handler)
