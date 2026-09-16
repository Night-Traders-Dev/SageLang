## Slow-blink firmware for the classic ESP32 DevKit.
##
## Drives GPIO2 (the usual onboard-LED pad) with a slow 2s period and
## narrates every edge over serial, so a human watching the board can
## match visible blinks against the log. `hw.*` calls map to native
## GPIO in emitted C (see the `hw` native module in the Sage compiler).
## This file is emit-only: `import hw` has no host implementation.
##
##   sage --emit-pico-c core/boards/ESP32/examples/blink.sage

import esp32
import hw

let LED_PIN = 2

print(esp32.describe())
print("ESP32 slow blink start on pin:", LED_PIN)

hw.gpio_init(LED_PIN)
hw.gpio_set_dir(LED_PIN, 1)

var i = 0
while i < 1000000:
    hw.gpio_put(LED_PIN, 1)
    hw.delay_ms(2000)
    print("TICK readback:", hw.gpio_get(LED_PIN))
    hw.gpio_put(LED_PIN, 0)
    hw.delay_ms(2000)
    print("TOCK readback:", hw.gpio_get(LED_PIN))
    i = i + 1

print("blink done")
