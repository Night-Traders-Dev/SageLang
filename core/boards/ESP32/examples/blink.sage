## Blink firmware for the classic ESP32 DevKit.
##
## Sweeps the common onboard-LED candidate pads, blinking each one
## while narrating over serial. Strapping pads (0/5/12/15), flash
## pads (6/7/8/11) and input-only pads (34..39) are never touched.
## Onboard LEDs vary by vendor (usually GPIO2), so the sweep finds
## whichever pad actually lights the blue LED. Watch the board and
## note which "probing pin" line matches visible blinking.
##
## `hw.*` calls map to native GPIO in emitted C (see the `hw` native
## module in the Sage compiler). This file is emit-only: `import hw`
## has no host implementation, so build it instead of running it:
##   sage --emit-pico-c core/boards/ESP32/examples/blink.sage

import esp32
import hw

let PINS = [2, 4, 16, 17, 18, 19, 21, 22, 23]

print(esp32.describe())
print("ESP32 LED sweep start")

for pin in PINS:
    if esp32.pin_can_output(pin):
        print("probing pin:", pin)
        hw.gpio_init(pin)
        hw.gpio_set_dir(pin, 1)
        var k = 0
        while k < 3:
            hw.gpio_put(pin, 1)
            hw.delay_ms(400)
            print("pin", pin, "ON readback:", hw.gpio_get(pin))
            hw.gpio_put(pin, 0)
            hw.delay_ms(400)
            print("pin", pin, "OFF readback:", hw.gpio_get(pin))
            k = k + 1

print("sweep done, repeating")

var round = 1
while round < 1000:
    print("sweep round:", round)
    for pin in PINS:
        hw.gpio_put(pin, 1)
        hw.delay_ms(400)
        hw.gpio_put(pin, 0)
        hw.delay_ms(400)
    round = round + 1

print("blink done")
