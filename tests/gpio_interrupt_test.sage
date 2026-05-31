import metal.gpio
import assert

let triggered = false

proc my_handler(pin):
    triggered = true
    print "Interrupt triggered on pin " + str(pin)

# Initialize GPIO with 8 pins at base address 0x1000
gpio.gpio_init(4096, 8)

# Register handler for pin 2
gpio.pin_register_handler(2, my_handler)

# Verify handler is called when dispatched
triggered = false
gpio.gpio_dispatch(2)
assert.assert_true(triggered, "Handler should have been triggered")

# Verify handler for different pin is NOT called
triggered = false
gpio.gpio_dispatch(3)
assert.assert_false(triggered, "Handler for pin 3 should not exist")

# Test enable/disable helpers (they just call pin_set_interrupt)
gpio.pin_enable_interrupt(2, gpio.INT_RISING)
assert.assert_equal(gpio.pin_get_interrupt(2), gpio.INT_RISING, "Interrupt mode should be RISING")

gpio.pin_disable_interrupt(2)
assert.assert_equal(gpio.pin_get_interrupt(2), gpio.INT_DISABLED, "Interrupt mode should be DISABLED")

print "GPIO interrupt smoke test passed!"
