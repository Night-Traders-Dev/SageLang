## metal.gpio — General Purpose I/O for Bare-Metal
##
## Provides pin control for embedded targets (Pico RP2040, generic MMIO).
## On x86, GPIO is typically accessed via Super I/O chip or PCH.

import metal.core

## ============================================================
## Pin Modes
## ============================================================

let PIN_INPUT    = 0
let PIN_OUTPUT   = 1
let PIN_ALT      = 2
let PIN_ANALOG   = 3

let PIN_LOW  = 0
let PIN_HIGH = 1

let PULL_NONE = 0
let PULL_UP   = 1
let PULL_DOWN = 2

## ============================================================
## Generic GPIO (MMIO-based)
## ============================================================

## GPIO controller state
let _gpio_base = 0
let _pin_modes = []
let _pin_pulls = []
let _pin_count = 0

## Initialize GPIO controller at MMIO base address
proc gpio_init(base, num_pins):
    _gpio_base = base
    _pin_count = num_pins
    _pin_modes = []
    _pin_pulls = []
    let i = 0
    while i < num_pins:
        push(_pin_modes, PIN_INPUT)
        push(_pin_pulls, PULL_NONE)
        i = i + 1

## Set pin mode (input/output)
proc pin_mode(pin, mode):
    if pin >= 0 and pin < _pin_count:
        _pin_modes[pin] = mode

## Set pull-up/pull-down resistor configuration
proc pin_pull(pin, pull):
    if pin >= 0 and pin < _pin_count:
        _pin_pulls[pin] = pull
        # In a real driver, this would write to a hardware register.
        # For the generic MMIO stub, we use an offset from base + (pin_count * 4).
        let pull_offset = (_pin_count * 4) + (pin * 4)
        core.mmio_write32(_gpio_base + pull_offset, pull)

## Debounce a pin: returns true if the pin stays at target_state for N samples.
proc pin_debounce(pin, target_state, samples, delay_ms):
    let j = 0
    while j < samples:
        if digital_read(pin) != target_state:
            return false
        if delay_ms > 0:
            core.delay_ms(delay_ms)
        j = j + 1
    return true

## Write digital value to pin
proc digital_write(pin, value):
    if pin >= 0 and pin < _pin_count:
        if _pin_modes[pin] == PIN_OUTPUT:
            let offset_write = pin * 4
            core.mmio_write32(_gpio_base + offset_write, value)

## Read digital value from pin
proc digital_read(pin):
    if pin >= 0 and pin < _pin_count:
        let offset_read = pin * 4
        return core.mmio_read32(_gpio_base + offset_read) & 1
    return 0

## Toggle pin state
proc digital_toggle(pin):
    let current = digital_read(pin)
    digital_write(pin, 1 - current)

## ============================================================
## LED Helpers (common patterns)
## ============================================================

## Turn an LED on
proc led_on(pin):
    pin_mode(pin, PIN_OUTPUT)
    digital_write(pin, PIN_HIGH)

## Turn an LED off
proc led_off(pin):
    digital_write(pin, PIN_LOW)

## Blink an LED N times
proc led_blink(pin, count, delay):
    let k = 0
    while k < count:
        led_on(pin)
        core.delay_ms(delay)
        led_off(pin)
        core.delay_ms(delay)
        k = k + 1
