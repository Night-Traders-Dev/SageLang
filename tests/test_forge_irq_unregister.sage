# Test unit for metal.irq handler registration and unregistration
import metal.irq
import assert

let handled_vector = -1

## Test interrupt handler procedure
proc my_handler(vector):
    handled_vector = vector

# Test registration and dispatch
irq.register_handler(42, my_handler)
irq.dispatch(42)
assert.assert_equal(handled_vector, 42, "Handler should have been dispatched for vector 42")

# Test unregister handler
handled_vector = -1
irq.unregister_handler(42)
irq.dispatch(42)
assert.assert_equal(handled_vector, -1, "Handler should not execute after being unregistered")

# Test re-registration after unregistering
handled_vector = -1
irq.register_handler(42, my_handler)
irq.dispatch(42)
assert.assert_equal(handled_vector, 42, "Handler should be re-registrable after unregistration")

# Clean up
irq.unregister_handler(42)

print "metal.irq unregister_handler test passed!"
