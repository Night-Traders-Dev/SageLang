import metal.irq
import assert

## Test IRQ priority configuration
proc test_priority():
    print "Testing IRQ priority configuration..."

    # Default priority should be 0
    let p0 = irq.get_priority(32)
    assert.assert_equal(p0, 0, "Default priority for vector 32 should be 0")

    # Set priority
    irq.set_priority(32, 5)
    let p1 = irq.get_priority(32)
    assert.assert_equal(p1, 5, "Priority for vector 32 should be 5")

    # Set another priority
    irq.set_priority(33, 10)
    let p2 = irq.get_priority(33)
    assert.assert_equal(p2, 10, "Priority for vector 33 should be 10")

    # Vector 32 should still be 5
    let p1_again = irq.get_priority(32)
    assert.assert_equal(p1_again, 5, "Priority for vector 32 should still be 5")

    print "IRQ priority tests passed!"

test_priority()
