import metal.gpio
import assert

let handler_called = false
let handler_pin = -1

proc my_handler(pin):
    handler_called = true
    handler_pin = pin

proc test_gpio_interrupts():
    # Initialize with 8 pins
    gpio.gpio_init(0x40000000, 8)

    # Register handler for pin 2
    gpio.pin_register_handler(2, my_handler)

    # Initial state
    assert.assert_false(handler_called, "Handler should not be called yet")

    # Dispatch pin 2
    gpio.gpio_dispatch(2)

    # Verify handler was called
    assert.assert_true(handler_called, "Handler should have been called")
    assert.assert_equal(handler_pin, 2, "Handler should receive correct pin number")

    # Reset and test unregistered pin
    handler_called = false
    gpio.gpio_dispatch(3)
    assert.assert_false(handler_called, "Handler should not be called for unregistered pin")

    print "GPIO interrupt test passed!"

test_gpio_interrupts()
