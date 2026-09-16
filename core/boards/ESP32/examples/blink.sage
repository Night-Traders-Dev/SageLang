## ESP32 blink demo plan (host-runnable).
##
## Prints the validated bring-up plan for an onboard-LED blinker on a
## classic ESP32 DevKit. GPIO2 is the common onboard-LED pad; the plan
## is validated with the esp32 board module instead of touching hardware.
##
## Run from the repo root:
##   SAGE_PATH=core/lib ./core/sage core/boards/ESP32/examples/blink.sage

import esp32

let LED_PIN = 2

print esp32.describe()
print("flash app offset:", esp32.flash_offset("app"))

if esp32.pin_can_output(LED_PIN):
    print("LED pin", LED_PIN, "usable for output")
else:
    print("LED pin", LED_PIN, "NOT usable for output")

if esp32.pin_is_strapping(LED_PIN):
    print("note: pin", LED_PIN, "is a strapping pin, keep it high at reset")

print("blink plan: drive pin", LED_PIN, "high 500ms, low 500ms, repeat")
