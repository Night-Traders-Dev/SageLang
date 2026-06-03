import metal.gpio
import assert

let interrupt_count = 0

proc my_handler(pin):
    interrupt_count = interrupt_count + 1
    print "Interrupt on pin " + str(pin)

proc test_gpio_interrupts():
    print "Testing GPIO interrupts..."

    # Initialize GPIO with 8 pins at base 0x1000
    gpio.gpio_init(4096, 8)

    # Register handler for pin 2
    gpio.pin_register_handler(2, my_handler)

    # Enable interrupt for pin 2
    gpio.pin_enable_interrupt(2)

    # Simulate interrupt dispatch for pin 2
    gpio.gpio_dispatch(2)

    assert.assert_true(interrupt_count == 1, "Interrupt count should be 1")

    # Simulate another interrupt
    gpio.gpio_dispatch(2)
    assert.assert_true(interrupt_count == 2, "Interrupt count should be 2")

    # Test pin 3 (no handler)
    gpio.gpio_dispatch(3)
    assert.assert_true(interrupt_count == 2, "Interrupt count should still be 2")

    # Disable interrupt for pin 2 (doesn't stop dispatch in stub, but tests the proc)
    gpio.pin_disable_interrupt(2)

    print "GPIO interrupt test passed!"

test_gpio_interrupts()
