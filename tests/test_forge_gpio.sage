# Test unit for metal.gpio interrupt extensions
import metal.gpio
import metal.core
import assert

core.heap_init(0x1000, 0x1000)
gpio.gpio_init(0x1000, 8)

# Test pin_enable_interrupt_ext and pin_disable_interrupt_ext
gpio.pin_enable_interrupt_ext(3, gpio.INT_RISING)
assert.assert_equal(gpio.pin_get_interrupt(3), gpio.INT_RISING, "Interrupt mode should be INT_RISING")

gpio.pin_disable_interrupt_ext(3)
assert.assert_equal(gpio.pin_get_interrupt(3), gpio.INT_DISABLED, "Interrupt mode should be INT_DISABLED")

# Test internal interrupt trigger state
gpio.pin_set_interrupt(2, gpio.INT_FALLING)
assert.assert_equal(gpio.pin_get_interrupt(2), gpio.INT_FALLING, "Interrupt mode should be INT_FALLING")

print "metal.gpio extension test passed!"
