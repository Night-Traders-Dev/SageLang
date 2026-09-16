# ESP32 Board Support

SageLang supports the **classic ESP32** (verified on ESP32-D0WD-V3, ESP-WROOM-32
/ DevKitC, 4MB flash): dual-core Xtensa LX6 @ 240MHz.

> **Radio note:** classic ESP32 WiFi is **2.4GHz-only** — there is no 5GHz
> radio. Boards must join a 2.4GHz SSID. See `WIFI_SUPPORTS_5GHZ` in
> `core/lib/esp32.sage`.

## Files

- `core/lib/esp32.sage` — board support module: chip constants, GPIO model
  (pads 0..39 minus absent 20/24/28-31, input-only 34..39, strapping
  0/2/5/12/15, flash-bound 6/7/8/11), UART0 pins (TX 1 / RX 3), standard
  flash offsets (bootloader `0x1000`, partitions `0x8000`, app `0x10000`),
  image magic checks, and the verified esptool recipe constants.
- `core/boards/ESP32/` — board package: `__init__.sage`, `test_smoke.sage`
  (80+ assertions, host-runnable), and `examples/` firmware sources:
  `hello.sage` (first boot print), `blink.sage` (GPIO2 with read-backs),
  `adc_read.sage` (GPIO34 sampling with mV conversion), `sysinfo.sage`
  (uptime/clock/temperature, verified live: 240MHz, ~42°C die),
  `deep_sleep.sage` (5s timer-wakeup sleep loop, verified by reboot cadence).
- `hw.deep_sleep_us(us)` is a compiler-mapped native (`core/src/c/compiler.c`):
  no-op on host/Pico builds, timer-wakeup sleep on ESP32-Arduino. Deep
  sleep always wakes with a reset, so firmware should expect reboot, not
  return — verified by ~7s boot cycles with small uptimes and zero returns.
- `testsuite/unit/26_stdlib/esp32_board_test.sage` — suite test.

## Peripherals and helpers (`esp32.*`)

- **GPIO**: `pin_valid`, `pin_can_output`, `pin_is_input_only`,
  `pin_is_strapping`, `pin_is_flash`.
- **ADC**: `adc1_channel(pin)` maps pads to ADC1 channels 0..7 (`-1` when
  none — use ADC1 because ADC2 clashes with WiFi);
  `adc_fullscale_mv(atten_db)` gives the approximate full scale for
  0/2.5/6/11 dB; `adc_to_mv(raw, atten_db)` converts 12-bit readings,
  `-1` on bad input.
- **Touch / RTC**: `touch_channel(pin)` maps pads to T0..T9 (`-1` when
  none); `rtc_capable(pin)` lists deep-sleep wake pads.
- **PWM**: `pwm_duty(percent, bits)` returns floored duty counts over the
  16 LEDC channels (e.g. `pwm_duty(50, 8)` is 127).
- **UART**: UART0 is the USB-serial console (TX 1 / RX 3);
  `uart_needs_remap(uart)` is true only for UART1, whose defaults
  (TX 10 / RX 9) sit on flash pads — UART2 defaults (TX 17 / RX 16)
  are free.
- **Flashing**: `image_size_ok(size)` fits against the 4MB part;
  `esptool_write_cmd(port, image)` renders the verified write command.
- **I2C**: two buses (`I2C_COUNT`), Wire defaults SDA 21 / SCL 22;
  `i2c_addr_usable(addr)` rejects reserved 7-bit ranges;
  `i2c_freq_ok(freq)` accepts the standard 100k/400k/1M rates.
- **Power planning**: `adc_atten_for_voltage(mv)` picks the smallest
  attenuation covering a sensor's max output; `ext1_mask(pins)` builds
  the EXT1 wake bitmask (`-1` on non-RTC pads);
  `battery_hours(cap_mah, sleep_ua, active_ma, active_s_per_h)`
  estimates duty-cycled node lifetime.

Run the smoke test from the repo root:

```bash
SAGE_PATH=core/lib ./core/sage core/boards/ESP32/test_smoke.sage
```

## Flashing CircuitPython (recovery / REPL firmware)

For a generic DevKit over its USB-serial bridge (`/dev/ttyUSB0`), using the
`espressif_esp32_devkitc_v4_wroom_32e` build (full flash image for offset
`0x0`; bootloader magic `0xE9` at `0x1000`):

```bash
esptool --port /dev/ttyUSB0 --baud 115200 --no-stub erase-region 0x0 0x400000
esptool --port /dev/ttyUSB0 --baud 460800 --no-stub \
  write-flash --flash-mode dio --flash-size detect --flash-freq 40m \
  -z 0x0 adafruit-circuitpython-...-en_US-10.3.1.bin
```

Notes from real hardware:

- Prefer `--no-stub` at 115200 baud for the handshake if the stub flasher
  fails to start; 460800 baud is fine for the bulk write.
- ROM mode has no chip-erase; `erase-region 0x0 0x400000` covers a 4MB part.
- The REPL answers on the serial port at 115200 baud.
- Classic ESP32 has no native USB: the board always appears as the external
  UART bridge (e.g. CP2102 on `/dev/ttyUSB0`); there is no CIRCUITPY drive.
- Reopening the serial port usually reboots the board (DTR reset).

## Building Sage firmware (Arduino-ESP32)

The Sage C backend (`--emit-pico-c`) emits a self-contained C file. For
ESP32 it is built against the Arduino-ESP32 core:

1. Emit: `sage --emit-pico-c <prog>.sage -o prog.c`
2. Adapt `prog.c`: drop the `pico/*` + `hardware/*` includes, add a
   FreeRTOS `sleep_ms` shim, rename `main()` to a callable entry, and stub
   what ESP32 newlib lacks (`dlsym`, POSIX semaphores).
3. Hardware access: the emitter maps `hw.gpio_*` / `hw.delay_*` calls to
   `sage_native_hw_*` C functions. Implement those bodies against Arduino
   (`pinMode` / `digitalWrite` / `digitalRead`) via a small
   `extern "C"` shim file — see `blink.sage`, which toggles GPIO2 and
   verifies each write with a read-back. `hw.adc_init` / `hw.adc_read`
   map the same way (`analogSetPinAttenuation` at 11 dB + `analogRead`);
   see `adc_read.sage`, verified live on GPIO34 (a floating pad reads
   near 0V with residual charge on the first sample — healthy behavior,
   not a stuck peripheral).
4. Sketch `.ino`: `Serial.begin(115200)`, call the entry once from
   `setup()`, idle in `loop()`.
5. Compile for `esp32:esp32:esp32` (4MB Dev Module profile), upload over
   the USB-serial port, and watch the output at 115200 baud. Plain C
   `printf` reaches UART0 through the ESP-IDF console.

`print` output and `hw.gpio_get` read-backs over serial are the
headless verification path: there is no screen on the bench, so every
firmware example prints what it does and reads back what it drove.

If the port ever streams framing-error zeros instead of text, the board
is likely wedged in reset/download mode from manual DTR/RTS fiddling —
recover with a proper reset (`esptool ... chip-id` ends in a hard reset
via RTS) and then open the port without touching the modem lines.
