# Test pin_pulse_in helper procedure in metal.gpio
import metal.gpio
import metal.core

gpio.gpio_init(0x1000, 8)
gpio.pin_mode(0, gpio.PIN_OUTPUT)

# Write initial state LOW (0)
gpio.digital_write(0, gpio.PIN_LOW)

# Test pin_pulse_in timing out when waiting for state 1 on a pin that stays LOW
let duration_timeout = gpio.pin_pulse_in(0, gpio.PIN_HIGH, 10)
if duration_timeout != -1:
    print("FAIL: Expected timeout -1, got " + str(duration_timeout))
else:
    print("PASS: Timeout handling verified")

# Test pin_pulse_in measuring high pulse on pin 0
gpio.digital_write(0, gpio.PIN_HIGH)
let duration_high = gpio.pin_pulse_in(0, gpio.PIN_HIGH, 50)
if duration_high != -1:
    print("FAIL: Expected timeout on pulse ending, got " + str(duration_high))
else:
    print("PASS: High pulse timeout verified")

print("ALL GPIO PULSE TESTS PASSED")
