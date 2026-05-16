import metal.gpio
import metal.core

proc test_gpio():
    print "Testing GPIO improvements (v2)..."

    # Initialize with 8 pins
    gpio.gpio_init(0x4000, 8)

    # Test getters/setters for mode
    gpio.pin_mode(0, gpio.PIN_OUTPUT)
    if gpio.pin_get_mode(0) == gpio.PIN_OUTPUT:
        print "  - pin_get_mode: OK"
    else:
        print "  - pin_get_mode: FAIL (" + str(gpio.pin_get_mode(0)) + ")"

    # Test getters/setters for pull
    gpio.pin_pull(1, gpio.PULL_UP)
    if gpio.pin_get_pull(1) == gpio.PULL_UP:
        print "  - pin_get_pull: OK"
    else:
        print "  - pin_get_pull: FAIL (" + str(gpio.pin_get_pull(1)) + ")"

    # Test getters/setters for interrupt
    gpio.pin_set_interrupt(2, gpio.INT_BOTH)
    if gpio.pin_get_interrupt(2) == gpio.INT_BOTH:
        print "  - pin_get_interrupt: OK"
    else:
        print "  - pin_get_interrupt: FAIL (" + str(gpio.pin_get_interrupt(2)) + ")"

    # We don't verify MMIO effects here as interpreter's MMIO is a stub.

    print "Tests complete."

test_gpio()
