## ADC reader firmware for the classic ESP32 DevKit.
##
## Samples GPIO34 (input-only, ADC1 channel 6) five times and prints
## raw 12-bit readings plus millivolts at 11 dB attenuation. `hw.*`
## calls map to native ADC in emitted C (see the `hw` native module
## in the Sage compiler). This file is emit-only: `import hw` has no
## host implementation, so build it instead of running it:
##   sage --emit-pico-c core/boards/ESP32/examples/adc_read.sage

import esp32
import hw

let PIN = 34
let ATTEN_DB = 11

print(esp32.describe())
print("adc channel:", esp32.adc1_channel(PIN))

hw.adc_init(PIN)

var i = 0
while i < 5:
    let raw = hw.adc_read(PIN)
    print("ADC raw:", raw)
    print("ADC mV:", esp32.adc_to_mv(raw, ATTEN_DB))
    hw.delay_ms(500)
    i = i + 1

print("adc done")
