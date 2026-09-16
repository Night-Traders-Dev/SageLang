## Hello-world firmware source for the classic ESP32 (SageLang).
##
## Built for hardware with the Sage C backend and the Arduino-ESP32
## core, then flashed with esptool. Host check:
##   SAGE_PATH=core/lib ./core/sage core/boards/ESP32/examples/hello.sage

import esp32

print(esp32.describe())
print("Hello from Sage on ESP32!")
