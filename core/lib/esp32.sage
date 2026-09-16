## esp32.sage — ESP32 (classic) board support for SageLang
##
## Covers the original ESP32 (e.g. ESP32-D0WD-V3, ESP-WROOM-32 / DevKitC):
## dual-core Xtensa LX6 @ 240MHz, 2.4GHz-only WiFi, 4MB SPI flash.
##
##   import esp32
##   if esp32.pin_can_output(2):
##       print "LED pin usable"
##   print esp32.describe()
##
## All helpers are pure (host-runnable); hardware access stays in `metal.*`.

## ============================================================
## Chip identity (verified via esptool: ESP32-D0WD-V3 rev v3.1)
## ============================================================

let CHIP_NAME = "ESP32"
let CHIP_VARIANT = "ESP32-D0WD-V3"
let CPU_ARCH = "Xtensa LX6"
let CPU_CORES = 2
let CPU_FREQ_MHZ = 240
let HAS_LP_CORE = true

## ============================================================
## Radio: 2.4GHz WiFi only — the CYW43-style 5GHz radio does not
## exist on classic ESP32. Boards must join a 2.4GHz SSID.
## ============================================================

let WIFI_BAND_GHZ = 2.4
let WIFI_SUPPORTS_5GHZ = false
let HAS_BT = true
let HAS_BLE = true

## ============================================================
## SPI flash layout (standard 4MB DevKit map, byte offsets)
## ============================================================

let FLASH_SIZE_BYTES = 4194304
let FLASH_BOOTLOADER_OFFSET = 4096
let FLASH_PART_TABLE_OFFSET = 32768
let FLASH_APP_OFFSET = 65536

## First byte of a valid second-stage bootloader image.
let FLASH_BOOT_MAGIC = 233

## First two bytes of a valid partition table.
let FLASH_PART_MAGIC_0 = 170
let FLASH_PART_MAGIC_1 = 80

## ============================================================
## GPIO model: pads are numbered 0..39, but 20, 24, 28, 29, 30
## and 31 do not exist. 34..39 are input-only. 6, 7, 8 and 11
## are wired to the SPI flash — do not use them.
## ============================================================

let GPIO_MIN = 0
let GPIO_MAX = 39
let GPIO_ABSENT = [20, 24, 28, 29, 30, 31]
let GPIO_INPUT_ONLY_FIRST = 34
let GPIO_STRAPPING = [0, 2, 5, 12, 15]
let GPIO_FLASH_PINS = [6, 7, 8, 11]
let GPIO_ADC1_PINS = [32, 33, 34, 35, 36, 37, 38, 39]
let GPIO_DAC_PINS = [25, 26]

## UART0 is the USB-serial console on most DevKits.
let UART0_TX_PIN = 1
let UART0_RX_PIN = 3

## ============================================================
## esptool recipe verified against real hardware
## (CP2102 bridge, ROM bootloader, --no-stub at 115200).
## ============================================================

let ESPTOOL_BAUD = 460800
let ESPTOOL_FALLBACK_BAUD = 115200
let ESPTOOL_FLASH_MODE = "dio"
let ESPTOOL_FLASH_FREQ = "40m"
let ESPTOOL_WRITE_OFFSET = 0

## True when pin names a real ESP32 pad.
@inline
proc pin_valid(pin):
    if pin < GPIO_MIN or pin > GPIO_MAX:
        return false
    for missing in GPIO_ABSENT:
        if pin == missing:
            return false
    return true

## True when pin exists and can drive an output.
@inline
proc pin_can_output(pin):
    if pin_valid(pin) == false:
        return false
    if pin >= GPIO_INPUT_ONLY_FIRST:
        return false
    return true

## True for input-only pads (34..39, e.g. ADC1 sense inputs).
@inline
proc pin_is_input_only(pin):
    if pin_valid(pin) == false:
        return false
    return pin >= GPIO_INPUT_ONLY_FIRST

## True for boot strapping pins (must be safe at reset).
@inline
proc pin_is_strapping(pin):
    for s in GPIO_STRAPPING:
        if pin == s:
            return true
    return false

## True for pads wired to the SPI flash (must stay untouched).
@inline
proc pin_is_flash(pin):
    for f in GPIO_FLASH_PINS:
        if pin == f:
            return true
    return false

## True for ADC1-capable pads (ADC2 clashes with WiFi, so only
## ADC1 is listed here).
@inline
proc adc1_capable(pin):
    for a in GPIO_ADC1_PINS:
        if pin == a:
            return true
    return false

## True for the two DAC pads.
@inline
proc dac_capable(pin):
    for d in GPIO_DAC_PINS:
        if pin == d:
            return true
    return false

## Byte offset of a named flash region, or -1 when unknown.
proc flash_offset(name):
    if name == "bootloader":
        return FLASH_BOOTLOADER_OFFSET
    elif name == "partitions":
        return FLASH_PART_TABLE_OFFSET
    elif name == "app":
        return FLASH_APP_OFFSET
    return -1

## True when a byte equals the bootloader image magic (0xE9).
@inline
proc boot_magic_ok(magic):
    return magic == FLASH_BOOT_MAGIC

## True for the two partition-table magic bytes (0xAA, 0x50).
@inline
proc part_magic_ok(b0, b1):
    return b0 == FLASH_PART_MAGIC_0 and b1 == FLASH_PART_MAGIC_1

## True for esptool flash modes the classic ESP32 accepts.
@inline
proc valid_flash_mode(mode):
    return mode == "qio" or mode == "qout" or mode == "dio" or mode == "dout"

## One-line human summary of the supported chip.
proc describe():
    return CHIP_NAME + " " + CHIP_VARIANT + " (" + CPU_ARCH + " x" + str(CPU_CORES) + " @" + str(CPU_FREQ_MHZ) + "MHz, WiFi " + str(WIFI_BAND_GHZ) + "GHz only)"
