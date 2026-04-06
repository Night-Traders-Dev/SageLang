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

## ============================================================
## Generic GPIO (MMIO-based)
## ============================================================

## GPIO controller state
let _gpio_base = 0
let _pin_modes = []
let _pin_count = 0

## Initialize GPIO controller at MMIO base address
proc gpio_init(base, num_pins):
    _gpio_base = base
    _pin_count = num_pins
    _pin_modes = []
    let i = 0
    while i < num_pins:
        push(_pin_modes, PIN_INPUT)
        i = i + 1

## Set pin mode (input/output)
proc pin_mode(pin, mode):
    if pin >= 0 and pin < _pin_count:
        _pin_modes[pin] = mode

## Write digital value to pin
proc digital_write(pin, value):
    if pin >= 0 and pin < _pin_count:
        if _pin_modes[pin] == PIN_OUTPUT:
            let offset = pin * 4
            core.mmio_write32(_gpio_base + offset, value)

## Read digital value from pin
proc digital_read(pin):
    if pin >= 0 and pin < _pin_count:
        let offset = pin * 4
        return core.mmio_read32(_gpio_base + offset) & 1
    return 0

## Toggle pin state
proc digital_toggle(pin):
    let current = digital_read(pin)
    digital_write(pin, 1 - current)

## ============================================================
## LED Helpers (common patterns)
## ============================================================

proc led_on(pin):
    pin_mode(pin, PIN_OUTPUT)
    digital_write(pin, PIN_HIGH)

proc led_off(pin):
    digital_write(pin, PIN_LOW)

proc led_blink(pin, count, delay):
    let i = 0
    while i < count:
        led_on(pin)
        core.delay_ms(delay)
        led_off(pin)
        core.delay_ms(delay)
        i = i + 1
