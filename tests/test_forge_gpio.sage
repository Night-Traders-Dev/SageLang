## Test unit for metal.gpio interrupt extensions and pin controls
import metal.gpio
import metal.core
import assert

proc test_gpio_interrupt_extensions():
    print "Testing metal.gpio interrupt extensions..."
    core.heap_init(0x1000, 0x1000)
    gpio.gpio_init(0x1000, 8)

    # Test pin_enable_interrupt_ext with INT_RISING
    gpio.pin_enable_interrupt_ext(3, gpio.INT_RISING)
    assert.assert_equal(gpio.pin_get_interrupt(3), gpio.INT_RISING, "Interrupt mode should be INT_RISING")

    # Test pin_disable_interrupt_ext
    gpio.pin_disable_interrupt_ext(3)
    assert.assert_equal(gpio.pin_get_interrupt(3), gpio.INT_DISABLED, "Interrupt mode should be INT_DISABLED")

    # Test pin_enable_interrupt_ext with INT_FALLING
    gpio.pin_enable_interrupt_ext(2, gpio.INT_FALLING)
    assert.assert_equal(gpio.pin_get_interrupt(2), gpio.INT_FALLING, "Interrupt mode should be INT_FALLING")

    # Test pin_enable_interrupt_ext with INT_BOTH
    gpio.pin_enable_interrupt_ext(5, gpio.INT_BOTH)
    assert.assert_equal(gpio.pin_get_interrupt(5), gpio.INT_BOTH, "Interrupt mode should be INT_BOTH")

    print "metal.gpio interrupt extension tests passed!"

proc main():
    test_gpio_interrupt_extensions()

main()
