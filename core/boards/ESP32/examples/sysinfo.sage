## System-info firmware for the classic ESP32 DevKit.
##
## Prints uptime, CPU clock, and on-chip temperature twice, one second
## apart — the advancing uptime proves the clock runs, and the two
## temperature samples prove the sensor reads live. `hw.*` calls map
## to native sysinfo in emitted C (see the `hw` native module in the
## Sage compiler). This file is emit-only: `import hw` has no host
## implementation, so build it instead of running it:
##   sage --emit-pico-c core/boards/ESP32/examples/sysinfo.sage

import hw

print("uptime ms:", hw.uptime_ms())
print("clock hz:", hw.clock_hz())
print("temp c:", hw.temp_c())
hw.delay_ms(1000)
print("uptime ms:", hw.uptime_ms())
print("temp c:", hw.temp_c())
print("sysinfo done")
