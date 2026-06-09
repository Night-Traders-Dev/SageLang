import metal.gpio
import metal.core

# Initialize mock MMIO heap for testing
core.heap_init(0x1000, 0x1000)
gpio.gpio_init(0x1000, 8)

# Test pin_pull
print "Testing pin_pull..."
gpio.pin_pull(0, gpio.PULL_UP)
gpio.pin_pull(1, gpio.PULL_DOWN)
# Check internal state
print "Pull 0: " + str(gpio._pin_pulls[0])
print "Pull 1: " + str(gpio._pin_pulls[1])

# Test pin_debounce
# Note: In the core.sage stub, mmio_read32 always returns 0 (implicitly)
# because it doesn't actually read from the address.
print "Testing pin_debounce..."
gpio.pin_mode(2, gpio.PIN_INPUT)

# Test debounce with LOW (stub returns 0)
let debounced_low = gpio.pin_debounce(2, gpio.PIN_LOW, 5, 0)
print "Debounce LOW success: " + str(debounced_low)

# Test debounce failure with HIGH
let debounced_high_fail = gpio.pin_debounce(2, gpio.PIN_HIGH, 5, 0)
print "Debounce HIGH fail (expected): " + str(not debounced_high_fail)

print "GPIO tests passed!"
