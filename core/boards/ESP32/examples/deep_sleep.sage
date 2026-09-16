## Deep-sleep demo for the classic ESP32 DevKit.
##
## Prints uptime, sleeps 5 seconds on the timer wakeup source, and
## reboots: deep sleep always wakes with a reset, so a healthy board
## prints the boot lines again roughly every 6-7 seconds with a small
## uptime each time. The "ERROR" line must never appear. `hw.*` calls
## map to native sleep in emitted C (see the `hw` native module in
## the Sage compiler). This file is emit-only: `import hw` has no
## host implementation, so build it instead of running it:
##   sage --emit-pico-c core/boards/ESP32/examples/deep_sleep.sage

import hw

print("booted, uptime ms:", hw.uptime_ms())
print("sleeping 5s")
hw.deep_sleep_us(5000000)
print("ERROR: returned from deep sleep")
