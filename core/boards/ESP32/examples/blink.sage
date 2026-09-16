## Blink firmware for the classic ESP32 DevKit (onboard LED on GPIO2).
##
## `hw.*` calls map to native GPIO in emitted C (see the `hw` native
## module in the Sage compiler). This file is emit-only: `import hw`
## has no host implementation, so build it instead of running it:
##   sage --emit-pico-c core/boards/ESP32/examples/blink.sage
##
## Each drive is verified with a read-back; on ESP32, digitalRead on
## an output pad returns the latched level, so the serial log proves
## the peripheral toggled even with no eyes on the board.

import esp32
import hw

let LED_PIN = 2

print(esp32.describe())
print("ESP32 blink start")

hw.gpio_init(LED_PIN)
hw.gpio_set_dir(LED_PIN, 1)

var i = 0
while i < 5:
    hw.gpio_put(LED_PIN, 1)
    hw.delay_ms(500)
    print("LED ON readback:", hw.gpio_get(LED_PIN))
    hw.gpio_put(LED_PIN, 0)
    hw.delay_ms(500)
    print("LED OFF readback:", hw.gpio_get(LED_PIN))
    i = i + 1

print("blink done")
