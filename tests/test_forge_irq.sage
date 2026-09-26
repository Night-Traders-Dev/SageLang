# Unit test for metal.irq safe registration and unregistration helpers
import metal.irq
import assert

let handled_count = 0

proc dummy_handler(vec):
    handled_count = handled_count + 1

# Test initial safe registration
let res1 = irq.register_handler_safe(42, dummy_handler)
assert.assert_true(res1, "register_handler_safe should return true for new vector")

# Test duplicate registration returns false without panicking
let res2 = irq.register_handler_safe(42, dummy_handler)
assert.assert_false(res2, "register_handler_safe should return false for already registered vector")

# Test dispatch works
irq.dispatch(42)
assert.assert_equal(handled_count, 1, "handler should have been executed on dispatch")

# Test unregister_handler
irq.unregister_handler(42)

# Test duplicate registration is possible again after unregistration
let res3 = irq.register_handler_safe(42, dummy_handler)
assert.assert_true(res3, "register_handler_safe should return true after unregister_handler")

# Cleanup
irq.unregister_handler(42)

print "metal.irq extension test passed!"
