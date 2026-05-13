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

print "Testing mask/unmask (stubs)..."
irq.mask_irq(0)
irq.unmask_irq(0)

print "Testing double registration guard (should panic)..."
# We wrap this in a way we can see it fail if the interpreter supports try/catch
# or just let it panic and see the output.
irq.register_handler(42, dummy_handler)
