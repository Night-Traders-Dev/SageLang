## ESP32 board support smoke test (host-runnable, no hardware needed).
##
## Run from the repo root:
##   SAGE_PATH=core/lib ./core/sage core/boards/ESP32/test_smoke.sage

import esp32

var failed = false

proc check(name, got, want):
    if got != want:
        print("FAIL", name, "got", got, "want", want)
        failed = true

check("chip", esp32.CHIP_NAME, "ESP32")
check("cores", esp32.CPU_CORES, 2)
check("freq", esp32.CPU_FREQ_MHZ, 240)
check("wifi-2.4-only", esp32.WIFI_SUPPORTS_5GHZ, false)
check("flash-size", esp32.FLASH_SIZE_BYTES, 4194304)
check("boot-offset", esp32.flash_offset("bootloader"), 4096)
check("part-offset", esp32.flash_offset("partitions"), 32768)
check("app-offset", esp32.flash_offset("app"), 65536)
check("unknown-region", esp32.flash_offset("nvs"), -1)
check("pin0-valid", esp32.pin_valid(0), true)
check("pin20-absent", esp32.pin_valid(20), false)
check("pin39-valid", esp32.pin_valid(39), true)
check("pin40-invalid", esp32.pin_valid(40), false)
check("pin2-output", esp32.pin_can_output(2), true)
check("pin34-no-output", esp32.pin_can_output(34), false)
check("pin34-input-only", esp32.pin_is_input_only(34), true)
check("pin2-not-input-only", esp32.pin_is_input_only(2), false)
check("pin0-strapping", esp32.pin_is_strapping(0), true)
check("pin1-not-strapping", esp32.pin_is_strapping(1), false)
check("pin6-flash", esp32.pin_is_flash(6), true)
check("pin2-not-flash", esp32.pin_is_flash(2), false)
check("adc1-32", esp32.adc1_capable(32), true)
check("adc1-27", esp32.adc1_capable(27), false)
check("dac-25", esp32.dac_capable(25), true)
check("dac-26", esp32.dac_capable(26), true)
check("dac-27", esp32.dac_capable(27), false)
check("boot-magic", esp32.boot_magic_ok(233), true)
check("boot-magic-bad", esp32.boot_magic_ok(0), false)
check("part-magic", esp32.part_magic_ok(170, 80), true)
check("part-magic-bad", esp32.part_magic_ok(0, 0), false)
check("flash-mode-dio", esp32.valid_flash_mode("dio"), true)
check("flash-mode-bogus", esp32.valid_flash_mode("sdio"), false)
check("uart0-tx", esp32.UART0_TX_PIN, 1)
check("uart0-rx", esp32.UART0_RX_PIN, 3)

if failed:
    print("SMOKE FAIL")
else:
    print("ALL OK: ESP32 board support")
    print(esp32.describe())
